# Migration Agent (`pp-migration-agent`) — design

## Purpose

Add a third agent skill, `pp-migration-agent`, that helps with Power Platform "lift & shift"
migration work: moving an environment, a whole tenant's worth of environments, specific records,
or data from a legacy system — into or between Dataverse environments. Four scenarios, one skill:

1. **Same-tenant environment copy** — `pac admin copy`.
2. **Tenant-to-tenant migration** — one environment, or a whole tenant's worth of environments,
   moved to a different tenant, via the `TenantToTenant-*` PowerShell cmdlets looped per
   environment, plus the tenant-level artifacts that don't travel with any one environment.
3. **Selective record-level lift & shift** — copying specific records matching a description
   from one Dataverse environment to another, without copying the whole environment.
4. **Legacy system → Dataverse migration** — schema mapping and a staged data load from a
   non-Dataverse source (CSV, SharePoint list, on-prem CRM export, another vendor's CRM) into
   Dataverse, using the Dataverse MCP server's schema tools where live, or a generated script
   otherwise.

## Why

The user asked for a "Migration Agent" / "lift & shift" agent and, after an initial narrower
scope (environment/record migration only, legacy and multi-environment explicitly excluded),
asked to broaden it twice: cover legacy-system → Dataverse migration too, and cover moving a
whole tenant, not just one named environment. Verified against current Microsoft Learn docs
rather than assumed:

- `pac admin copy` is real, scriptable, and self-service, but **always a full overwrite of the
  target** and **cannot target a production environment** (sandbox/preview only as the target).
- Tenant-to-tenant migration is **self-service** via PowerShell (`TenantToTenant-*` cmdlets) —
  not a support-ticket-only process as commonly assumed. It operates **per environment** — there
  is no single verified command that migrates "a whole tenant" in one call. Moving every
  environment in a tenant means running the same per-environment sequence once per environment,
  plus handling tenant-level settings (DLP policies, environment groups, tenant settings) that
  live above any individual environment and have no migrate command at all — these must be
  reviewed and manually recreated in the destination tenant.
- Neither same-tenant copy nor tenant-to-tenant migration is a Dataverse MCP tool call — both are
  `pac` CLI / PowerShell module operations. "Live" for these two modes means the agent runs the
  command itself via its own shell tool (e.g. Claude Code's Bash tool), with confirmation, not a
  Dataverse MCP call.
- Selective record-level copying between two environments *is* a Dataverse MCP scenario — read
  from one environment's MCP connection, write to another — extending `pp-data-ops-agent`'s
  query/preview/confirm shape across two connections instead of one.
- Legacy-system migration has no live connectivity to arbitrary external systems — this skill
  cannot reach into an on-prem SQL Server or another vendor's CRM API itself. What it *can* do
  live is the Dataverse side: propose a table/column mapping, create or update the target schema
  via the Dataverse MCP server's `create_table`/`update_table` tools (on confirmation), and load
  data the user provides (pasted, or read from a file) via batched `create_record` calls — the
  same preview/confirm/batch shape as every other write path in this skill. Getting data *out* of
  the legacy system is the user's or a separate tool's job; this skill starts once the data is in
  a form it can read (CSV/JSON/a query result).

## Non-goals

- **Solution/component promotion between environments** (export → unpack → pack → import via
  GitHub Actions, dev→test→prod) is already covered by `power-platform-alm-toolkit`'s four-part
  blueprint. This skill doesn't duplicate that; if a request is really "promote my solution to
  test and prod," redirect to the existing skill.
- Not a new MCP server, not a scheduled/unattended service — same constraints as the other two
  agents in this repo.
- Does not attempt to automate the destination-tenant **approval** step of a tenant-to-tenant
  migration, for any individual environment in scope — that step is an Admin Center action taken
  by a human on the destination tenant and cannot be scripted away. The skill's job is to prepare
  everything up to that point, tell the user exactly what to do there, and resume once they
  confirm it's approved.
- Does not connect live to the legacy source system itself (mode 4) — it works from data the user
  provides, and proposes/applies the Dataverse-side schema and load.

## Architecture

```
skills/pp-migration-agent/
├── SKILL.md
├── LICENSE.txt
└── references/
    ├── same-tenant-copy.md       # pac admin copy: exact commands, overwrite warning, polling
    ├── cross-tenant-migration.md # TenantToTenant-* sequence (per environment), tenant-level
    │                               artifacts checklist (DLP, environment groups, tenant settings)
    ├── record-lift-shift.md      # cross-environment query/preview/confirm/copy recipe
    └── legacy-to-dataverse.md    # schema mapping, create_table/update_table, staged load recipe
```

Same `name`/`description`/`compatibility` frontmatter pattern as the other two skills.
`compatibility` must be explicit that modes 1–2 need `pac` CLI (mode 1) or the
`Microsoft.PowerApps.Administration.PowerShell` module (mode 2) authenticated locally — these
aren't Dataverse MCP tools — while modes 3–4 need the Dataverse MCP server connected (both
environments for mode 3; the target environment for mode 4), or fall back to a generated script.

## The four modes

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
- **Report:** point to `pac admin status`/the Admin Center for progress if run async (`--async`),
  and give the documented post-copy action items (custom connectors get new IDs and need flows
  re-pointed; canvas apps only keep their 20 most recent revisions).

### Mode 2: Tenant-to-tenant migration (one environment, or a whole tenant)

This is a guided, multi-session process, not a single action — be explicit about that up front,
and more so when multiple environments are in scope.

- **Scope check first:** ask (if not already clear) whether this is one named environment or
  "everything in this tenant" — the latter means repeating the per-environment sequence below
  once per environment (`pac admin list` to enumerate them), one at a time, not in parallel,
  since each needs its own user-mapping file, its own destination-tenant approval, and its own
  post-migration checklist.
- **Prerequisites check:** target-tenant users already exist (Entra ID + licenses), the
  `Microsoft.PowerApps.Administration.PowerShell` module is available, and the user has admin
  privileges in both tenants (or coordination with an admin who does).
- **Strongly recommend a test migration first:** copy the production environment to a sandbox
  (mode 1), then migrate *that* sandbox cross-tenant, before ever migrating production directly.
  Say this explicitly; don't let a user skip straight to migrating production, for any
  environment in scope.
- **Walk the real sequence**, one step at a time, from `references/cross-tenant-migration.md`,
  per environment: build the user-mapping CSV, upload it, prepare the migration, wait for
  destination-tenant approval (tell the user exactly what to tell the destination admin to do —
  this step can't be automated), then trigger the move and poll status.
- **Give the full post-migration checklist per environment** up front, not as a surprise
  afterward: flows import disabled and must be enabled (child flows before parents), connection
  references need re-linking, HTTP-triggered flow URLs change and any caller needs updating,
  security groups don't migrate so the System Administrator role must be reassigned to validating
  admins explicitly, and several Power Pages/Customer Insights/Copilot Studio components need
  manual reconfiguration per `references/cross-tenant-migration.md`.
- **When the scope is "a whole tenant":** after every environment named has been migrated,
  separately review and help recreate the tenant-level artifacts that don't travel with any
  environment — DLP policies (`pac admin dlp-policy list`/`show` in the source, manually
  recreated in the destination; there's no migrate command for these), environment groups
  (`pac admin list-groups`), and tenant settings (`pac admin list-tenant-settings`) — say plainly
  that these need manual review and recreation, since no verified command moves them.

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

### Mode 4: Legacy system → Dataverse migration

- **Scope the source honestly first:** this skill does not connect live to the legacy system
  itself. Ask the user to provide the source data or its schema (a CSV/JSON sample, an exported
  schema, or a description of the fields) rather than implying it can reach into their old system
  on its own.
- **Propose a mapping:** source field → target Dataverse table/column, flagging data-type
  mismatches (e.g. a free-text status field in the legacy system mapping to a Dataverse choice
  column) and any field with no obvious Dataverse equivalent, per `references/legacy-to-dataverse.md`.
- **Schema, on confirmation:** if the target table/columns don't already exist, call `describe`
  to confirm, then propose the `create_table`/`update_table` calls needed — state exactly what
  will be created before running it, same confirm-before-write rule as everywhere else in this
  skill.
- **Staged load, on confirmation:** load a small sample batch first (e.g. 10–20 records), show
  the user the result, then proceed with the full batched load via `create_record`, with the same
  per-record failure isolation, retry, and summary reporting as mode 3.
- **No-MCP fallback:** generate the schema-creation calls and the batched load script instead of
  running them.

## Safety model

### Backup and rollback (non-negotiable, every mode)

No destructive or data-moving step in this skill runs without a concrete way back, stated to the
user before it runs, not improvised after something goes wrong:

- **Mode 1:** before running `pac admin copy` against any target that already has content worth
  keeping, ask whether the target needs a backup first and, if so, run `pac admin backup
  --environment <target-id> --label "<pre-copy-backup-October-2026>"` (confirmed-real command;
  see `references/same-tenant-copy.md`) before the copy. If the target is empty/disposable, say
  so instead of backing up something with nothing in it. State `pac admin list-backups
  --environment <target-id>` and `pac admin restore --selected-backup latest --source-env
  <target-id>` as the rollback path, and that this is the *only* rollback path — the copy
  operation itself has no undo.
- **Mode 2:** recommend `pac admin backup` on the source environment before migration starts (the
  source keeps its data until the move completes, but a backup protects against a failed or
  partial migration). Explicitly do not suggest deleting the source environment's shell until the
  user confirms the destination is validated and working — the "test migration first" rule in
  Mode 2 above exists specifically so a real rollback option (the untouched source, or a backup of
  it) still exists if the migration itself needs to be redone. State plainly that once a
  migration is confirmed to have moved real data and the source is deleted, there is no
  documented undo for the move itself.
- **Mode 3:** the preview step, which already runs before any write, *is* the rollback data for
  any record this mode updates (not creates) — it must capture the target record's current
  field values for every column about to change, not just a row count, so an update can be
  manually reversed from that captured preview if needed. For records this mode creates fresh,
  rollback means deleting them — track and report every created record's ID in the final summary
  specifically so that's possible, not just a count.
- **Mode 4:** same as mode 3 for the data load (track created record IDs for rollback-by-delete).
  For the schema side, creating a new table is reversible (delete the table), but adding a column
  to an existing table is effectively permanent in practice (removing it back out is its own
  destructive change) — say this plainly when proposing a schema change to an existing table, not
  only a brand-new one.

### Per-mode rules

- Mode 1: the overwrite warning comes before the confirmation prompt, every time, not as a
  footnote. Never run against anything the user hasn't explicitly named as the target.
- Mode 2: no step beyond "prepare" runs without the user explicitly confirming the previous step
  succeeded — this process spans days and different people (source admin, destination admin);
  the skill must never assume a prior step completed just because time has passed. When multiple
  environments are in scope, each one gets its own full confirmation cycle — a single "yes, do
  the whole tenant" does not stand in for confirming each environment's move and each
  environment's post-migration checklist individually.
- Mode 3: same preview-before-write, confirm-before-write, per-record error isolation, and
  separate-confirmation-for-deletes rules as `pp-data-ops-agent`.
- Mode 4: schema changes (`create_table`/`update_table`) are confirmed separately from the data
  load that follows them — creating a table and loading 50,000 rows into it are two different
  blast radii and two different confirmations. The sample-batch-first rule is not optional.
- Across all four modes: if the agent has shell execution available, it still asks before running
  any command that changes state (copy, migrate, create/update table, create/update/delete
  record) — having the capability to run something isn't the same as having permission to run it
  yet.
- Never invent a `pac` flag, PowerShell cmdlet, Dataverse MCP tool parameter, or table/column name
  not verified in the references files or confirmed live via `describe`.

## Error handling

A failure partway through mode 1 or mode 2 is reported with exactly where it stopped and what
state things are likely in (e.g. "the copy operation is still running — check `pac admin status`
/ the Admin Center before retrying, don't start a second copy against the same target"). When
mode 2 covers multiple environments, a failure on one environment's migration is reported against
that environment specifically and does not block starting the next one, but each environment's
status is reported individually in the final summary, never rolled up into one pass/fail. Modes 3
and 4 follow the same per-record isolation as `pp-data-ops-agent`.

## Testing / rollout

- Add eval scenarios covering all four modes to `evals/pp-migration-agent.evals.json`, including
  one for a whole-tenant migration request (multiple environments) and one for a legacy-system
  load, checking in particular that mode 1 states the overwrite/production-can't-be-a-target
  warning before asking for confirmation, and that mode 4 is explicit about not connecting live to
  the legacy source.
- `scripts/validate.py`/`check_templates.py`/`build.py` already generalize across every skill
  under `skills/` — no changes needed there.
- README's "Skills in this repo" row for `pp-migration-agent` is updated to reflect all four
  modes.
