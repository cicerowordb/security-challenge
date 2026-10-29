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
  printf '%s\n' "$*" | tee -a "$LOG_FILE" >&2
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
Uso: 01-password-generator.sh --pattern <padrao> [--all | --random] [opcoes]

Padroes:
  d = digito 0-9
  l = minuscula a-z
  L = maiuscula A-Z
  # = simbolo !@#$%&*_-

Opcoes:
  --pattern <padrao>  Padrao de senha (obrigatorio)
  --all               Gera todas as combinacoes
  --random            Gera uma senha aleatoria
  --count <N>         Gera N senhas aleatorias unicas (implica --random)
  --seed <N>          Semente para reprodutibilidade
  --shuffle           Embaralha os caracteres (somente com --random)
  --force             Permite --all com mais de 10 milhoes de combinacoes
  -h, --help          Mostra esta ajuda
EOF
}

PATTERN=""
MODE=""
COUNT=1
COUNT_GIVEN=0
SEED=""
SHUFFLE=0
FORCE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pattern)
      PATTERN="${2:-}"
      shift 2
      ;;
    --all)
      MODE="all"
      shift
      ;;
    --random)
      MODE="random"
      shift
      ;;
    --count)
      COUNT="${2:-}"
      COUNT_GIVEN=1
      MODE="random"
      shift 2
      ;;
    --seed)
      SEED="${2:-}"
      shift 2
      ;;
    --shuffle)
      SHUFFLE=1
      shift
      ;;
    --force)
      FORCE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Opcao desconhecida: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$PATTERN" ]]; then
  echo "ERRO: --pattern e obrigatorio" >&2
  usage
  exit 1
fi

