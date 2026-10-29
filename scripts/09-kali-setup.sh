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

log "== Instalacao do Kali =="
ensure_network

log "Construindo imagem lab-kali:latest..."
run docker build -t lab-kali:latest "$ROOT_DIR/docker/kali"

remove_container lab-kali

log "Subindo lab-kali em 172.28.0.13..."
run docker run -d \
  --name lab-kali \
  --network lab-net \
  --ip 172.28.0.13 \
  -v "$ROOT_DIR/wordlists:/wordlists:ro" \
  -v "$ROOT_DIR/logs:/logs" \
  --sysctl "net.ipv4.ip_local_port_range=1024 65535" \
  --sysctl net.ipv4.tcp_tw_reuse=1 \
  lab-kali:latest

sleep 1

if [[ "$(docker inspect -f '{{.State.Running}}' lab-kali 2>/dev/null || true)" != "true" ]]; then
  log "ERRO: lab-kali nao iniciou"
  docker logs lab-kali 2>&1 | tail -n 50 | tee -a "$LOG_FILE" || true
  exit 1
fi

log "Validando ferramentas..."
run docker exec lab-kali medusa -V
run docker exec lab-kali smbclient --version
run docker exec lab-kali nmap --version
run docker exec lab-kali curl --version

if ! docker exec lab-kali enum4linux -h >/dev/null 2>&1; then
  log "AVISO: enum4linux -h retornou erro; verificando comando..."
  run docker exec lab-kali command -v enum4linux
fi

ip="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' lab-kali)"
log "OK: lab-kali ativo em $ip"
log "== Kali pronto =="
