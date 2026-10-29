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
Uso: 04-ftp-test.sh --credentials <arquivo>
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

if [[ "$(docker inspect -f '{{.State.Running}}' lab-ftp 2>/dev/null || true)" != "true" ]]; then
  log "ERRO: lab-ftp nao esta em execucao; rode 03-ftp-install-config.sh primeiro"
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

log "== Testes do FTP =="
log "Credencial positiva: $TEST_USER"

docker run --rm --network lab-net \
  --name lab-ftp-test \
  -e TEST_USER="$TEST_USER" \
  -e TEST_PASS="$TEST_PASS" \
  -i debian:12 bash -s 2>&1 <<'INNER' | tee -a "$LOG_FILE"
set -e
apt-get update -qq >/dev/null
apt-get install -y -qq curl >/dev/null

echo "Teste positivo: login e listagem"
curl -sS --fail --user "$TEST_USER:$TEST_PASS" "ftp://172.28.0.10/" >/dev/null
echo "OK: login positivo"

echo "Teste negativo: senha incorreta"
if curl -sS --user "$TEST_USER:senha-incorreta-$$" "ftp://172.28.0.10/" >/dev/null 2>&1; then
  echo "ERRO: login negativo passou"
  exit 1
else
  echo "OK: login negativo falhou"
fi
INNER

log "== Testes do FTP concluidos =="
