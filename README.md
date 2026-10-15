# Power Platform ALM Toolkit Skill

**Turn any AI assistant into an enterprise Power Platform architect — and a live Dataverse operator.** This repo ships three Agent Skills: one teaches Claude, Codex, GitHub Copilot, Cursor, Gemini and other AI tools to generate production-ready ALM automation (source-controlled scripts, GitHub Actions pipelines, plain-language runbooks); the other two run live Dataverse queries, bulk data operations, and governance checks right now, through the Dataverse MCP server when it's connected — or generate the equivalent query/runbook when it isn't, so neither one requires MCP set up first.

[![CI](https://github.com/NaveenGaneshe/power-platform-alm-toolkit-skill/actions/workflows/ci.yml/badge.svg)](https://github.com/NaveenGaneshe/power-platform-alm-toolkit-skill/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Agent Skills](https://img.shields.io/badge/format-Agent%20Skills%20(SKILL.md)-6f42c1)](https://agentskills.io/specification)
![Status](https://img.shields.io/badge/status-preview%20v0.1.0-orange)

```text
You:   "Before every release weekend our admins switch off ~40 flows in the Invoicing
        solution in production, then back on Monday. Build a module that does this properly."

Skill: 1. Capability mapping   → Automation & Workflow Governance, blast radius, identity, least-privilege role
       2. Architecture & code  → PowerShell 7 scripts, Web API queries, snapshot of which flows were on
       3. Repo & pipelines     → file layout, GitHub Actions with test run by default + production approval
       4. Runbooks             → "Fill in these 3 boxes, tick Test run, press Run" for admins; setup for devs
```

---

## Contents

- [Skills in this repo](#skills-in-this-repo)
- [Why this exists](#why-this-exists)
- [Features](#features)
- [Supported AI tools](#supported-ai-tools)
- [Installation](#installation)
- [Usage](#usage)
- [What you get](#what-you-get)
- [Prerequisites for the generated automation](#prerequisites-for-the-generated-automation)
- [Repository layout](#repository-layout)
- [Development](#development)
- [Roadmap](#roadmap)
- [Contributing, security and license](#contributing-security-and-license)

---

## Skills in this repo

| Skill | Status | What it does | Trigger |
|---|---|---|---|
| [`power-platform-alm-toolkit`](skills/power-platform-alm-toolkit) | ✅ Shipped | **Generates** ALM code for you: scripts, pipelines, and runbooks, ready to commit and run later. | Any Power Platform ALM request — pipelines, bulk-update scripts, role sync, flow governance. |
| [`pp-data-ops-agent`](skills/pp-data-ops-agent) | ✅ Shipped | Ask-and-answer queries and bulk record updates/deactivations/deletes, with a preview and an explicit confirmation gate before anything writes. **Runs live** through the Dataverse MCP server if you have it connected — if you don't, it generates the equivalent query or script for you to run yourself instead of refusing. | "How many contacts have no email?", "deactivate cases open over 90 days," "show me accounts created last month." |
| [`pp-governance-agent`](skills/pp-governance-agent) | ✅ Shipped | Security-role drift between environments, connection-reference health, and post-import flow health, with fixes proposed and applied only on confirmation — a lightweight alternative to the piece of the retired Power Platform CoE Starter Kit that gave visibility but couldn't fix anything itself. **Runs live** through the Dataverse MCP server if connected; otherwise generates the same checks as a runbook you run yourself. | "Audit my security roles," "why won't my flows turn on," "health check my environment." |

### About the Dataverse MCP server (optional, not a prerequisite)

`pp-data-ops-agent` and `pp-governance-agent` both act on a real Dataverse environment through the **Microsoft Dataverse MCP server** when it's available — but **neither one requires it to be set up first**. If you haven't connected it, the skill still completes your request: it generates the equivalent read-only query (or, for a bulk change, a preview query plus the Web API calls to apply it) for you to run yourself, and mentions once that connecting MCP would let it run live next time. To set it up in Claude Code and get live answers instead of generated ones:

```bash
claude mcp add dataverse-dev -t stdio -- npx -y @microsoft/dataverse mcp https://yourorg-dev.crm.dynamics.com
```

Repeat with a different name per environment (`dataverse-test`, `dataverse-prod`, ...). See [Microsoft's connection guide](https://learn.microsoft.com/power-apps/maker/data-platform/data-platform-mcp) for GitHub Copilot, Copilot Studio, and other clients. Note: Dataverse MCP tool calls from non-Copilot-Studio clients (including Claude Code) are billed per Microsoft's published rates unless you have a qualifying Dynamics 365 Premium or Microsoft 365 Copilot license — the no-MCP fallback has no such cost since nothing is called live.

## Why this exists

Power Platform teams live between two worlds:

- **Developers** want everything in Git: solutions unpacked, versions stamped, environments promoted by pipelines, and no hand-clicking in production.
- **Citizen developers and admins** need to do real operational work every day: bulk-update records, sync users and security roles, switch flows off for a release, produce a data dictionary, or just answer "how many of X do we have." They need to do it without writing code, and without the risk of breaking production.

Generic AI answers fall short of both groups. They invent PAC CLI flags, hardcode environment URLs, skip the "what if this goes wrong?" part, and never write the instructions an admin actually needs — and when the task is "just tell me the answer right now," they can't act on a live environment at all.

This repo fixes that two ways: `power-platform-alm-toolkit` gives the AI one consistent, opinionated playbook, the **four-part operational blueprint**, plus verified reference material and tested code to build code *generation* on. `pp-data-ops-agent` gives it a safe way to *act* live, through the Dataverse MCP server, with the same safety instincts (preview first, confirm before writing, never guess at a schema) carried over into execution instead of just generation.

### Benefits

| For | Benefit |
|---|---|
| **Developers** | Complete, copy-pasteable files instead of fragments. Environment-agnostic code: the same commit deploys to dev, test and prod. CI/CD that unpacks, versions, checks, packs and deploys out of the box. |
| **Citizen developers & admins** | Every generated operation gets a simple GitHub form (text boxes, toggles, dropdowns) and a jargon-free runbook, test-run on by default. For one-off questions and quick fixes, `pp-data-ops-agent` skips the form entirely — just ask and get a live answer or a confirm-before-write change. |
| **Platform / CoE leads** | One consistent safety pattern across every module and every live operation: least-privilege identities, production approval gates (generated code) or explicit per-action confirmation (live agent), before-change snapshots, and an undo path. Easy to review and audit either way. |
| **Everyone** | Works in the AI tool your team already uses. Two skill folders, every tool. |

---

## Features

### The four-part operational blueprint

Every module request is answered in the same structure:

| Part | What you get |
|---|---|
| **1. Core Operational Capability Mapping** | The operation classified into one of four categories, plus its execution layer, run-as identity, trigger surface and **blast radius** (what changes, the worst case, how to undo). |
| **2. Extended Solution Architecture & Schemas** | Raw config and schema files (Custom API definitions, deployment settings, custom connector OpenAPI, PCF manifests, module manifests) and complete PowerShell 7 / OData / FetchXML backends. |
| **3. Repository Directory Structure & ALM Pipelines** | Exactly where each file lives in the repo, and production-ready GitHub Actions: export → unpack → validate → version → pack → inject environment settings → deploy test → approve → deploy production. |
| **4. End-User & Developer Runbooks** | A README section for operators (what each field means, which button to press, how to read results, how to undo) and for developers (setup, local runs, tests, extension). |

### Operational categories covered

| Category | Example operations |
|---|---|
| **Data & Schema Management** | Deep queries, bulk record updates, metadata exploration, data dictionary generation, schema migrations |
| **Access & Profile Administration** | User profile sync, security role assignment, setting overrides, security audits |
| **Automation & Workflow Governance** | Turning flows and plug-in steps on/off in bulk, state triggers, event log tracking, telemetry |
| **Environment Operations** | Solution packaging, migration prep, dependency maps, multi-environment sync |

### Safe by default

- **Test run first.** Every operation that changes data previews what would change and changes nothing, until an operator unticks *Test run* and types `APPLY`.
- **Snapshots and undo.** Records are saved before they're changed, and kept as a downloadable run artifact.
- **Throttling-aware.** Batching with `UpdateMultiple`, automatic retry on Dataverse service-protection limits (HTTP 429 with `Retry-After`).
- **No secrets in code.** Settings come from GitHub environment variables and secrets, with optional secretless sign-in through GitHub OIDC federation.
- **Production gates.** Deployments and operations against production wait for approval from required reviewers.
- **Script-injection safe.** Form inputs are passed to scripts through environment variables, never spliced into code.

### Built on verified tooling, not guesses

- PAC CLI commands and `microsoft/powerplatform-actions` inputs checked against Microsoft's current documentation (October 2026), including the newer YAML source-control format used by Dataverse Git integration.
- A shared, unit-tested PowerShell 7 module ([`assets/Dataverse.psm1`](skills/power-platform-alm-toolkit/assets/Dataverse.psm1)) for authentication, paging, batching, retry, snapshots and run summaries. It runs on Windows, macOS and Linux.
- A deployment-settings injector that **refuses to deploy** if any environment variable or connection reference is missing a value.

---

## Supported AI tools

The skill uses the open [Agent Skills](https://agentskills.io/specification) format (`SKILL.md`), so most modern AI coding tools load it natively. Chat-only assistants use the portable single-file bundle.

| Tool | How it loads the skill | Quick install |
|---|---|---|
| **Claude Code** | Native skill (`~/.claude/skills` or `.claude/skills`) | `./scripts/install.sh --tool claude` |
| **Claude apps** (claude.ai, desktop, mobile) | Uploaded skill (Pro, Max, Team, Enterprise) | Upload `power-platform-alm-toolkit.zip` |
| **OpenAI Codex** (CLI, IDE, desktop app) | Native skill (`~/.agents/skills` or `.agents/skills`) | `./scripts/install.sh --tool codex` |
| **GitHub Copilot** (VS Code / JetBrains agent mode, CLI, cloud agent) | Native skill (`~/.copilot/skills`, `.github/skills` or `.agents/skills`) | `./scripts/install.sh --tool copilot` |
| **Cursor** | Native skill (`~/.cursor/skills`, `.cursor/skills` or `.agents/skills`) | `./scripts/install.sh --tool cursor` |
| **Gemini CLI** | Native skill (`~/.gemini/skills` or `.agents/skills`) | `./scripts/install.sh --tool gemini` |
| **Windsurf, Cline, OpenCode, Goose, Kiro, Zed, and many more** | Native skill via the [`skills` CLI](https://github.com/vercel-labs/skills) | `npx skills add NaveenGaneshe/power-platform-alm-toolkit-skill` |
| **ChatGPT** (custom GPT), **Gemini** (Gems), **Microsoft Copilot Studio**, **Claude Projects** | Instructions + knowledge file | See [chat assistants guide](docs/chat-assistants.md) |
| **Any other model or API** | Paste or attach the portable bundle | Use `power-platform-alm-toolkit.md` as a system prompt / context file |

> **Tip:** `--tool all` installs into `~/.claude/skills` *and* the shared `~/.agents/skills` folder. Between them, those cover Claude Code, Codex, Copilot, Cursor and Gemini CLI without duplicate copies.

---

## Installation

### Option 1: One command with the `skills` CLI (any agent)

Requires Node.js 18+.

```bash
npx skills add NaveenGaneshe/power-platform-alm-toolkit-skill            # pick agents interactively
npx skills add NaveenGaneshe/power-platform-alm-toolkit-skill -g -a claude-code -a codex -a cursor
```

### Option 2: Installer scripts (from a clone or straight from GitHub)

**macOS / Linux / WSL / Git Bash**

```bash
git clone https://github.com/NaveenGaneshe/power-platform-alm-toolkit-skill.git
cd power-platform-alm-toolkit-skill
./scripts/install.sh                     # interactive menu
./scripts/install.sh --tool all          # Claude Code + Codex/Copilot/Cursor/Gemini, for your user
./scripts/install.sh --tool agents --scope project   # commit the skill into the current repo for your whole team

# Without cloning:
curl -fsSL https://raw.githubusercontent.com/NaveenGaneshe/power-platform-alm-toolkit-skill/main/scripts/install.sh | bash -s -- --tool all
```

**Windows (PowerShell 5.1 or 7)**

```powershell
git clone https://github.com/NaveenGaneshe/power-platform-alm-toolkit-skill.git
cd power-platform-alm-toolkit-skill
.\scripts\install.ps1                    # interactive menu
.\scripts\install.ps1 -Tool claude,codex
.\scripts\install.ps1 -Tool agents -Scope project

# Without cloning:
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/NaveenGaneshe/power-platform-alm-toolkit-skill/main/scripts/install.ps1))) -Tool all
```

Update by running the installer again. Uninstall with `--uninstall` (Bash) or `-Uninstall` (PowerShell).

| `--tool` value | User scope (`--scope user`, default) | Project scope (`--scope project`) |
|---|---|---|
| `claude` | `~/.claude/skills/` | `.claude/skills/` |
| `agents` / `codex` | `~/.agents/skills/` | `.agents/skills/` |
| `copilot` | `~/.copilot/skills/` | `.github/skills/` |
| `cursor` | `~/.cursor/skills/` | `.cursor/skills/` |
| `gemini` | `~/.gemini/skills/` | `.gemini/skills/` |

### Option 3: Manual copy

Copy any of [`skills/power-platform-alm-toolkit`](skills/power-platform-alm-toolkit), [`skills/pp-data-ops-agent`](skills/pp-data-ops-agent), or [`skills/pp-governance-agent`](skills/pp-governance-agent) into any directory from the table above. Each folder name must stay exactly as it is in this repo.

### Option 4: Claude apps (claude.ai, desktop, mobile)

1. Download the zip for whichever skill(s) you want — `power-platform-alm-toolkit.zip`, `pp-data-ops-agent.zip`, `pp-governance-agent.zip` — from the [latest release](https://github.com/NaveenGaneshe/power-platform-alm-toolkit-skill/releases/latest). Each skill is its own zip.
2. In Claude, open **Settings → Capabilities**, make sure **Code execution and file creation** is on, then under **Skills** choose **Upload skill** and select each zip.
3. Toggle the skill(s) on. On Team and Enterprise plans, owners can provision them for the whole organization.

### Option 5: ChatGPT, Gemini, Copilot Studio and other chat assistants

For each skill you want, download its `<skill-name>.md` (the whole skill in one file) and `<skill-name>.instructions.md` from the [latest release](https://github.com/NaveenGaneshe/power-platform-alm-toolkit-skill/releases/latest), then follow the [chat assistants guide](docs/chat-assistants.md). `pp-data-ops-agent` and `pp-governance-agent` work without any MCP connection (they'll generate a query/runbook instead of running live), but get the most value where the tool also supports connecting the Dataverse MCP server — most portable chat assistants don't, so Claude Code, Claude Desktop, or GitHub Copilot get the live experience.

### Check it's working

Start a new session and ask:

> *What's the four-part blueprint you use for Power Platform toolkit modules?*

You should get the four section names back — this confirms `power-platform-alm-toolkit`. For `pp-data-ops-agent`, ask something like *"how many contacts have no email address?"* — without the Dataverse MCP server connected, it should hand you a ready-to-run query rather than refuse; with it connected (see its [compatibility note](skills/pp-data-ops-agent/SKILL.md)), it runs that query live and answers directly. `pp-governance-agent` works the same way for something like *"audit my security roles."* In Codex you can also type `$power-platform-alm-toolkit`, and in Claude Code `/power-platform-alm-toolkit`, to call any of the three skills explicitly by name.

---

## Usage

Just describe the operation. The skill triggers automatically on Power Platform, Dataverse, Power Automate, PAC CLI, solution ALM and related requests. You don't need to mention the skill or the blueprint.

### Example prompts

| Category | Try asking |
|---|---|
| Data & Schema | "Build a module that generates a data dictionary (Markdown + CSV) for every custom table in our *Sales* solution, runnable by BAs from GitHub." |
| Data & Schema | "We need to deactivate ~200k stale contacts not modified since 2022. Make it safe to run from a form, with an undo." |
| Access & Profile | "Sync security roles from an Excel-exported CSV of users and roles across dev, test and prod, and report differences before changing anything." |
| Access & Profile | "Audit who has System Administrator in each environment and post the report as a pipeline summary every Monday." |
| Automation Governance | "Before release weekends, switch off every flow in the *Invoicing* solution in prod and turn back on only the ones that were on." |
| Environment Ops | "Just the pipeline: export *HRCore* from dev into Git, promote to UAT then prod with different SharePoint URLs, prod needs manager approval." |
| Environment Ops | "Map every dependency that blocks uninstalling the *LegacyCRM* solution and turn it into a migration checklist." |

More in [`examples/prompts.md`](examples/prompts.md).

### Getting the most out of it

- **Say how big and how risky.** "10 records in dev" and "2 million records in production" produce very different designs.
- **Name your environments** if they aren't dev/test/production (e.g. UAT), and who must approve production.
- **Ask for just one part** ("only the runbook", "only the pipeline") when that's all you need. The skill scales its answer.
- **Let it write files.** In agentic tools (Claude Code, Codex, Copilot agent mode, Cursor), ask it to create the files in your toolkit repo directly.

---

## What you get

Generated modules follow one repository convention, so a toolkit built over months still feels like one product:

```text
pp-ops-toolkit/
├── .github/workflows/
│   ├── solution-export.yml            # Dev → pull request (unpack managed + unmanaged)
│   ├── solution-build-deploy.yml      # lint, test, version, pack, check → test → approved prod
│   ├── _reusable-import-solution.yml  # per-environment settings injection + import
│   └── op-<module>.yml                # the citizen-developer "Run workflow" form
├── shared/scripts/                    # Dataverse.psm1, New-DeploymentSettings.ps1
├── solutions/<Solution>/              # unpacked solution + module.json + settings template
└── modules/<category>/<module>/       # scripts, schemas, connector, pcf, tests, README runbook
```

For operators, each operation appears in GitHub under **Actions → Run: <name> → Run workflow** as a simple form:

| Field | Type | Default |
|---|---|---|
| Which environment? | Dropdown | `dev` |
| Test run (change nothing) | Toggle | On |
| *Module-specific fields* | Text / dropdown | Explained in plain language |
| Confirm | Text | Type `APPLY` to make real changes |

---

## Prerequisites for the generated automation

The skill itself needs nothing beyond a supported AI tool. The automation it generates expects:

- **Microsoft Power Platform / Dataverse** environments (dev, test, production or your own names)
- A **Microsoft Entra ID app registration** added as an **application user** in each environment, with a least-privilege security role
- A **GitHub repository** with Actions enabled and GitHub **environments** (`dev`, `test`, `production`) holding variables `PP_ENV_URL`, `PP_APP_ID`, `PP_TENANT_ID` and secret `PP_CLIENT_SECRET` (or a federated credential for secretless sign-in)
- For local runs: **PowerShell 7.2+** and the **Power Platform CLI** (`dotnet tool install --global Microsoft.PowerApps.CLI.Tool`)

---

## Repository layout

```text
.
├── skills/                               # ← every skill in this repo (each folder is installed separately)
│   ├── power-platform-alm-toolkit/       #   generates ALM code/pipelines
│   │   ├── SKILL.md                      #     instructions + trigger description
│   │   ├── references/                   #     tooling, Dataverse patterns, repo layout, pipelines, runbook template
│   │   ├── assets/Dataverse.psm1         #     tested PowerShell 7 module the generated code builds on
│   │   └── LICENSE.txt
│   ├── pp-data-ops-agent/                #   queries/bulk ops — live via Dataverse MCP, or generated if not connected
│   │   ├── SKILL.md
│   │   ├── references/data-ops-recipes.md
│   │   └── LICENSE.txt
│   └── pp-governance-agent/              #   role drift, connection-reference & flow health — live or generated
│       ├── SKILL.md
│       ├── references/                   #     mcp-tool-reference, check-recipes, admin-api-patterns
│       └── LICENSE.txt
├── scripts/
│   ├── install.sh / install.ps1         # installers for every supported tool — install every skill above
│   ├── validate.py                      # Agent Skills spec validation, run across all skills
│   ├── check_templates.py               # parses every YAML/JSON example inside any skill
│   └── build.py                         # builds each skill's zip + portable bundle into dist/
├── tests/Dataverse.Tests.ps1            # Pester tests (HTTP fully mocked)
├── docs/                                # chat-assistants.md (ChatGPT, Gemini, Copilot Studio), publishing.md,
│                                         # superpowers/specs|plans (design docs for in-progress skills)
├── examples/prompts.md                  # prompt library
├── evals/                               # evaluation prompts for improving the skills (one file per skill)
└── .github/workflows/                   # CI (validate, test on Win/macOS/Linux, installer smoke tests) + release
```

---

## Development

```bash
pip install pyyaml
python3 scripts/validate.py          # spec checks: name, description length, referenced files exist
python3 scripts/check_templates.py   # every YAML/JSON example in the skill parses
python3 scripts/build.py             # dist/power-platform-alm-toolkit.zip + dist/portable/*
```

```powershell
Install-Module Pester -MinimumVersion 5.5.0 -Scope CurrentUser
Install-Module PSScriptAnalyzer -Scope CurrentUser
Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
Invoke-Pester ./tests -Output Detailed
```

**Releasing:** bump `metadata.version` in `SKILL.md`, update `CHANGELOG.md`, then publish a GitHub release with a matching tag (for example `v0.2.0`). The release workflow builds and attaches the zip, the portable bundle, the chat instructions and checksums.

---

## Roadmap

- [ ] Evaluation runs across the prompts in `evals/` with published results
- [ ] Ready-made reference modules (data dictionary, flow on/off, role sync) in a companion `pp-ops-toolkit` repo
- [ ] Azure DevOps pipeline variants
- [ ] Copilot Studio agent template that calls the toolkit's runbook workflows from natural language
- [ ] Power Pages and Dataverse elastic-table patterns

Ideas welcome: [open an issue](https://github.com/NaveenGaneshe/power-platform-alm-toolkit-skill/issues).

---

## Contributing, security and license

- **Contributing:** see [CONTRIBUTING.md](CONTRIBUTING.md). Improvements to references (new verified patterns, updated PAC CLI parameters) are especially valuable.
- **Security:** please report vulnerabilities privately as described in [SECURITY.md](SECURITY.md).
- **License:** [MIT](LICENSE).

> **Disclaimer:** This is a community project. It is not affiliated with, endorsed by, or supported by Microsoft, Anthropic, OpenAI, GitHub or Google. AI-generated code can be wrong: review it, run it in a non-production environment first, and keep the test-run defaults on until you trust a module. Microsoft, Power Platform, Dataverse, Power Automate, Power Apps and Dynamics 365 are trademarks of the Microsoft group of companies.
