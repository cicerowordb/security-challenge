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
Uso: 03-ftp-install-config.sh --credentials <arquivo>

O arquivo deve conter pares usuario:senha, um por linha.
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

CREDENTIALS="$(cd "$(dirname "$CREDENTIALS")" && pwd)/$(basename "$CREDENTIALS")"

ensure_network() {
  if docker network inspect lab-net >/dev/null 2>&1; then
    local subnet
    subnet="$(docker network inspect -f '{{range .IPAM.Config}}{{.Subnet}}{{end}}' lab-net)"
    if [[ "$subnet" != "172.28.0.0/16" ]]; then
      log "ERRO: lab-net existe com subnet '$subnet'; esperado 172.28.0.0/16"
      exit 1
    fi
    log "Rede lab-net ja existe"
  else
    run docker network create \
      --driver bridge \
      --subnet 172.28.0.0/16 \
      --gateway 172.28.0.1 \
      lab-net
    log "Rede lab-net criada"
  fi
}

remove_container() {
  local name=$1
  if docker container inspect "$name" >/dev/null 2>&1; then
    run docker rm -f "$name"
    log "Container $name removido"
  fi
}

wait_for_process() {
  local container=$1
  local process=$2
  local timeout=${3:-60}
  local i
  for ((i = 0; i < timeout; i++)); do
    if docker exec "$container" pgrep -x "$process" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  log "ERRO: processo '$process' nao iniciou em '$container'"
  docker logs "$container" 2>&1 | tail -n 50 | tee -a "$LOG_FILE" || true
  return 1
}

log "== Instalacao e configuracao do FTP =="
ensure_network

log "Construindo imagem lab-ftp:latest..."
run docker build -t lab-ftp:latest "$ROOT_DIR/docker/ftp"

remove_container lab-ftp

log "Subindo lab-ftp em 172.28.0.10..."
run docker run -d \
  --name lab-ftp \
  --network lab-net \
  --ip 172.28.0.10 \
  -e CREDENTIALS_FILE=/run/credentials.txt \
  -v "$CREDENTIALS:/run/credentials.txt:ro" \
  -v "$ROOT_DIR/logs:/logs" \
  lab-ftp:latest

log "Aguardando vsftpd..."
wait_for_process lab-ftp vsftpd 30

ip="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' lab-ftp)"
log "OK: lab-ftp ativo em $ip"
log "Credenciais usadas: $CREDENTIALS"
log "== FTP pronto =="
