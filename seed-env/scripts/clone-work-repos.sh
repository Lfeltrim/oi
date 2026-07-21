#!/usr/bin/env bash
# =============================================================================
# clone-work-repos.sh — clona (ou atualiza) os repositórios de trabalho
# hospedados no Azure DevOps, listados em repos.txt.
#
# Autenticação: usa o Personal Access Token do Azure DevOps na variável
# AZDO_PAT. O token é passado via cabeçalho HTTP (Authorization: Basic),
# então NÃO fica gravado no remote de cada repo.
#
# Uso:
#   AZDO_PAT=xxxxx ./scripts/clone-work-repos.sh
#   AZDO_PAT=xxxxx WORK_DIR=/workspaces ./scripts/clone-work-repos.sh repos.txt
#
# Onde criar o PAT: Azure DevOps → avatar → Personal access tokens →
#   scope "Code → Read" (ou "Read & Write" se for dar push de volta).
# =============================================================================
set -uo pipefail

: "${AZDO_PAT:?Defina AZDO_PAT com um Personal Access Token do Azure DevOps (scope Code: Read)}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOS_FILE="${1:-${SCRIPT_DIR}/../repos.txt}"
WORK_DIR="${WORK_DIR:-${HOME}/work}"

if [ ! -f "$REPOS_FILE" ]; then
  echo "✘ Arquivo de repos não encontrado: $REPOS_FILE" >&2
  exit 1
fi

mkdir -p "$WORK_DIR"

# PAT vira "Authorization: Basic base64(:PAT)" — forma recomendada pelo Azure DevOps.
AUTH="$(printf ':%s' "$AZDO_PAT" | base64 | tr -d '\n')"
GIT_AUTH=(-c "http.extraHeader=Authorization: Basic ${AUTH}")

fails=0
while IFS= read -r raw || [ -n "$raw" ]; do
  # remove comentários (#...) e espaços das pontas
  line="${raw%%#*}"
  line="$(printf '%s' "$line" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
  [ -z "$line" ] && continue

  name="$(basename "$line")"; name="${name%.git}"
  dest="${WORK_DIR}/${name}"

  if [ -d "${dest}/.git" ]; then
    echo "↻ atualizando ${name}"
    git "${GIT_AUTH[@]}" -C "$dest" pull --ff-only || { echo "  ✘ falhou o pull de ${name}"; fails=$((fails+1)); }
  else
    echo "⤓ clonando ${name}"
    git "${GIT_AUTH[@]}" clone "$line" "$dest" || { echo "  ✘ falhou o clone de ${name}"; fails=$((fails+1)); }
  fi
done < "$REPOS_FILE"

echo
if [ "$fails" -eq 0 ]; then
  echo "✔ Todos os repositórios prontos em ${WORK_DIR}"
else
  echo "⚠ Concluído com ${fails} falha(s). Verifique as URLs e o scope do PAT."
  exit 1
fi
