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
Uso: 05-web-install-config.sh --credentials <arquivo>

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

log "== Instalacao e configuracao do Web/DVWA =="
ensure_network

log "Construindo imagem lab-web:latest..."
run docker build -t lab-web:latest "$ROOT_DIR/docker/web"

remove_container lab-web

log "Subindo lab-web em 172.28.0.11..."
run docker run -d \
  --name lab-web \
  --network lab-net \
  --ip 172.28.0.11 \
  -v "$CREDENTIALS:/run/credentials.txt:ro" \
  -v "$ROOT_DIR/logs:/logs" \
  lab-web:latest

log "Aguardando o servidor web..."
HTTP_CODE=""
for ((i = 0; i < 120; i++)); do
  HTTP_CODE="$(docker exec lab-web curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1/DVWA/setup.php 2>/dev/null || true)"
  if [[ "$HTTP_CODE" =~ ^[1-5][0-9][0-9]$ ]]; then
    break
  fi
  sleep 1
done

if [[ ! "$HTTP_CODE" =~ ^[1-5][0-9][0-9]$ ]]; then
  log "ERRO: o servidor web nao respondeu"
  docker logs lab-web 2>&1 | tail -n 50 | tee -a "$LOG_FILE" || true
  exit 1
fi

log "Servidor web respondeu com HTTP $HTTP_CODE"
log "Executando setup do DVWA..."

docker exec -i lab-web bash -s 2>&1 <<'INNER' | tee -a "$LOG_FILE"
set -e
COOKIE=/tmp/dvwa-setup.cookie
rm -f "$COOKIE"
TOKEN=$(curl -s -c "$COOKIE" http://127.0.0.1/DVWA/setup.php | awk -F"value='" '/user_token/ {print $2}' | cut -d"'" -f1)
if [ -n "$TOKEN" ]; then
  DATA="create_db=1&user_token=$TOKEN"
else
  DATA="create_db=1"
fi
RESP=$(curl -s -L -b "$COOKIE" -c "$COOKIE" -d "$DATA" http://127.0.0.1/DVWA/setup.php)
if printf '%s' "$RESP" | grep -qiE 'Setup successful|Database has been created'; then
  echo "OK: setup do DVWA concluido"
else
  printf '%s\n' "$RESP"
  echo "ERRO: setup do DVWA falhou"
  exit 1
fi
INNER

log "Inserindo usuarios no DVWA..."
docker exec lab-web mariadb --socket=/run/mysqld/mysqld.sock -u root -e "DELETE FROM dvwa.users;"

idx=100
while IFS=: read -r user pass; do
  [[ -z "${user:-}" ]] && continue
  [[ "$user" == \#* ]] && continue

  SQL="DELETE FROM dvwa.users WHERE user='$user' OR user_id=$idx;"
  SQL+=" INSERT INTO dvwa.users (user_id, first_name, last_name, user, password, avatar, last_login, failed_login)"
  SQL+=" VALUES ($idx, '', '', '$user', MD5('$pass'), '', NOW(), 0);"

  docker exec lab-web mariadb --socket=/run/mysqld/mysqld.sock -u root -e "$SQL"
  log "  usuario inserido: $user"
  idx=$((idx + 1))
done < "$CREDENTIALS"

COUNT="$(docker exec lab-web mariadb --socket=/run/mysqld/mysqld.sock -u root -N -B -e 'SELECT COUNT(*) FROM dvwa.users;')"
log "Usuarios no DVWA: $COUNT"
if [[ "$COUNT" != "9" ]]; then
  log "ERRO: esperado 9 usuarios no DVWA"
  exit 1
fi

ip="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' lab-web)"
log "OK: lab-web ativo em $ip"
log "Credenciais usadas: $CREDENTIALS"
log "== Web/DVWA pronto =="
