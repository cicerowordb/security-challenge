#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0" .sh)"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

KEEP_LOGS=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --keep-logs)
      KEEP_LOGS=1
      shift
      ;;
    -h|--help)
      cat >&2 <<'EOF'
Uso: 99-teardown.sh [--keep-logs]

Remove containers, rede e imagens do laboratorio.
--keep-logs preserva logs/ e images/.
EOF
      exit 0
      ;;
    *)
      echo "ERRO: opcao desconhecida: $1" >&2
      exit 1
      ;;
  esac
done

START_TS=$(date +%s)

echo "== Teardown do laboratorio =="

for container in lab-kali lab-web lab-smb lab-ftp; do
  if docker container inspect "$container" >/dev/null 2>&1; then
    docker rm -f "$container" >/dev/null
    echo "Container removido: $container"
  fi
done

if docker network inspect lab-net >/dev/null 2>&1; then
  docker network rm lab-net >/dev/null
  echo "Rede removida: lab-net"
fi

for image in lab-kali:latest lab-web:latest lab-smb:latest lab-ftp:latest; do
  if docker image inspect "$image" >/dev/null 2>&1; then
    docker rmi "$image" >/dev/null
    echo "Imagem removida: $image"
  fi
done

if ((KEEP_LOGS == 0)); then
  rm -rf "$ROOT_DIR/logs" "$ROOT_DIR/images"
  mkdir -p "$ROOT_DIR/logs" "$ROOT_DIR/images"
  echo "logs/ e images/ limpos"
else
  echo "logs/ e images/ preservados"
fi

LOG_DIR="$ROOT_DIR/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/${SCRIPT_NAME}-$(date +%Y%m%d-%H%M%S).log"
if [[ -e "$LOG_FILE" ]]; then
  LOG_FILE="${LOG_FILE%.log}-$$.log"
fi

log() {
  printf '%s\n' "$*" | tee -a "$LOG_FILE"
}

END_TS=$(date +%s)
ELAPSED=$((END_TS - START_TS))
log "Teardown concluido"
log "$(printf 'Tempo total: %02d:%02d:%02d' \
  $((ELAPSED / 3600)) \
  $(((ELAPSED % 3600) / 60)) \
  $((ELAPSED % 60)))"
