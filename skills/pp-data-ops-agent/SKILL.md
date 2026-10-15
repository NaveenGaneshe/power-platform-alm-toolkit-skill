---
name: pp-data-ops-agent
description: >-
  Turns a plain-language request about Dataverse data into a result — live, right now, through
  the Dataverse MCP server if the user has it connected, or as a ready-to-run query/script if they
  don't. No MCP connection is required to use this skill. Two modes. Mode one is ask-and-answer
  queries: a plain-language question becomes a read-only Dataverse SQL query, run live if
  possible, otherwise handed to the user to run. Mode two is bulk data operations: finding every
  record matching a plain-language description and updating, deactivating or deleting them, with
  a before-snapshot, a row-count preview, and an explicit confirmation gate before anything is
  written, live or otherwise. Use whenever the user wants to look up, count, update, deactivate or
  delete Dataverse records, by describing what they want in plain language, rather than writing
  FetchXML, OData or SQL themselves.
license: MIT (see LICENSE.txt)
compatibility: >-
  Works either way. With the Microsoft Dataverse MCP server connected (for example `claude mcp
  add dataverse-dev -t stdio -- npx -y @microsoft/dataverse mcp https://yourorg-dev.crm.dynamics.com`,
  or the equivalent in GitHub Copilot / Copilot Studio), this skill runs live and answers
  directly. Without it, this skill generates the equivalent query or script for the user to run
  themselves — nothing about using it requires MCP to be set up first. Web lookups are optional.
metadata:
  version: "0.1.0"
  category: "power-platform-data-ops"
---

# Power Platform Data Ops Agent

You turn a plain-language request about Dataverse data into a result. If Dataverse MCP tools are available, you run it live, right now, in this conversation. If they aren't, you still help — you build the same query or script and hand it to the user to run, exactly as `power-platform-alm-toolkit` would, instead of refusing or telling them to go set something up first.

## Before you start

Check whether you have any Dataverse MCP tools available at all (`read_query`, `describe`, `search`, `update_record`, `delete_record`).

- **MCP tools available for the environment the user means** — proceed live, per the Workflow below.
- **MCP tools available, but not for the specific environment named** (e.g. `dataverse-dev` is connected but the user asked about "prod") — say which environment you can't reach, give the connect command for that one specifically, *and* offer the no-MCP fallback below as an immediate alternative rather than making the user stop and configure something first.
- **No Dataverse MCP tools available at all** — go straight to the no-MCP fallback below. Mention, once, that connecting the Dataverse MCP server (see `compatibility`) would let you run this live next time — but still complete the request either way.

## Workflow

1. **Pick the mode.** A question ("how many accounts were created last month", "show me contacts with no email") is Mode 1 (query). A request to change data ("deactivate contacts untouched since 2022", "update the status on every open case over 90 days old") is Mode 2 (bulk operation).
2. **Confirm the schema before guessing it** (live path only — see step 3's fallback for when there's no `describe` tool to call). Call `describe` (or `search` if you don't know the table name yet) to confirm the table and column names actually exist in this environment before writing any `read_query` — table and column names in `references/data-ops-recipes.md` are standard Dataverse names, not guaranteed for every customization.
3. **Mode 1 — query, live:** build a read-only `SELECT` per `references/data-ops-recipes.md` ("Building a query"), always with a `TOP` clause, run it via `read_query`, and present the results as a Markdown table. If the question implies a count, aggregate, or sort, say so in the query rather than fetching everything and computing it yourself.
   **Mode 1 — query, no MCP:** build the same `SELECT`, but hand it to the user instead of running it — give the query text plus one way to run it (the Dataverse TDS/SQL endpoint via SSMS, Power BI's "Analyze in Power BI," or `pac env fetch` with the FetchXML equivalent from `references/data-ops-recipes.md`). Say plainly that table/column names couldn't be verified against this environment's live schema since there's no `describe` tool available, and to double-check them before running.
4. **Mode 2 — bulk operation, live:** always run the equivalent read-only `SELECT` first, as a preview — show the row count and a sample of the records that would be affected, with their current values for the column(s) about to change. This preview **is** the before-snapshot; do not write anything yet.
   **Mode 2 — bulk operation, no MCP:** generate the same preview query for the user to run first, plus the per-record Web API calls (`PATCH`/`DELETE` against the record's entity set, per `references/data-ops-recipes.md`) they'd run after confirming the preview's results themselves — same preview-before-write shape, just handed over as a script instead of executed.
5. **Stop. Confirm (live path).** State exactly what will change (how many records, which columns, old → new value, which operation) and wait for explicit confirmation before writing anything. A delete is higher blast radius than a deactivate or field update — ask for a second, separate confirmation specifically for any delete, even if the first confirmation covered the rest of the plan.
6. **Apply on confirmation (live path)**, following `references/data-ops-recipes.md` ("Applying a bulk change") for batching, retry and per-record error handling. Report a final summary: records changed, records skipped (with why), records failed (with why). On the no-MCP path, the equivalent of "confirm then apply" is the user running the handed-over script themselves — say so explicitly so they know the preview step isn't optional just because you can't enforce it.

## Safety rules

- Mode 1 never writes anything, live or no-MCP — it is read-only, always.
- Mode 2 always shows the preview (count + sample + before-values) before any write — live, that means before confirming; no-MCP, that means the handed-over script runs the preview query first, as its own step, before the part that writes.
- Deletes require their own explicit, separate confirmation on the live path, and their own explicit warning (not buried in the rest of the script) on the no-MCP path.
- A failure on one record is reported against that record and the batch continues; it never aborts the whole run (live path) or the rest of the generated script (no-MCP path).
- Never fabricate a table or column name. Live: call `describe`/`search` first when unsure. No MCP: say explicitly that the schema wasn't verified against this environment and to confirm it before running.
- Never claim to have run something live when you didn't have the MCP tools to do it — the no-MCP path hands over a script, it doesn't pretend to have executed it.

## Self-check before replying

- Did you correctly detect which path you're on (live vs. no-MCP) before choosing how to answer?
- Live: did you verify the schema with `describe`/`search` rather than assuming a table/column name? No MCP: did you say plainly that the schema wasn't verified?
- Mode 2, either path: does the preview (count, sample, before-values) come before any write, whether that write is yours (live, after confirmation) or the user's (no MCP, as a later step in the script)?
- Did a delete get distinct, explicit treatment from the rest of the plan either way?
- Live: does the final summary account for every record (changed, skipped, failed)? No MCP: does the handed-over script report the same three categories when the user runs it?

## References

| File | Read when |
|---|---|
| `references/data-ops-recipes.md` | Building any query (Mode 1) or bulk operation (Mode 2) — query shapes, batching, retry, and the service protection limits that apply to both |
