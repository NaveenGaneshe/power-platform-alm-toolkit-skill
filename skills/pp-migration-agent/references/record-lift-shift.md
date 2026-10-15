# Selective record-level lift & shift

Copying specific records between two Dataverse environments — not the whole environment (that's
mode 1/2). Same mechanics as `pp-data-ops-agent`, run twice against two different Dataverse MCP
connections (one per environment), plus a target-side existence check.

## Gather (source)

Call `describe` on the source environment's connection first, then build the read-only query:

```sql
SELECT TOP 500 accountid, name, emailaddress1, createdon
FROM account
WHERE createdon >= '2026-01-01'
```

Always include a `TOP` clause (see `pp-data-ops-agent`'s `references/data-ops-recipes.md` for the
same guidance on choice/lookup columns). Present the row count and a sample before going further.

## Gather (target) — check for existing matches

Call `describe` on the target environment's connection too, to confirm the same table/columns
exist there. Then ask the user what counts as a duplicate — there's no universal rule, since it
depends on whether an alternate key exists:

```sql
-- Example: matching contacts by email as a natural key
SELECT contactid, emailaddress1
FROM contact
WHERE emailaddress1 IN ('a@example.com', 'b@example.com')
```

If the table has a defined alternate key, prefer matching on that. If not, tell the user plainly
that without one, this is a best-effort match and ask them to confirm the matching column(s)
before proceeding — don't guess silently.

## Preview, both sides, before any write

Report: how many source records match, how many already appear to exist at the target (so the
user can choose first-load vs. incremental), and which columns will be copied.

## Confirm, then copy

For each source record with no match at the target: `create_record` against the target
connection with the mapped field values. For each source record that does match: `update_record`
against the matched target record, only if the user asked for an update-in-place rather than a
skip. Before any `update_record` call, capture the target record's current values for every
column about to change — this is the rollback data, not just a row count, and it must exist
before the write, not be reconstructed after. Batch at 100–200 records, report progress between
batches, isolate per-record failures (same as `pp-data-ops-agent`), and give a final summary:
created (with every created record's ID, so a rollback-by-delete is possible later), updated
(with the before-values captured, so an update can be manually reversed), skipped (already
existed and no update requested), failed (with why).

Lookup columns on the source almost never resolve correctly on the target as-is (foreign key IDs
differ between environments) — if a record being copied has a lookup to another table, resolve
the equivalent target-side ID first (by the same alternate-key or natural-key approach above) or
tell the user explicitly that this lookup needs manual remapping rather than copying a source ID
that's meaningless in the target.

## No-MCP fallback

If either environment's Dataverse MCP connection isn't available, generate:
1. The source `SELECT` (for the user to run and get results from, e.g. via `pac env fetch` or the
   TDS endpoint).
2. The per-record Web API calls against the target — `POST <target-org-url>/api/data/v9.2/<entityset>`
   for a create, `PATCH <target-org-url>/api/data/v9.2/<entityset>(<id>)` for an update-in-place —
   built from the source results the user provides back, exactly like `pp-data-ops-agent`'s
   no-MCP path.
