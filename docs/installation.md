# Installation

Every option below installs all five skills together, unless you pick just one (Option 3, or the
`skills` CLI's interactive picker in Option 1). Update by running the installer again.

## Which option fits your AI tool

The skills use the open [Agent Skills](https://agentskills.io/specification) format (`SKILL.md`),
so most modern AI coding tools load them natively. Chat-only assistants use a single-file bundle.

| Tool | How it loads the skills | Quick install |
|---|---|---|
| **Claude Code** | Native skill (`~/.claude/skills` or `.claude/skills`) | `./scripts/install.sh --tool claude` |
| **Claude apps** (claude.ai, desktop, mobile) | Uploaded skill (Pro, Max, Team, Enterprise) | Upload each skill's zip ([Option 4](#option-4-claude-apps-claudeai-desktop-mobile)) |
| **OpenAI Codex** (CLI, IDE, desktop app) | Native skill (`~/.agents/skills` or `.agents/skills`) | `./scripts/install.sh --tool codex` |
| **GitHub Copilot** (VS Code / JetBrains agent mode, CLI, cloud agent) | Native skill (`~/.copilot/skills`, `.github/skills` or `.agents/skills`) | `./scripts/install.sh --tool copilot` |
| **Cursor** | Native skill (`~/.cursor/skills`, `.cursor/skills` or `.agents/skills`) | `./scripts/install.sh --tool cursor` |
| **Gemini CLI** | Native skill (`~/.gemini/skills` or `.agents/skills`) | `./scripts/install.sh --tool gemini` |
| **Windsurf, Cline, OpenCode, Goose, Kiro, Zed and more** | Native skill via the [`skills` CLI](https://github.com/vercel-labs/skills) | `npx skills add NaveenGaneshe/power-platform-alm-toolkit-skill` |
| **ChatGPT** (custom GPT), **Gemini** (Gems), **Microsoft Copilot Studio**, **Claude Projects** | Instructions + knowledge file | [Option 5](#option-5-chatgpt-gemini-copilot-studio-and-other-chat-assistants) |
| **Any other model or API** | Paste or attach the single-file bundle | Use a skill's `<skill-name>.md` as a system prompt or context file ([Option 5](#option-5-chatgpt-gemini-copilot-studio-and-other-chat-assistants)) |

> **Tip:** `--tool all` installs into `~/.claude/skills` *and* the shared `~/.agents/skills`
> folder. Between them, those cover Claude Code, Codex, Copilot, Cursor and Gemini CLI without
> duplicate copies.

## Option 1: One command with the `skills` CLI (any agent)

Requires Node.js 18+.

```bash
npx skills add NaveenGaneshe/power-platform-alm-toolkit-skill            # pick agents interactively
npx skills add NaveenGaneshe/power-platform-alm-toolkit-skill -g -a claude-code -a codex -a cursor
```

## Option 2: Installer scripts

**macOS / Linux / WSL / Git Bash**

```bash
git clone https://github.com/NaveenGaneshe/power-platform-alm-toolkit-skill.git
cd power-platform-alm-toolkit-skill
./scripts/install.sh                     # interactive menu
./scripts/install.sh --tool all          # Claude Code + Codex/Copilot/Cursor/Gemini, for your user
./scripts/install.sh --tool agents --scope project   # commit the skills into the current repo for your whole team

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

Uninstall with `--uninstall` (Bash) or `-Uninstall` (PowerShell).

| `--tool` value | User scope (`--scope user`, default) | Project scope (`--scope project`) |
|---|---|---|
| `claude` | `~/.claude/skills/` | `.claude/skills/` |
| `agents` / `codex` | `~/.agents/skills/` | `.agents/skills/` |
| `copilot` | `~/.copilot/skills/` | `.github/skills/` |
| `cursor` | `~/.cursor/skills/` | `.cursor/skills/` |
| `gemini` | `~/.gemini/skills/` | `.gemini/skills/` |

## Option 3: Manual copy

Copy any of the folders under [`skills/`](../skills) into a directory from the table above. Keep
each folder name exactly as it is in this repo.

## Option 4: Claude apps (claude.ai, desktop, mobile)

1. Download the zip for each skill you want (`power-platform-alm-toolkit.zip`,
   `pp-data-ops-agent.zip`, `pp-governance-agent.zip`, `pp-migration-agent.zip`,
   `pp-integration-agent.zip`) from the
   [latest release](https://github.com/NaveenGaneshe/power-platform-alm-toolkit-skill/releases/latest).
2. In Claude, open **Settings → Capabilities**, make sure **Code execution and file creation** is
   on, then under **Skills** choose **Upload skill** and select each zip.
3. Turn the skills on. On Team and Enterprise plans, owners can provide them to the whole
   organization.

## Option 5: ChatGPT, Gemini, Copilot Studio and other chat assistants

For each skill you want, download `<skill-name>.md` (the whole skill in one file) and
`<skill-name>.instructions.md` from the
[latest release](https://github.com/NaveenGaneshe/power-platform-alm-toolkit-skill/releases/latest),
then follow the [chat assistants guide](chat-assistants.md).

Chat assistants usually can't connect to Dataverse, so the four agents hand you a ready-to-run
query, script or runbook instead of answering live. For live answers, use a tool that can connect
the Dataverse MCP server, such as Claude Code, Claude Desktop or GitHub Copilot. The migration
agent's environment and tenant moves also need the `pac` CLI or PowerShell to run live.

## Check it's working

Start a new session and ask:

> *How many contacts have no email address?*

Without a live connection, you should get a ready-to-run query back rather than a refusal. To check
the code-generation skill, ask *"What's the four-part blueprint you use for Power Platform toolkit
modules?"* and you should get the four section names back. In Claude Code you can also call any
skill by name, for example `/pp-data-ops-agent`; in Codex, `$pp-data-ops-agent`.

## Connect to Dataverse for live answers (optional)

The four agents work without this. Connecting the Dataverse MCP server lets them answer and act
live instead of handing you a query. These steps are for Claude Code; GitHub Copilot and other
tools are similar, see Microsoft's
[Dataverse MCP documentation](https://learn.microsoft.com/power-apps/maker/data-platform/data-platform-mcp).

1. **An admin allows the client, once per environment.** By default only Copilot Studio may use
   the Dataverse MCP server, and other tools get an error. Claude Code connects through
   Microsoft's `@microsoft/dataverse` proxy, which signs in as the **Dataverse CLI** client. In the
   Power Platform admin center: **Manage** → **Environments** → the environment → **Settings** →
   **Product** → **Features** → **Dataverse Model Context Protocol** → **Advanced Settings** →
   open **Dataverse CLI** → set **Is Enabled** to **Yes** → **Save & Close**.
2. **A tenant admin grants consent, once per tenant.** Open
   `https://login.microsoftonline.com/<tenant-id>/adminconsent?client_id=0c412cc3-0dd6-449b-987f-05b053db9457`
   and accept.
3. **Sign in and connect**, replacing the URL with your environment's:

   ```bash
   npx -y @microsoft/dataverse auth create --environment https://yourorg.crm.dynamics.com
   claude mcp add dataverse -t stdio -- npx -y @microsoft/dataverse mcp https://yourorg.crm.dynamics.com
   ```

   Start a new Claude Code session, and the agents can now query that environment. Add one
   connection per environment you want them to reach (for example `dataverse-dev` and
   `dataverse-prod`).

**Cost:** since December 15, 2025, Microsoft bills Dataverse MCP calls from tools other than
Copilot Studio in Copilot Credits. A Dynamics 365 Premium or Microsoft 365 Copilot license waives
this, but only for Dynamics 365 data. The agents keep their calls few and tell you before a run
that will make many.
