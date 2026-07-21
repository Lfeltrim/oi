# data-dev-env

Repositório **semente** de ambiente de desenvolvimento. Ele não guarda código
de trabalho — serve só para **provisionar o ambiente efêmero** (Claude Code on
the web **ou** GitHub Codespaces) já com todas as ferramentas instaladas. O
código de trabalho de verdade vive no **Azure DevOps** e é clonado à parte.

> Ideia: GitHub = bootstrap do ambiente · Azure DevOps = onde o código mora.

## O que é instalado

| Ferramenta | Comando | Como |
|---|---|---|
| Terraform | `terraform` | binário oficial em `~/.local/bin` |
| dbt (+ adapter Snowflake) | `dbt` | venv isolado (`dbt-snowflake`) |
| Astro CLI (Airflow) | `astro` | instalador oficial da Astronomer |
| Snowflake CLI | `snow` | venv isolado (`snowflake-cli`) |
| Cortex Code CLI (CoCo) | `cortex` | instalador oficial da Snowflake |
| Azure CLI | `az` | script oficial da Microsoft |
| Claude Code CLI | `claude` | `npm i -g @anthropic-ai/claude-code` |

E, no VS Code (Codespaces), as extensões: **Claude Code**
(`anthropic.claude-code`), **Snowflake** (`snowflake.snowflake-vsc`),
Terraform, Python e Azure CLI Tools.

> **Airflow / Astro:** o Astro CLI é instalado para desenvolvimento local. O
> deploy continua indo para o seu Airflow self-hosted no Azure — este repo não
> mexe nisso.

> **Requisito de rede (GitHub):** no **Claude Code on the web**, o proxy do
> GitHub só libera download de *release assets* de repositórios **anexados à
> sessão** — e não é possível anexar repos de outra conta (ex.: `dbt-labs`,
> `astronomer`). Efeito prático:
> - **dbt:** o `setup.sh` tenta a versão mais recente e, se o release do
>   dbt-labs estiver bloqueado, **cai automaticamente para dbt 1.7.x**, que
>   instala 100% do PyPI. Ou seja, dbt sempre fica disponível. Para forçar
>   outra versão: `DBT_SPEC='dbt-snowflake==1.9.*' bash ./setup.sh`.
> - **Astro CLI:** é binário de *release* do GitHub e **não** tem fallback no
>   PyPI, então **não instala** no Claude web com o GitHub bloqueado.
>
> No **GitHub Codespaces** nada disso se aplica: o GitHub é acessível por
> padrão e ambos (dbt mais recente e Astro) instalam normalmente. As demais
> ferramentas (Terraform, `snow`, `cortex`, `az`) não dependem de GitHub.

## Plugin do Cortex Code para o Claude Code

O plugin `snowflake-cortex-code@claude-plugins-official` já está declarado em
[`.claude/settings.json`](.claude/settings.json) (`enabledPlugins`), então o
Claude Code o habilita automaticamente. Ele exige o **Cortex Code CLI**
(`cortex`) no PATH — o `setup.sh` cuida disso — e uma conexão Snowflake em
`~/.snowflake/connections.toml`.

## Como usar

### No Claude Code on the web
Ao iniciar uma sessão a partir deste repo, o
[SessionStart hook](.claude/hooks/session-start.sh) roda o `setup.sh`
automaticamente (modo síncrono: a sessão começa só depois que tudo está
instalado). Nada a fazer manualmente.

### No GitHub Codespaces
Ao criar o Codespace, o [`.devcontainer/devcontainer.json`](.devcontainer/devcontainer.json)
roda o `setup.sh` no `postCreateCommand` e instala as extensões do VS Code.

### Manualmente
```bash
bash ./setup.sh
```
Idempotente: rodar de novo pula o que já existe. Use `FORCE=1 bash ./setup.sh`
para reinstalar.

## Clonar os repos de trabalho do Azure DevOps

1. Liste as URLs de clone HTTPS em [`repos.txt`](repos.txt) (uma por linha).
2. Crie um **PAT** no Azure DevOps (scope `Code → Read`; `Read & Write` se for
   dar push de volta) e exporte-o:
   ```bash
   export AZDO_PAT=xxxxxxxxxxxx
   ./scripts/clone-work-repos.sh
   ```
   Os repos vão para `~/work` (ou defina `WORK_DIR`). O PAT é passado por
   cabeçalho HTTP, então **não** fica salvo no remote de cada repo.

### Guardando o PAT com segurança
- **Codespaces:** Settings → Codespaces → **Secrets** → crie `AZDO_PAT`. Ele é
  injetado como variável de ambiente em todo Codespace.
- **Claude Code on the web:** configure `AZDO_PAT` como variável de ambiente do
  ambiente (nas configurações do ambiente).
- **Local:** copie `.env.example` para `.env` (que está no `.gitignore`) e faça
  `source .env`.

Nunca comite o token. Prefira PATs de **validade curta** e revogue quando não
precisar mais.

## Estrutura

```
.
├── setup.sh                     # instalador de todas as ferramentas (idempotente)
├── repos.txt                    # lista de repos do Azure DevOps a clonar
├── scripts/
│   └── clone-work-repos.sh      # clona/atualiza os repos usando AZDO_PAT
├── .devcontainer/
│   └── devcontainer.json        # Codespaces: base + features + extensões + setup
├── .claude/
│   ├── settings.json            # SessionStart hook + plugin do Cortex Code
│   └── hooks/
│       └── session-start.sh     # roda setup.sh no início da sessão (Claude web)
├── .env.example                 # modelo de variáveis (AZDO_PAT, WORK_DIR)
└── .gitignore
```

## Personalizando
- **Versão do Terraform:** `TERRAFORM_VERSION=1.x.y bash ./setup.sh`.
- **Mais ferramentas:** adicione uma função `install_*` no `setup.sh` e registre
  com `step "Nome" <comando-check> install_sua_ferramenta`.
- **Mais extensões do VS Code:** edite a lista em `devcontainer.json`.
