#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0" .sh)"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORDLISTS="$ROOT_DIR/wordlists"
LOGS="$ROOT_DIR/logs"
GENERATOR="$ROOT_DIR/scripts/01-password-generator.sh"
mkdir -p "$WORDLISTS" "$LOGS"

LOG_FILE="$LOGS/${SCRIPT_NAME}-$(date +%Y%m%d-%H%M%S).log"
if [[ -e "$LOG_FILE" ]]; then
  LOG_FILE="${LOG_FILE%.log}-$$.log"
fi

TMP_DIR="$(mktemp -d)"
START_TS=$(date +%s)

log() {
  printf '%s\n' "$*" | tee -a "$LOG_FILE"
}

finish() {
  local end_ts elapsed
  rm -rf "$TMP_DIR"
  end_ts=$(date +%s)
  elapsed=$((end_ts - START_TS))
  log "$(printf 'Tempo total: %02d:%02d:%02d' \
    $((elapsed / 3600)) \
    $(((elapsed % 3600) / 60)) \
    $((elapsed % 60)))"
}
trap finish EXIT

if [[ ! -x "$GENERATOR" ]]; then
  log "ERRO: gerador nao encontrado ou sem permissao: $GENERATOR"
  exit 1
fi

log "== Geracao das wordlists =="

cat > "$WORDLISTS/users.txt" <<'USERS'
admin
administrator
root
user
test
guest
support
backup
adm
USERS

cp "$WORDLISTS/users.txt" "$WORDLISTS/trial1-users.txt"
printf 'admin\n' > "$WORDLISTS/trial2-users.txt"
printf 'admin\n' > "$WORDLISTS/trial3-users.txt"

log "Gerando trial1-passwords.txt (ddll, 58.500 linhas)..."
"$GENERATOR" --pattern ddll --all > "$WORDLISTS/trial1-passwords.txt" 2>> "$LOG_FILE"

log "Gerando trial3-passwords.txt (dddll, 468.000 linhas)..."
"$GENERATOR" --pattern dddll --all > "$WORDLISTS/trial3-passwords.txt" 2>> "$LOG_FILE"

cp "$WORDLISTS/trial1-passwords.txt" "$WORDLISTS/trial2-passwords.txt"

log "Gerando senhas aleatorias para os demais usuarios..."
"$GENERATOR" --pattern ddll --random --count 16 --seed 42 > "$TMP_DIR/random00.txt" 2>> "$LOG_FILE"
"$GENERATOR" --pattern dddll --random --count 16 --seed 43 > "$TMP_DIR/random000.txt" 2>> "$LOG_FILE"

mapfile -t ALL_RANDOM_00 < "$TMP_DIR/random00.txt"
mapfile -t ALL_RANDOM_000 < "$TMP_DIR/random000.txt"

RANDOM_00=()
for p in "${ALL_RANDOM_00[@]}"; do
  [[ "$p" == "12ab" ]] && continue
  RANDOM_00+=("$p")
  (( ${#RANDOM_00[@]} == 8 )) && break
done

RANDOM_000=()
for p in "${ALL_RANDOM_000[@]}"; do
  [[ "$p" == "123ab" ]] && continue
  RANDOM_000+=("$p")
  (( ${#RANDOM_000[@]} == 8 )) && break
done

if (( ${#RANDOM_00[@]} < 8 )); then
  log "ERRO: nao foi possivel gerar 8 senhas aleatorias ddll"
  exit 1
fi

if (( ${#RANDOM_000[@]} < 8 )); then
  log "ERRO: nao foi possivel gerar 8 senhas aleatorias dddll"
  exit 1
fi

log "Montando trial1-credentials.txt..."
idx=0
: > "$WORDLISTS/trial1-credentials.txt"
while IFS= read -r user; do
  if [[ "$user" == "backup" ]]; then
    pass="12ab"
  else
    pass="${RANDOM_00[$idx]}"
    idx=$((idx + 1))
  fi
  printf '%s:%s\n' "$user" "$pass" >> "$WORDLISTS/trial1-credentials.txt"
done < "$WORDLISTS/users.txt"

declare -A T1_PASS=()
while IFS=: read -r user pass; do
  [[ -z "${user:-}" ]] && continue
  T1_PASS[$user]="$pass"
done < "$WORDLISTS/trial1-credentials.txt"

log "Montando trial2-credentials.txt..."
: > "$WORDLISTS/trial2-credentials.txt"
while IFS= read -r user; do
  if [[ "$user" == "admin" ]]; then
    pass="12ab"
  elif [[ "$user" == "backup" ]]; then
    pass="${T1_PASS[admin]}"
  else
    pass="${T1_PASS[$user]}"
  fi
  printf '%s:%s\n' "$user" "$pass" >> "$WORDLISTS/trial2-credentials.txt"
done < "$WORDLISTS/users.txt"

log "Montando trial3-credentials.txt..."
idx=0
: > "$WORDLISTS/trial3-credentials.txt"
while IFS= read -r user; do
  if [[ "$user" == "admin" ]]; then
    pass="123ab"
  else
    pass="${RANDOM_000[$idx]}"
    idx=$((idx + 1))
  fi
  printf '%s:%s\n' "$user" "$pass" >> "$WORDLISTS/trial3-credentials.txt"
done < "$WORDLISTS/users.txt"

cat > "$WORDLISTS/trial1-spray.txt" <<'SPRAY'
12ab
34cd
56ef
78gh
90ij
01kl
23mn
45op
67qr
89st
SPRAY

{
  echo "# trial1"
  cat "$WORDLISTS/trial1-credentials.txt"
  echo "# trial2"
  cat "$WORDLISTS/trial2-credentials.txt"
  echo "# trial3"
  cat "$WORDLISTS/trial3-credentials.txt"
} > "$LOGS/credentials.txt"

log "Arquivos gerados:"
for f in \
  users.txt \
  trial1-users.txt \
  trial1-credentials.txt \
  trial1-passwords.txt \
  trial1-spray.txt \
  trial2-users.txt \
  trial2-credentials.txt \
  trial2-passwords.txt \
  trial3-users.txt \
  trial3-credentials.txt \
  trial3-passwords.txt; do
  log "  $WORDLISTS/$f ($(wc -l < "$WORDLISTS/$f") linhas)"
done

log "Resumo:"
log "  seed trial1: 42"
log "  seed trial3: 43"
log "  senha fixa trial1 (backup): 12ab"
log "  senha fixa trial2 (admin): 12ab"
log "  senha fixa trial3 (admin): 123ab"
log "  linha de 12ab em trial1-passwords.txt: $(grep -n -m1 '^12ab$' "$WORDLISTS/trial1-passwords.txt" | cut -d: -f1)"
log "  linha de 123ab em trial3-passwords.txt: $(grep -n -m1 '^123ab$' "$WORDLISTS/trial3-passwords.txt" | cut -d: -f1)"
log "  credentials consolidado: $LOGS/credentials.txt"

log "== Wordlists geradas =="
