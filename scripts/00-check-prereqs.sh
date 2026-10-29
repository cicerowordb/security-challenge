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

fail() {
  log "ERRO: $*"
  exit 1
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

log "===== Verificacao de pre-requisitos ====="

for cmd in curl awk sed grep wc date mktemp git; do
  command -v "$cmd" >/dev/null 2>&1 || fail "comando auxiliar ausente: $cmd"
done
log "OK: comandos auxiliares presentes"

command -v docker >/dev/null 2>&1 || fail "docker nao encontrado no PATH"
log "OK: docker encontrado"

if ! docker info >/dev/null 2>&1; then
  fail "Docker daemon inacessivel; verifique se o servico esta rodando e se o usuario tem permissao"
fi
log "OK: Docker daemon acessivel"

current_user="$(id -un)"
if id -nG "$current_user" | grep -qw docker; then
  log "OK: usuario '$current_user' esta no grupo docker"
else
  log "AVISO: usuario '$current_user' nao esta no grupo docker, mas o acesso ao daemon funcionou"
fi

for image in debian:12 kalilinux/kali-rolling; do
  if docker image inspect "$image" >/dev/null 2>&1; then
    log "OK: imagem base presente: $image"
  else
    log "AVISO: imagem base ausente: $image (sera baixada durante o build)"
  fi
done

if docker network inspect lab-net >/dev/null 2>&1; then
  subnet="$(docker network inspect -f '{{range .IPAM.Config}}{{.Subnet}}{{end}}' lab-net)"
  if [[ "$subnet" != "172.28.0.0/16" ]]; then
    fail "a rede lab-net existe com subnet '$subnet'; esperado 172.28.0.0/16"
  fi
  log "OK: rede lab-net existe com subnet 172.28.0.0/16"
else
  for net in $(docker network ls --format '{{.Name}}'); do
    sub="$(docker network inspect -f '{{range .IPAM.Config}}{{.Subnet}} {{end}}' "$net" 2>/dev/null || true)"
    if [[ "$sub" == *"172.28.0.0/16"* ]]; then
      fail "a subnet 172.28.0.0/16 ja esta em uso pela rede '$net'"
    fi
  done
  log "OK: subnet 172.28.0.0/16 livre"
fi

avail_kb="$(df -Pk "$ROOT_DIR" | awk 'NR==2 {print $4}')"
required_kb=$((5 * 1024 * 1024))
if ((avail_kb < required_kb)); then
  fail "espaco em disco insuficiente: $((avail_kb / 1024 / 1024)) GiB disponiveis; minimo 5 GiB"
fi
log "OK: espaco em disco: $((avail_kb / 1024 / 1024)) GiB disponiveis"

mem_avail_kb="$(awk '/MemAvailable/ {print $2}' /proc/meminfo)"
required_mem_kb=$((4 * 1024 * 1024))
if ((mem_avail_kb < required_mem_kb)); then
  fail "memoria disponivel insuficiente: $((mem_avail_kb / 1024 / 1024)) GiB; minimo 4 GiB"
fi
log "OK: memoria disponivel: $((mem_avail_kb / 1024 / 1024)) GiB"


log "===== Pre-requisitos atendidos ====="
