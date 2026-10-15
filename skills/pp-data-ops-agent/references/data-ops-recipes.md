# Data ops recipes

Both modes run through the Dataverse MCP server's `read_query` (read-only Dataverse SQL
`SELECT` over the TDS endpoint) and, for Mode 2 only, its `update_record`/`delete_record` tools.
Call `describe` or `search` first whenever a table or column name isn't already confirmed for
this environment — table names in Dataverse SQL are singular logical names (`account`, `contact`,
`incident`), not the pluralized entity set names used by the OData Web API.

## Building a query (Mode 1 and the Mode 2 preview)

Always include a `TOP` clause — Dataverse returns up to 5,000 rows for standard tables without
one, which is rarely what a plain-language question actually wants:

```sql
SELECT TOP 50 contactid, fullname, emailaddress1, createdon
FROM contact
WHERE emailaddress1 IS NULL
ORDER BY createdon DESC
```

For a count instead of rows:

```sql
SELECT COUNT(*) AS matching_count
FROM incident
WHERE statecode = 0 AND createdon < DATEADD(day, -90, GETUTCDATE())
```

Choice (option set) columns come back as two columns, `<column>value` and `<column>name` — filter
and aggregate on the `value` column (it's indexed), only select the `name` column for display, and
keep the number of choice-label columns in one query under ~10 for performance.

Lookup columns come back as `<lookup>id` and `<lookup>name` (e.g. `ownerid`, `ownername`) — no
extra join is needed to get the display name of a lookup target.

## Applying a bulk change (Mode 2 only, after confirmation)

Never use `UPDATE`/`DELETE` SQL syntax — the TDS/SQL endpoint behind `read_query` is read-only by
design. Writes go through `update_record`/`delete_record`, one call per record, looped over the
IDs returned by the preview query:

- Start at 100–200 records per confirmed batch; if the preview count is larger, process it in
  batches of that size and report progress between batches rather than silently working through
  thousands of records with no interim status.
- On a failure for one record (permission denied, record already deleted by someone else,
  validation error from a plug-in), record it as a per-record failure and continue the batch —
  never abort the whole run over one record.
- Respect Dataverse service protection limits: 6,000 requests and 20 minutes of combined
  execution time per user per 5-minute window, 52 concurrent requests. On an HTTP 429/503-style
  throttling error, back off and retry (the MCP tool surfaces this as a tool error; treat any
  such error as retryable up to 5 attempts with increasing delay before reporting that record as
  failed).
- A deactivate (`statecode`/`statuscode` update) is reversible by re-running the same change in
  the opposite direction — mention this as the undo path in the final summary. A delete is not
  reversible; this is exactly why deletes require their own separate confirmation per `SKILL.md`.

## Report format

Preview (before any write):

`Row count: <n> | Sample (first 10): <table of key columns> | Change: <column> <old> → <new> per record`

Final summary (after a confirmed apply):

`Changed: <n> | Skipped: <n, with reason> | Failed: <n, with reason> | Undo: <what re-running in reverse would do, or "not reversible" for deletes>`
