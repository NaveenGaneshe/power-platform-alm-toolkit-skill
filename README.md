<p align="center">
  <img src="docs/images/header.svg" alt="Five AI agent skills, ALM Toolkit, Data Ops, Migration, Governance and Integration, working around Dataverse inside Power Platform" width="100%">
</p>

# Power Platform ALM Toolkit

[![CI](https://github.com/NaveenGaneshe/power-platform-alm-toolkit-skill/actions/workflows/ci.yml/badge.svg)](https://github.com/NaveenGaneshe/power-platform-alm-toolkit-skill/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Agent Skills](https://img.shields.io/badge/format-Agent%20Skills%20(SKILL.md)-6f42c1)](https://agentskills.io/specification)
![Status](https://img.shields.io/badge/status-preview%20v0.1.0-orange)

**Five skills that turn your AI assistant into a careful Power Platform expert.** Ask in plain
language, in Claude, GitHub Copilot, Codex, Cursor, Gemini or a chat assistant. The skills answer
questions about your Dataverse data, check the health of your environments, plan migrations and
integrations, and build ALM pipelines and scripts. They always show you what will change before
anything changes.

## What you can ask

| Skill | Use it to | Try asking |
|---|---|---|
| [`pp-data-ops-agent`](skills/pp-data-ops-agent) | Look up, count, update, deactivate or delete records | *"How many contacts have no email address?"* |
| [`pp-governance-agent`](skills/pp-governance-agent) | Check security roles, connection references and flows | *"Why won't my flows turn on after the import?"* |
| [`pp-migration-agent`](skills/pp-migration-agent) | Copy environments, move tenants, or move records and old data into Dataverse | *"Copy our dev environment into a new UAT sandbox."* |
| [`pp-integration-agent`](skills/pp-integration-agent) | Connect Dataverse to a CRM, accounting, e-commerce or other platform | *"Keep our contacts in sync with our CRM, with no duplicates."* |
| [`power-platform-alm-toolkit`](skills/power-platform-alm-toolkit) | Build pipelines, scripts and runbooks to keep in Git | *"Build a pipeline that promotes our HRCore solution from dev to UAT to prod."* |

You don't need to name the skill. Describe what you want, and the right one picks up the request.

## How it works

- **Live, or ready to run.** If your AI tool is connected to Dataverse, the agents answer and act
  right away. If it isn't, they hand you a ready-to-run query, script or runbook instead. You don't
  need any setup to start.
- **Nothing changes without your OK.** Every change is previewed first: how many records, which
  fields, old and new values. It runs only after you confirm. Deletes get their own separate
  confirmation, and the way to undo is stated before anything runs.
- **Built on checked facts.** Commands, API calls and table names come from verified reference
  files, not guesses. When something can't be verified, the agent says so.

## Get started

**1. Install.** Pick the line for your setup:

```bash
# Claude Code, Codex, GitHub Copilot, Cursor, Gemini CLI and many more (needs Node.js 18+)
npx skills add NaveenGaneshe/power-platform-alm-toolkit-skill

# macOS / Linux, without Node.js
curl -fsSL https://raw.githubusercontent.com/NaveenGaneshe/power-platform-alm-toolkit-skill/main/scripts/install.sh | bash -s -- --tool all
```

```powershell
# Windows
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/NaveenGaneshe/power-platform-alm-toolkit-skill/main/scripts/install.ps1))) -Tool all
```

Using claude.ai, ChatGPT, Gemini or Copilot Studio? See the [installation guide](docs/installation.md)
for every option.

**2. Ask something.** Start a new session and try *"How many contacts have no email address?"*.
Without a live connection, you get a query you can run yourself.

**3. Connect live (optional).** To get answers straight from your environment, connect the
Dataverse MCP server. An admin has to allow it once per environment, and Microsoft bills these
calls in Copilot Credits. The [installation guide](docs/installation.md#connect-to-dataverse-for-live-answers-optional)
has the steps.

## Learn more

- [User guide](docs/user-guide.md): how to ask so you get a good result first time, and what each
  skill does.
- [Prompt library](examples/prompts.md): copy-paste prompts for every skill.
- [Installation guide](docs/installation.md): every AI tool, and connecting to Dataverse.
- [Scheduled governance check](docs/scheduled-governance-check.md): run the governance checks every
  night and get the report as a GitHub issue.
- [Contributing](CONTRIBUTING.md): repository layout, local checks and how to propose changes.

## Good to know

This is a community project. It is not affiliated with, endorsed by, or supported by Microsoft,
Anthropic, OpenAI, GitHub or Google. AI output can be wrong: review it, try it in a non-production
environment first, and keep the test-run defaults on until you trust it. Microsoft, Power Platform,
Dataverse, Power Automate, Power Apps and Dynamics 365 are trademarks of the Microsoft group of
companies.

Report security issues privately, as described in [SECURITY.md](SECURITY.md).
Licensed under [MIT](LICENSE).
