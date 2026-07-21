#!/usr/bin/env bash
# =============================================================================
# setup.sh — Instalador do ambiente de desenvolvimento de dados
#
# Instala as ferramentas usadas no dia a dia (Terraform, dbt, Astro CLI,
# Snowflake CLI, Cortex Code CLI, Azure CLI, Claude Code CLI) de forma
# idempotente. Serve tanto para o Claude Code on the web (via SessionStart
# hook) quanto para o GitHub Codespaces (via postCreateCommand).
#
# Uso:
#   bash setup.sh            # instala tudo (pula o que já existe)
#   FORCE=1 bash setup.sh    # reinstala mesmo que já exista
#
# Variáveis opcionais:
#   TERRAFORM_VERSION  versão do Terraform (default abaixo)
# =============================================================================
set -uo pipefail

# -----------------------------------------------------------------------------
# Config
# -----------------------------------------------------------------------------
TERRAFORM_VERSION="${TERRAFORM_VERSION:-1.13.1}"
LOCAL_BIN="${HOME}/.local/bin"
mkdir -p "$LOCAL_BIN"
export PATH="$LOCAL_BIN:$PATH"

if [ "$(id -u)" -eq 0 ]; then SUDO=""; else SUDO="sudo"; fi

# Resultado de cada etapa, para o resumo final
declare -a OK=() FAIL=() SKIP=()

log()  { printf '\033[1;34m▸ %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m  ✔ %s\033[0m\n' "$*"; OK+=("$1"); }
skip() { printf '\033[1;33m  ⏭ %s (já instalado)\033[0m\n' "$*"; SKIP+=("$1"); }
fail() { printf '\033[1;31m  ✘ %s\033[0m\n' "$*"; FAIL+=("$1"); }
have() { command -v "$1" >/dev/null 2>&1; }

# Roda um passo de instalação isolando falhas (um erro não derruba o script)
step() { # step <nome> <cmd-check> <função-de-install>
  local name="$1" check="$2" fn="$3"
  log "$name"
  if [ "${FORCE:-0}" != "1" ] && have "$check"; then skip "$name"; return; fi
  if "$fn"; then ok "$name"; else fail "$name"; fi
}

# -----------------------------------------------------------------------------
# Pré-requisitos de sistema
# -----------------------------------------------------------------------------
install_prereqs() {
  export DEBIAN_FRONTEND=noninteractive
  $SUDO apt-get update -qq || return 1
  $SUDO apt-get install -y -qq \
    curl unzip git ca-certificates gnupg lsb-release \
    python3 python3-pip python3-venv >/dev/null || return 1
}

# Instala uma app Python num venv isolado e expõe o executável em ~/.local/bin.
# Mais robusto que o pipx (não depende de uv nem de PATH global).
#   venv_app <nome-do-venv> <executável> <specs-do-pip...>
venv_app() {
  local name="$1" bin="$2"; shift 2
  local venv="${HOME}/.venvs/${name}"
  python3 -m venv "$venv" || return 1
  "$venv/bin/pip" install -q --upgrade pip >/dev/null 2>&1 || return 1
  "$venv/bin/pip" install -q "$@" || return 1
  ln -sf "$venv/bin/$bin" "$LOCAL_BIN/$bin"
  have "$bin"
}

# -----------------------------------------------------------------------------
# Terraform (binário oficial → ~/.local/bin, sem root)
# -----------------------------------------------------------------------------
install_terraform() {
  local arch; arch="$(dpkg --print-architecture 2>/dev/null || echo amd64)"
  case "$arch" in arm64) arch=arm64 ;; *) arch=amd64 ;; esac
  local url="https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_${arch}.zip"
  curl -fsSL -o /tmp/terraform.zip "$url" || return 1
  unzip -o -q /tmp/terraform.zip -d "$LOCAL_BIN" || return 1
  rm -f /tmp/terraform.zip
}

# -----------------------------------------------------------------------------
# dbt em venv isolado. Instalar o adapter (dbt-snowflake) já traz o dbt-core e
# o executável `dbt`. Requer github.com acessível (o parser do dbt é baixado de
# um release do GitHub durante o build).
# Ajuste DBT_SPEC para fixar versão, ex.: DBT_SPEC='dbt-snowflake==1.9.*'
# -----------------------------------------------------------------------------
install_dbt() {
  # Tenta a versão desejada (default: adapter mais recente). Onde o github.com
  # é acessível (Codespaces, ou rede liberada), instala a última.
  if venv_app dbt dbt "${DBT_SPEC:-dbt-snowflake}"; then return 0; fi
  # Fallback: dbt 1.7.x instala 100% do PyPI (não depende de release do GitHub),
  # então funciona mesmo no Claude web onde os assets do dbt-labs ficam bloqueados.
  echo "  (dbt: instalação padrão falhou — provável bloqueio de release do GitHub;" >&2
  echo "   caindo para ${DBT_FALLBACK_SPEC:-dbt-snowflake==1.7.*}, que instala via PyPI)" >&2
  rm -rf "${HOME}/.venvs/dbt"
  venv_app dbt dbt "${DBT_FALLBACK_SPEC:-dbt-snowflake==1.7.*}"
}

