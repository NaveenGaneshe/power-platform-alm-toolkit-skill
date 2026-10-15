# Cross-tenant environment migration

Verified against `learn.microsoft.com/power-platform/admin/move-environment-tenant`. This is a
self-service PowerShell process (no Microsoft support ticket required), but it spans multiple
sessions and two different admins (source tenant, destination tenant) — present it as a guided
process, not a single command.

## What actually happens

The environment doesn't physically move. The Dataverse organization is *linked* to the
destination tenant instead; the source tenant keeps an empty environment shell (delete it once
the move is confirmed and no longer needed). The environment URL, org ID, and name stay the same.

## Supported / unsupported

- Supported: production and sandbox environments.
- Not supported: default, developer, trial, Teams environments; GCC↔public cloud moves; Dynamics
  365 Customer Voice, Omnichannel for Customer Service, component libraries; an environment whose
  Dataverse org is linked to a Finance & Operations org.
- Target-tenant users must already exist (Microsoft 365 + Entra ID, licensed) before starting.

## Scope: one environment, or a whole tenant

There is no single verified command that migrates "a whole tenant" in one call. Moving every
environment in a tenant means running the full per-environment sequence below once per
environment, one at a time — not in parallel, since each needs its own user-mapping file and its
own destination-tenant approval. Use `pac admin list` to enumerate the source tenant's
environments if the user wants "everything" moved. Report each environment's migration status
individually at the end; never roll several environments' outcomes into one pass/fail.

## Recommend this before anything else, for every environment in scope

Copy the production environment to a sandbox first (mode 1 of this skill), then run the
cross-tenant migration against *that* sandbox, to validate the whole process before ever moving
production. State this to the user explicitly; don't let them skip straight to production.

## Back up before you migrate

```
pac admin backup --environment <source-env-id> --label "pre-migration-backup-2026-10-16"
```

The environment itself isn't deleted by a cross-tenant move — the Dataverse org is linked to the
new tenant and the source keeps an empty shell — but a backup protects against a failed or
partial migration. Don't suggest deleting the source environment's shell until the user confirms
the destination is validated and working; once a migration has moved real data and the source is
deleted, there is no documented undo for the move itself.

## The sequence (source tenant admin, except where noted)

```powershell
Add-PowerAppsAccount
TenantToTenant-ViewMigrationRequest
# -> gives the MigrationId to use in the commands below

TenantToTenant-UploadUserMappingFile -EnvironmentName <EnvironmentId> -UserMappingFilePath "C:\path\usermapping.csv"
# -> returns a SAS URI; use it as -ReadOnlyUserMappingFileContainerUri below

TenantToTenant-PrepareMigration -MigrationId <MigrationId> -TargetTenantId <TargetTenantId> -ReadOnlyUserMappingFileContainerUri <SasUri>

TenantToTenant-GetMigrationStatus -MigrationId <MigrationId>
# -> poll this; validation can take a while depending on user-mapping file size
```

**Stop here and tell the user to have the destination-tenant admin approve the request** — this
step happens in the destination tenant and cannot be done from the source side:

```powershell
# Destination tenant admin runs:
Add-PowerAppsAccount
TenantToTenant-ViewApprovalRequest
TenantToTenant-ManageMigrationRequest -MigrationId <MigrationId>   # approve or reject
```

Requests expire after 7 days if not approved. Once the admin confirms approval, resume:

```powershell
# Source tenant admin runs:
TenantToTenant-MigratePowerAppEnvironment -MigrationId <MigrationId> -TargetTenantId <TargetTenantId>
TenantToTenant-GetMigrationStatus -MigrationId <MigrationId>
# Expect: "Migrate Environment: Running" then "Migrate Environment: Succeeded"
```

Allow up to 24 hours; a migration that looks stalled hasn't necessarily failed.

The same process has an Admin Center UI equivalent (**Manage → Environments → select
environment → Move environment**, destination tenant reviews under **Review moves**, source
tenant selects **Begin move**) if the user prefers clicking through it instead of PowerShell.

## User-mapping file format and common errors

CSV, two columns per line, no header shown in the examples: `source-email,destination-email`.
Documented validation errors to watch for:

- **Duplicate source email on multiple lines.**
- **Invalid email format.**
- **Destination email same as source email** on a line.
- **A line with other than exactly two columns** (stray commas).

If `TenantToTenant-GetMigrationStatus` reports "Validation Failed," it returns a SAS URL to an
error report — tell the user to open it, fix the listed rows, and re-upload via
`TenantToTenant-UploadUserMappingFile` with the same SAS URI before re-running `PrepareMigration`.

## Post-migration checklist (give this up front, not as a surprise)

- **Flows import disabled.** Enable child flows before any parent flow that calls them, or the
  parent will error on first run.
- **Connection references need re-linking** — open each solution, reauthenticate or link each
  connection reference to an existing (or new) connection in the destination tenant.
- **HTTP-triggered flow URLs change on import.** Any caller (external system, parent flow) needs
  the new URL.
- **Security groups do not migrate.** Explicitly reassign the System Administrator role to every
  admin who needs to validate the migration — otherwise they'll see an empty-looking environment
  due to missing permissions, not missing data. Confirm this before opening a support request
  over "empty data."
- **Non-solution-aware canvas apps** must be individually exported before migration and
  re-imported (**Apps → Import canvas app**) after.
- **Copilot Studio**: re-import exported solution packages and confirm solution contents.
- **Power Pages**: reprovision each website with the same portal type and language.
- **Customer Insights – Journeys**: has its own extra post-migration steps; point the user at
  Microsoft's Customer Insights migration doc rather than improvising these.
- Mailboxes auto-configure only if the mapped user already has one in the destination tenant;
  otherwise reconfigure manually.

## Tenant-level artifacts (only relevant when moving a whole tenant)

These live above any individual environment and have no verified migrate command — review and
manually recreate them in the destination tenant once every environment is moved:

```
pac admin dlp-policy list
pac admin dlp-policy show --policy-id <id>
pac admin list-groups
pac admin list-tenant-settings
```

Say plainly to the user that these need manual review and recreation in the destination tenant —
don't imply any of them transfer automatically, and don't invent a migrate command for them.