if [[ ! "$PATTERN" =~ ^[dlL#]+$ ]]; then
  echo "ERRO: padrao invalido '$PATTERN'; use apenas d, l, L e #" >&2
  exit 1
fi

if [[ -z "$MODE" ]]; then
  echo "ERRO: informe --all ou --random" >&2
  usage
  exit 1
fi

if (( SHUFFLE )) && [[ "$MODE" != "random" ]]; then
  echo "ERRO: --shuffle so pode ser usado com --random" >&2
  exit 1
fi

if [[ -n "$SEED" ]] && [[ "$MODE" != "random" ]]; then
  echo "ERRO: --seed so pode ser usado com --random" >&2
  exit 1
fi

if [[ -n "$SEED" ]] && [[ ! "$SEED" =~ ^[0-9]+$ ]]; then
  echo "ERRO: --seed deve ser um numero inteiro nao negativo" >&2
  exit 1
fi

if [[ ! "$COUNT" =~ ^[1-9][0-9]*$ ]]; then
  echo "ERRO: --count deve ser um inteiro positivo" >&2
  exit 1
fi

declare -A CLASS_CHARS=(
  [d]="0123456789"
  [l]="abcdefghijklmnopqrstuvwxyz"
  [L]="ABCDEFGHIJKLMNOPQRSTUVWXYZ"
  ['#']='!@#$%&*_-'
)

declare -A OCC=(
  [d]=0
  [l]=0
  [L]=0
  ['#']=0
)

for ((i = 0; i < ${#PATTERN}; i++)); do
  token="${PATTERN:$i:1}"
  OCC[$token]=$((OCC[$token] + 1))
done

perm() {
  local n=$1
  local k=$2
  local result=1
  local i
  for ((i = 0; i < k; i++)); do
    result=$((result * (n - i)))
  done
  printf '%s' "$result"
}

TOTAL=1
for token in d l L '#'; do
  k=${OCC[$token]}
  if ((k > 0)); then
    n=${#CLASS_CHARS[$token]}
    if ((k > n)); then
      echo "ERRO: o padrao pede $k caracteres da classe '$token', mas a classe tem $n" >&2
      exit 1
    fi
    p=$(perm "$n" "$k")
    TOTAL=$((TOTAL * p))
  fi
done

if [[ "$MODE" == "all" ]] && ((TOTAL > 10000000)) && ((FORCE == 0)); then
  echo "ERRO: --all geraria $TOTAL senhas; use --force para permitir" >&2
  exit 1
fi

if [[ "$MODE" == "random" ]] && ((COUNT > TOTAL)); then
  echo "ERRO: --count $COUNT maior que o total de $TOTAL combinacoes" >&2
  exit 1
fi

if [[ -n "$SEED" ]]; then
  PRNG_STATE=$((SEED % 2147483647))
else
  PRNG_STATE=$(( $(date +%s%N) % 2147483647 ))
fi
if ((PRNG_STATE == 0)); then
  PRNG_STATE=1
fi

prng_next() {
  PRNG_STATE=$(((PRNG_STATE * 1103515245 + 12345) & 0x7fffffff))
  PRNG_VALUE=$PRNG_STATE
}

prng_range() {
  local n=$1
  prng_next
  PRNG_RANGE=$((PRNG_VALUE % n))
}

log "Padrao: $PATTERN"
log "Total de combinacoes: $TOTAL"

shuffle_string() {
  local s=$1
  local i j tmp
  local -a chars=()
  local out=""
  for ((i = 0; i < ${#s}; i++)); do
    chars[$i]="${s:$i:1}"
  done
  for ((i = ${#chars[@]} - 1; i > 0; i--)); do
    prng_range $((i + 1))
    j=$PRNG_RANGE
    tmp="${chars[$i]}"
    chars[$i]="${chars[$j]}"
    chars[$j]="$tmp"
  done
  for ((i = 0; i < ${#chars[@]}; i++)); do
    out+="${chars[$i]}"
  done
  SHUFFLED_STRING="$out"
}

generate_random() {
  local out=""
  local token chars c
  local -A used=(
    [d]=""
    [l]=""
    [L]=""
    ['#']=""
  )
  local i
  for ((i = 0; i < ${#PATTERN}; i++)); do
    token="${PATTERN:$i:1}"
    chars="${CLASS_CHARS[$token]}"
    while true; do
      prng_range ${#chars}
      c="${chars:$PRNG_RANGE:1}"
      if [[ "${used[$token]}" != *"$c"* ]]; then
        used[$token]+="$c"
        out+="$c"
        break
      fi
    done
  done
  if ((SHUFFLE)); then
    shuffle_string "$out"
    out="$SHUFFLED_STRING"
  fi
  RANDOM_PASSWORD="$out"
}

if [[ "$MODE" == "all" ]]; then
  CURRENT=""
  declare -A USED=(
    [d]=""
    [l]=""
    [L]=""
    ['#']=""
  )

  generate_all() {
    local idx=$1
    if ((idx == ${#PATTERN})); then
      printf '%s\n' "$CURRENT"
      return
    fi

    local token="${PATTERN:$idx:1}"
    local chars="${CLASS_CHARS[$token]}"
    local i c
    for ((i = 0; i < ${#chars}; i++)); do
      c="${chars:$i:1}"
      if [[ "${USED[$token]}" == *"$c"* ]]; then
        continue
      fi
      USED[$token]+="$c"
      CURRENT+="$c"
      generate_all $((idx + 1))
      CURRENT="${CURRENT%?}"
      USED[$token]="${USED[$token]%?}"
    done
  }

  log "Gerando todas as combinacoes..."
  generate_all 0
else
  if ((COUNT_GIVEN == 0)); then
    COUNT=1
  fi

  log "Gerando $COUNT senha(s) aleatoria(s)..."
  declare -A SEEN=()
  emitted=0
  while ((emitted < COUNT)); do
    generate_random
    password="$RANDOM_PASSWORD"
    if [[ -z "${SEEN[$password]:-}" ]]; then
      SEEN[$password]=1
      printf '%s\n' "$password"
      emitted=$((emitted + 1))
    fi
  done
fi