# -----------------------------------------------------------------------------
# Astro CLI (Airflow local; deploy fica no seu Airflow self-hosted no Azure).
# Instala em ~/.local/bin (sem sudo). Requer github.com acessível para baixar o
# binário do release.
# -----------------------------------------------------------------------------
install_astro() {
  curl -sSL https://install.astronomer.io | bash -s -- -b "$LOCAL_BIN" >/dev/null 2>&1
  have astro   # o instalador sai 0 mesmo se o download falhar; checa o binário
}

# -----------------------------------------------------------------------------
# Snowflake CLI (snow) em venv isolado
# -----------------------------------------------------------------------------
install_snow() {
  venv_app snowflake-cli snow snowflake-cli
}

# -----------------------------------------------------------------------------
# Cortex Code CLI (cortex / CoCo) — instalador oficial da Snowflake
# -----------------------------------------------------------------------------
install_cortex() {
  curl -LsS https://ai.snowflake.com/static/cc-scripts/install.sh | sh >/dev/null 2>&1
  have cortex
}

# -----------------------------------------------------------------------------
# Azure CLI (az) — script oficial da Microsoft (Debian/Ubuntu)
# -----------------------------------------------------------------------------
install_az() {
  curl -sL https://aka.ms/InstallAzureCLIDeb | $SUDO bash >/dev/null 2>&1 || return 1
}

# -----------------------------------------------------------------------------
# Claude Code CLI — necessário para o plugin do Cortex Code.
# No Claude Code on the web o `claude` já existe (é o runtime), então é pulado.
# No Codespaces instalamos via npm.
# -----------------------------------------------------------------------------
install_claude() {
  if have npm; then
    npm install -g @anthropic-ai/claude-code >/dev/null 2>&1 || return 1
  else
    curl -fsSL https://claude.ai/install.sh | bash >/dev/null 2>&1 || return 1
  fi
}

# -----------------------------------------------------------------------------
# Plugin do Cortex Code para o Claude Code.
# Mecanismo primário: declarado em .claude/settings.json (enabledPlugins).
# Aqui tentamos também o install via CLI (best-effort, não-fatal).
# -----------------------------------------------------------------------------
install_cortex_plugin() {
  have claude || return 0   # sem CLI do claude não há o que fazer aqui
  claude plugin install snowflake-cortex-code@claude-plugins-official >/dev/null 2>&1 || true
  return 0
}

# -----------------------------------------------------------------------------
# PATH: persiste ~/.local/bin para a sessão
# -----------------------------------------------------------------------------
persist_path() {
  local line='export PATH="$HOME/.local/bin:$PATH"'
  # Claude Code on the web: usa $CLAUDE_ENV_FILE
  if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
    grep -qF "$line" "$CLAUDE_ENV_FILE" 2>/dev/null || echo "$line" >> "$CLAUDE_ENV_FILE"
  fi
  # Codespaces / shells locais
  grep -qF "$line" "${HOME}/.bashrc" 2>/dev/null || echo "$line" >> "${HOME}/.bashrc"
}

# -----------------------------------------------------------------------------
# Execução
# -----------------------------------------------------------------------------
main() {
  log "Instalando pré-requisitos de sistema…"
  if install_prereqs; then ok "pré-requisitos"; else fail "pré-requisitos"; fi

  step "Terraform"               terraform  install_terraform
  step "dbt (core + snowflake)"  dbt        install_dbt
  step "Astro CLI"               astro      install_astro
  step "Snowflake CLI (snow)"    snow       install_snow
  step "Cortex Code CLI"         cortex     install_cortex
  step "Azure CLI (az)"          az         install_az
  step "Claude Code CLI"         claude     install_claude

  log "Plugin Cortex Code p/ Claude Code"
  install_cortex_plugin && ok "plugin cortex (declarado em .claude/settings.json)"

  persist_path

  echo
  log "Resumo"
  [ ${#OK[@]}   -gt 0 ] && printf '  \033[1;32minstalado:\033[0m %s\n' "${OK[*]}"
  [ ${#SKIP[@]} -gt 0 ] && printf '  \033[1;33mjá existia:\033[0m %s\n' "${SKIP[*]}"
  [ ${#FAIL[@]} -gt 0 ] && printf '  \033[1;31mfalhou:\033[0m %s\n' "${FAIL[*]}"
  echo
  echo "Ferramentas instaladas em ~/.local/bin e no PATH. Abra um novo shell ou rode:"
  echo '  export PATH="$HOME/.local/bin:$PATH"'
  # Não falha a sessão mesmo se algo não instalou — o resumo acima mostra o quê.
  return 0
}

main "$@"
