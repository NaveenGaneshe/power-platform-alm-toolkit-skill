# Dataverse MCP server — tool catalog and gaps

The Microsoft Dataverse MCP server (GA since December 2025) is the live connection this skill
depends on. It respects the calling user's Dataverse security role — no separate permission
model is needed. Connect one server per environment you want to check (`claude mcp add
<name> -t stdio -- npx -y @microsoft/dataverse mcp <org-url>`, or your AI tool's equivalent).

## Tools this skill uses

| Tool | What it does | How this skill uses it |
|---|---|---|
| `describe` | Returns schema/metadata for tables, searching matched results from `search`. Replaces the older `describe_table`/`list_tables`/`fetch` tools. | Call this **before** any `read_query` to confirm a table or column actually exists in this environment and under the name you expect — never assume `systemuserroles`, `connectionreference`, etc. exist unchanged across every Dataverse version without checking. |
| `search` | Searches table schemas and metadata by keyword (not row data). | Use to find the right table name when you're unsure (e.g. searching "connection reference" to confirm the table's exact logical name in this environment). |
| `read_query` | Runs a read-only Dataverse SQL `SELECT` query against the TDS endpoint. No `INSERT`/`UPDATE`/`DELETE` — this is why all three check modes are safe to run freely in the "gather" step. | The primary tool for every "gather" and "compare" step in `references/check-recipes.md`. Returns at most 20 rows: a `TOP` above 20 is rejected, and `OFFSET … FETCH` is silently ignored. Count first and page by primary key, as `references/check-recipes.md` describes. |
| `update_record` | Updates an existing row in a Dataverse table. | The only tool this skill uses to apply a confirmed fix (e.g. adding a role assignment, re-pointing a connection reference, turning a flow back on) — never called until the user has explicitly confirmed that specific fix. |
| `search_data` | Searches structured/unstructured row data (only available when Dataverse search is enabled for the environment). | Not used by this skill's core modes; mentioned here so you don't confuse it with `read_query` — `search_data` is relevance search, not a SQL filter. |

## Tools that exist but this skill does not use

`create_record`, `delete_record`, `create_table`, `update_table`, `delete_table`, `upsert_skill`,
`delete_skill`, `init_file_upload`, `commit_file_upload`, `file_download` are all part of the same
MCP server but outside this skill's scope (none of the three modes create or delete rows, change
schema, or move files). Do not reach for them unless a user explicitly asks for something beyond
the three modes this skill covers — if they do, that's a new check, not this skill.

## What the Dataverse MCP server cannot do (the gaps `admin-api-patterns.md` fills)

- **No cross-environment comparison.** Each MCP server connection is scoped to one environment.
  Role drift (mode 1) requires calling `read_query` once per environment server and diffing the
  results yourself — there's no built-in "compare" tool.
- **No unmanaged-layer detection.** Nothing in the Dataverse MCP tool set, the Dataverse Web API,
  or the `pac` CLI exposes whether a component has an active unmanaged layer — this is a Maker
  Portal-only concept (Solution → component → "See solution layers"). `references/admin-api-patterns.md`
  states this gap explicitly; do not fabricate a command for it.
- **No environment listing or tenant-wide security role listing.** These come from `pac admin list`
  and `pac admin list-roles` respectively (see `references/admin-api-patterns.md`), not the
  Dataverse MCP server, which only ever talks to the one environment it's connected to.

## Cost note

Dataverse MCP tool calls from non-Copilot-Studio clients (including Claude Code, Claude Desktop,
and GitHub Copilot) are billed in Copilot Credits, since December 15, 2025. A Dynamics 365 Premium
or Microsoft 365 Copilot license waives the charge, but only for Dynamics 365 data. `search_data`
bills at the Tenant graph grounding rate; every other tool, including the metadata `search`, at
the "Text and generative AI tools (basic)" per-10-responses rate. Mention this to the user the
first time a session runs a check that will make several tool calls (e.g. one `read_query` per
environment in a multi-environment role-drift audit), so they aren't surprised by it, and follow
"Keep MCP calls lean" in `SKILL.md`.
