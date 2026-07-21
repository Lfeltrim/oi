#!/usr/bin/env bash
# SessionStart hook — roda no início de cada sessão do Claude Code on the web.
# Instala o ambiente (setup.sh) de forma síncrona, garantindo que as
# ferramentas estejam prontas antes do agente começar a trabalhar.
set -euo pipefail

# Só roda no ambiente remoto (Claude Code on the web), não em uso local.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

cd "${CLAUDE_PROJECT_DIR:-$(pwd)}"
bash ./setup.sh
