# Same-tenant environment copy

Verified against `learn.microsoft.com/power-platform/developer/cli/reference/admin` and
`learn.microsoft.com/power-platform/admin/copy-environment`.

## Find environment IDs if the user doesn't have them

```
pac admin list
pac admin list --type Sandbox
pac admin list --json
```

## The copy command

```
pac admin copy --name "<target display name>" --source-env <id-or-url> --target-env <id-or-url> --type MinimalCopy
pac admin copy --name "<target display name>" --source-env <id-or-url> --target-env <id-or-url> --type FullCopy
```

- `--type MinimalCopy` — customizations and schema only, no data.
- `--type FullCopy` — everything, including data.
- `--skip-audit-data` — switch; recommended for `FullCopy` unless the user specifically needs
  audit history copied too (it increases duration otherwise).
- `--async` — returns immediately instead of waiting; without it, the command waits up to
  `--max-async-wait-time` minutes (default 60) before timing out, even though the operation
  itself keeps running server-side and can take up to 24 hours for a large `FullCopy`.

## Hard constraints — state these before asking for confirmation

- **Full overwrite.** Everything currently in the target is deleted and replaced. This cannot be
  undone from within the copy operation itself.
- **No production targets.** You can only copy *to* a sandbox or preview environment, never to a
  production environment. The source can be any type.
- **Same tenant and region only.** `pac admin copy` cannot cross a tenant boundary — that's mode
  2 (`references/cross-tenant-migration.md`).
- Components not added to a solution (loose canvas apps, flows, custom connectors, connections)
  may not be included in the copy — tell the user to validate these post-copy.

## Backup before you copy (the only rollback path)

`pac admin copy` has no undo. If the target environment has anything worth keeping, back it up
first:

```
pac admin backup --environment <target-id> --label "pre-copy-backup-2026-10-16"
```

To recover if the copy didn't go as planned:

```
pac admin list-backups --environment <target-id>
pac admin restore --selected-backup latest --source-env <target-id>
pac admin restore --selected-backup '12/01/2026 09:00' --source-env <target-id> --target-env <target-id>
```

`--selected-backup` takes `latest` or a timestamp in `mm/dd/yyyy hh:mm` format. `--target-env`
defaults to `--source-env` if omitted (i.e. restore back onto the same environment). If the
target was genuinely empty/disposable before the copy, say so instead of backing up nothing.

## Checking progress

```
pac admin status
```

Lists the status of all in-progress tenant operations, including an async copy. The Admin
Center's Environments page also shows copy status visually if the user prefers that.

## Post-copy action items (always mention these)

- **Custom connectors get a new identifier in the target environment** and appear as a new
  connector — flows that used the old one need to be re-pointed. Review the custom connectors
  page to confirm they published correctly.
- **Canvas apps only keep their 20 most recent revisions** through the copy.
- The target environment is placed in Administration mode after the copy completes, with
  background operations disabled — tell the user they'll need to take it out of Administration
  mode (via the Admin Center) before flows and other background operations resume.
