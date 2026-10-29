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
Uso: 06-web-test.sh --credentials <arquivo>
EOF
}

CREDENTIALS=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --credentials)
      CREDENTIALS="${2:-}"
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

if [[ -z "$CREDENTIALS" ]]; then
  log "ERRO: --credentials e obrigatorio"
  usage
  exit 1
fi

if [[ ! -f "$CREDENTIALS" ]]; then
  log "ERRO: arquivo de credenciais nao encontrado: $CREDENTIALS"
  exit 1
fi

if [[ "$(docker inspect -f '{{.State.Running}}' lab-web 2>/dev/null || true)" != "true" ]]; then
  log "ERRO: lab-web nao esta em execucao; rode 05-web-install-config.sh primeiro"
  exit 1
fi

TEST_USER=""
TEST_PASS=""
while IFS=: read -r user pass; do
  [[ -z "${user:-}" ]] && continue
  [[ "$user" == \#* ]] && continue
  TEST_USER="$user"
  TEST_PASS="$pass"
  break
done < "$CREDENTIALS"

if [[ -z "$TEST_USER" ]]; then
  log "ERRO: nenhuma credencial valida em $CREDENTIALS"
  exit 1
fi

log "== Testes do Web/DVWA =="
log "Credencial positiva: $TEST_USER"

docker run --rm --network lab-net \
  --name lab-web-test \
  -e TEST_USER="$TEST_USER" \
  -e TEST_PASS="$TEST_PASS" \
  -i debian:12 bash -s 2>&1 <<'INNER' | tee -a "$LOG_FILE"
set -e
apt-get update -qq >/dev/null
apt-get install -y -qq curl >/dev/null

echo "Teste positivo: login no DVWA"
COOKIE=$(mktemp)
TOKEN=$(curl -s -c "$COOKIE" http://172.28.0.11/DVWA/login.php | awk -F"value='" '/user_token/ {print $2}' | cut -d"'" -f1)
BODY=$(curl -s -L -b "$COOKIE" -c "$COOKIE" -d "username=$TEST_USER&password=$TEST_PASS&user_token=$TOKEN&Login=Login" http://172.28.0.11/DVWA/login.php)
if printf '%s' "$BODY" | grep -q "You have logged in as"; then
  echo "OK: login positivo"
else
  echo "ERRO: login positivo falhou"
  exit 1
fi

echo "Teste negativo: senha incorreta"
COOKIE2=$(mktemp)
TOKEN2=$(curl -s -c "$COOKIE2" http://172.28.0.11/DVWA/login.php | awk -F"value='" '/user_token/ {print $2}' | cut -d"'" -f1)
BODY2=$(curl -s -L -b "$COOKIE2" -c "$COOKIE2" -d "username=$TEST_USER&password=senha-incorreta&user_token=$TOKEN2&Login=Login" http://172.28.0.11/DVWA/login.php)
if printf '%s' "$BODY2" | grep -q "Login failed"; then
  echo "OK: login negativo falhou"
else
  echo "ERRO: login negativo nao exibiu mensagem de falha"
  exit 1
fi
INNER

log "== Testes do Web/DVWA concluidos =="
