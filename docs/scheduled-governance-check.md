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

**Use a private repository.** The report names users, security roles and broken connections, and
issues in a public repository can be read by anyone. The workflow's first step stops the run if the
repository is public. To use it, copy `.github/workflows/governance-check.yml` and the `scripts/`
and `skills/` folders into a private repository (or fork this one and make the fork private), then
follow the steps below there.

You touch GitHub's Settings UI and, once per environment, the Power Platform admin center — no
file or code changes needed after this.

### 1. Add secrets

**Settings > Secrets and variables > Actions > Secrets**, add:

| Secret | What it is |
|---|---|
| `ANTHROPIC_API_KEY` | Your Claude API key |
| `DATAVERSE_CLIENT_ID` | App registration (service principal) client ID |
| `DATAVERSE_TENANT_ID` | Your Azure AD tenant ID |

No client secret is needed or stored — this workflow authenticates to Azure AD via **federated
credentials (OIDC)**. On the app registration, go to **Certificates & secrets > Federated
credentials > Add credential**, pick the "GitHub Actions deploying Azure resources" scenario, and
point it at this repo and branch `main`.

Grant the service principal a **read-only** security role in every environment you list below.
The skill never writes, but it's worth the credential itself not being *able* to either.

### 2. Add the environment list

**Settings > Secrets and variables > Actions > Variables**, add one variable:

| Variable | Value |
|---|---|
| `GOVERNANCE_ENVIRONMENTS` | `Production=https://contoso.crm.dynamics.com,UAT=https://contoso-uat.crm.dynamics.com` |

Comma-separated `name=url` pairs. Names may use letters, digits, `-` and `_` only (they become part
of the MCP server name). Add or remove an environment here any time — no workflow edit.

### 3. Allow the service principal on the Dataverse MCP server

By default each environment only lets Copilot Studio use the Dataverse MCP server, and any other
client gets `403 Forbidden`. This workflow signs in as your service principal (through Microsoft's
`@microsoft/dataverse` proxy with GitHub federated auth), so it's the service principal's app ID
that has to be allowed, once per environment in `GOVERNANCE_ENVIRONMENTS`:

Power Platform admin center → **Manage** → **Environments** → the environment → **Settings** →
**Product** → **Features** → **Dataverse Model Context Protocol** → make sure **Allow MCP clients to
interact with Dataverse MCP server** is on → **Advanced Settings** → add a new client entry with
any name and the app ID from `DATAVERSE_CLIENT_ID` → set **Is Enabled** to **Yes** → **Save & Close**.

The service principal also needs to be an application user in each environment, with the
read-only role from step 1.

### 4. Test it

Go to the **Actions** tab, pick **Scheduled Governance Check**, click **Run workflow**. Check the
new issue it files.

## Cost

Each run makes Dataverse MCP tool calls, and since December 15, 2025 Microsoft bills those in
Copilot Credits when they come from tools other than Copilot Studio (a Dynamics 365 Premium or
Microsoft 365 Copilot license waives this, but only for Dynamics 365 data). The run also uses
your Claude API key. Both scale with how many environments you list and how often the schedule
fires, so a daily run across many environments adds up. Run it weekly (see below) if daily is
more than you need.

## Changing the schedule

Edit the `cron:` line in `.github/workflows/governance-check.yml`. Cron is UTC and reads
`minute hour day month weekday` — `0 6 * * *` is 6am UTC daily; `0 6 * * 1` is 6am UTC every Monday.

## Safety model

- **Run-as identity**: a read-only Dataverse service principal, authenticated via Azure AD
  federated credentials — no client secret is stored anywhere, in GitHub or otherwise.
- **Where the report goes**: a GitHub issue, so the workflow refuses to run in a public repository.
- **What Claude may do**: the workflow installs the skills first, so the run follows
  `pp-governance-agent`'s tested checks. It pre-approves only the Dataverse MCP read tools
  (`read_query`, `describe`, `search`) plus reading the skill's own files. An unattended run can't
  approve anything else, so a write tool call is refused even if data in an environment tries to
  talk the model into one.
- **Blast radius**: none. Every check this workflow runs is read-only, and the skill it invokes
  never applies a fix without an explicit human confirmation that an unattended run can't give.
- **Rollback**: nothing to roll back — this workflow never changes state.

## Alternatives

- **Azure DevOps**: same shape (scheduled pipeline, variable group for secrets, work item or
  email instead of a GitHub issue) if your org runs ADO instead of GitHub.
