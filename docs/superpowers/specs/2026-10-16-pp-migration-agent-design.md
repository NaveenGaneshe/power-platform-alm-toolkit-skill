# Migration Agent (`pp-migration-agent`) — design

## Purpose

Add a third agent skill, `pp-migration-agent`, that helps with Power Platform "lift & shift"
migration work: moving an environment (or specific records) from one place to another. Three
real, verified scenarios, one skill:

1. **Same-tenant environment copy** — `pac admin copy`.
2. **Cross-tenant environment migration** — the `TenantToTenant-*` PowerShell cmdlets.
3. **Selective record-level lift & shift** — copying specific records matching a description
   from one Dataverse environment to another, without copying the whole environment.

## Why

The user asked for a "Migration Agent" / "lift & shift" agent, covering "all of" the migration
scenarios raised during scoping. Verified against current Microsoft Learn docs rather than
assumed:

- `pac admin copy` is real, scriptable, and self-service, but **always a full overwrite of the
  target** and **cannot target a production environment** (sandbox/preview only as the target).
- Tenant-to-tenant migration is **also self-service** via PowerShell (`TenantToTenant-*`
  cmdlets) — not a support-ticket-only process as commonly assumed. It is a multi-day, multi-step
  process requiring destination-tenant approval, a user-mapping CSV, and substantial
  post-migration cleanup (flows arrive disabled, connection references need re-linking,
  HTTP-triggered flow URLs change, security groups don't migrate).
- Neither of these is a Dataverse MCP tool call — both are `pac` CLI / PowerShell module
  operations. "Live" for these two modes means the agent runs the command itself via its own
  shell tool (e.g. Claude Code's Bash tool), with confirmation, not a Dataverse MCP call.
- Selective record-level copying between two environments *is* a Dataverse MCP scenario — read
  from one environment's MCP connection, write to another — extending `pp-data-ops-agent`'s
  query/preview/confirm shape across two connections instead of one.

## Non-goals

- **Legacy system → Dataverse migration** (CSV, SharePoint lists, on-prem CRM, another vendor's
  CRM) is explicitly out of scope for this skill. There's no live tool for it — it's schema
  mapping plus an import script, which fits `power-platform-alm-toolkit`'s code-generation model,
  not this skill's live/semi-live execution model. When a user asks for this, `pp-migration-agent`
  should say so and point them at the other skill rather than attempting it or silently ignoring
  the request.
- **Solution/component migration between environments** (export → unpack → pack → import via
  GitHub Actions) is already covered by `power-platform-alm-toolkit`'s four-part blueprint. This
  skill doesn't duplicate that; if a request is really "promote my solution to test and prod,"
  redirect to the existing skill.
- Not a new MCP server, not a scheduled/unattended service — same constraints as the other two
  agents in this repo.
- Does not attempt to automate the destination-tenant **approval** step of a tenant-to-tenant
  migration — that step is an Admin Center action taken by a human on the destination tenant and
  cannot be scripted away. The skill's job is to prepare everything up to that point, tell the
  user exactly what to do there, and resume once they confirm it's approved.

## Architecture

```
skills/pp-migration-agent/
├── SKILL.md
├── LICENSE.txt
└── references/
    ├── same-tenant-copy.md       # pac admin copy: exact commands, overwrite warning, polling
    ├── cross-tenant-migration.md # TenantToTenant-* sequence, user-mapping file, post-migration checklist
    └── record-lift-shift.md      # cross-environment query/preview/confirm/copy recipe
```

Same `name`/`description`/`compatibility` frontmatter pattern as the other two skills.
`compatibility` must be explicit that modes 1–2 need `pac` CLI (mode 1) or the
`Microsoft.PowerApps.Administration.PowerShell` module (mode 2) authenticated locally — these
aren't Dataverse MCP tools — while mode 3 needs the Dataverse MCP server connected for both
environments (or falls back to a generated script, same as the other two agents).

## The three modes

### Mode 1: Same-tenant environment copy

- **Gather:** which source and target environment (by name or ID — `pac admin list` if the user
  doesn't have IDs handy), and which copy type: `MinimalCopy` (customizations/schema only) or
  `FullCopy` (everything, including data).
- **Warn, explicitly, before anything else:** this **overwrites and deletes** everything currently
  in the target environment, cannot be undone, cannot target a production environment, and can
  take up to 24 hours for `FullCopy` with a lot of data. State this before asking for
  confirmation, not buried after it.
- **Confirm**, then either run `pac admin copy --source-env <id> --target-env <id> --type
  <MinimalCopy|FullCopy> --name "<target display name>"` directly (if the agent has shell
  execution available and the user confirms running it now) or hand over the exact command for
  the user to run themselves.
- **Report:** point to `pac admin list-backups`/the Admin Center for progress if run async
  (`--async`), and give the documented post-copy action items (custom connectors get new IDs and
  need flows re-pointed; canvas apps only keep their 20 most recent revisions).

### Mode 2: Cross-tenant migration

This is a guided, multi-session process, not a single action — be explicit about that up front.

- **Prerequisites check:** target tenant users must already exist (Entra ID + licenses), the
  `Microsoft.PowerApps.Administration.PowerShell` module must be available, and the user needs
  admin privileges in both tenants (or coordination with an admin who has them).
- **Strongly recommend a test migration first:** copy the production environment to a sandbox
  (mode 1), then migrate *that* sandbox cross-tenant, before ever migrating production directly.
  Say this explicitly; don't let a user skip straight to migrating production.
- **Walk the real sequence**, one step at a time, from `references/cross-tenant-migration.md`:
  build the user-mapping CSV, upload it, prepare the migration, wait for destination-tenant
  approval (tell the user exactly what to tell the destination admin to do — this step can't be
  automated), then trigger the move and poll status.
- **Give the full post-migration checklist** up front, not as a surprise afterward: flows import
  disabled and must be enabled (child flows before parents), connection references need
  re-linking, HTTP-triggered flow URLs change and any caller needs updating, security groups
  don't migrate so the System Administrator role must be reassigned to validating admins
  explicitly, and several Power Pages/Customer Insights/Copilot Studio components need manual
  reconfiguration per `references/cross-tenant-migration.md`.

### Mode 3: Selective record-level lift & shift

- **Gather (source):** run the equivalent of `pp-data-ops-agent`'s Mode 1 query against the
  source environment's Dataverse MCP connection — build the `SELECT`, preview the row count and
  sample, confirm the schema with `describe` first.
- **Gather (target):** call `describe` on the target environment's connection to confirm the
  table/columns exist there too, and check for any records that already look like duplicates
  (e.g. matching on an alternate key or an obvious natural key) so the user can decide whether
  this is a first load or an incremental one.
- **Preview, both sides:** show what will be read from source and what (if anything) already
  exists at the target that might conflict, before any write.
- **Confirm, then copy:** `create_record` (or `update_record` if matching an existing target
  record) against the target environment's connection, one record at a time, in batches, with the
  same per-record failure handling, retry, and summary reporting as `pp-data-ops-agent`.
- **No-MCP fallback:** if either environment's MCP connection isn't available, generate the
  source `SELECT` plus the per-record Web API `POST`/`PATCH` calls against the target, exactly
  like `pp-data-ops-agent`'s no-MCP path — same shape, just across two environments.

## Safety model

- Mode 1: the overwrite warning comes before the confirmation prompt, every time, not as a
  footnote. Never run against anything the user hasn't explicitly named as the target.
- Mode 2: no step beyond "prepare" runs without the user explicitly confirming the previous step
  succeeded — this process spans days and different people (source admin, destination admin);
  the skill must never assume a prior step completed just because time has passed.
- Mode 3: same preview-before-write, confirm-before-write, per-record error isolation, and
  separate-confirmation-for-deletes rules as `pp-data-ops-agent`.
- Across all three modes: if the agent has shell execution available, it still asks before running
  any command that changes state (copy, migrate, create/update/delete record) — having the
  capability to run something isn't the same as having permission to run it yet.
- Never invent a `pac` flag, PowerShell cmdlet, or parameter not verified in the references files.

## Error handling

A failure partway through mode 1 or mode 2 is reported with exactly where it stopped and what
state things are likely in (e.g. "the copy operation is still running — check `pac admin
list-backups` / the Admin Center before retrying, don't start a second copy against the same
target"). Mode 3 follows the same per-record isolation as `pp-data-ops-agent`.

## Testing / rollout

- Add eval scenarios covering all three modes to `evals/pp-migration-agent.evals.json`, checking
  in particular that mode 1 states the overwrite/production-can't-be-a-target warning before
  asking for confirmation, and that a legacy-system migration request gets redirected rather than
  attempted.
- `scripts/validate.py`/`check_templates.py`/`build.py` already generalize across every skill
  under `skills/` — no changes needed there.
- README gets a fourth row in the "Skills in this repo" table, same pattern as the other two
  agents.
