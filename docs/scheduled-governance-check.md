# Scheduled governance check (GitHub Actions)

Runs `pp-governance-agent`'s three read-only checks (role drift, connection reference health,
post-import flow health) against your Dataverse environments every night, and files the report
as a GitHub issue. Nobody has to remember to kick it off.

## What it does

1. On a schedule (6am UTC by default) or whenever you click **Run workflow** on the Actions tab.
2. Connects to each environment you list, read-only.
3. Asks Claude to run the governance agent's checks and write the report. It never applies a fix
   — a scheduled run has nobody there to confirm one, and the skill itself won't write without
   that confirmation.
4. Opens a new issue titled `Governance report - <date>`, labeled `governance-report`, with the
   full report as the issue body.

## One-time setup

You only touch GitHub's Settings UI — no file or code changes needed after this.

### 1. Add secrets

**Settings > Secrets and variables > Actions > Secrets**, add:

| Secret | What it is |
|---|---|
| `ANTHROPIC_API_KEY` | Your Claude API key |
| `DATAVERSE_CLIENT_ID` | App registration (service principal) client ID |
| `DATAVERSE_CLIENT_SECRET` | That app registration's client secret |
| `DATAVERSE_TENANT_ID` | Your Azure AD tenant ID |

Grant the service principal a **read-only** security role in every environment you list below.
The skill never writes, but it's worth the credential itself not being *able* to either.

### 2. Add the environment list

**Settings > Secrets and variables > Actions > Variables**, add one variable:

| Variable | Value |
|---|---|
| `GOVERNANCE_ENVIRONMENTS` | `Production=https://contoso.crm.dynamics.com,UAT=https://contoso-uat.crm.dynamics.com` |

Comma-separated `name=url` pairs. Add or remove an environment here any time — no workflow edit.

### 3. Verify the Dataverse MCP server's auth flags

The workflow registers each environment's Dataverse MCP server with placeholder flags
(`--client-id`, `--client-secret`, `--tenant-id`). Confirm these match your installed
`@microsoft/dataverse` package's actual non-interactive/service-principal auth options
(`npx -y @microsoft/dataverse mcp --help`) before relying on this in production — this is the
one piece specific to the MCP server's own version that this workflow can't verify for you.

### 4. Test it

Go to the **Actions** tab, pick **Scheduled Governance Check**, click **Run workflow**. Check the
new issue it files.

## Changing the schedule

Edit the `cron:` line in `.github/workflows/governance-check.yml`. Cron is UTC and reads
`minute hour day month weekday` — `0 6 * * *` is 6am UTC daily.

## Alternatives

- **Azure DevOps**: same shape (scheduled pipeline, variable group for secrets, work item or
  email instead of a GitHub issue) if your org runs ADO instead of GitHub.
