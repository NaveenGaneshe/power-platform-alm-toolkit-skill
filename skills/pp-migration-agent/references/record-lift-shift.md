# Selective record-level lift & shift

Copying specific records between two Dataverse environments — not the whole environment (that's
mode 1/2). Same mechanics as `pp-data-ops-agent`, run twice against two different Dataverse MCP
connections (one per environment), plus a target-side existence check.

This covers both a **single entity** ("move these accounts") and a **multi-entity package**
("move these accounts, their contacts, and their open opportunities, with the relationships
between them intact") — read "Multi-entity packages" below before starting anything that spans
more than one table, since a single-entity request migrated in isolation will leave any lookup
to another in-scope entity pointing at a meaningless source-side ID.

## Multi-entity packages: dependency order and the ID crosswalk

When the user's request names more than one entity, or one entity with relationships to others
also in scope, don't run them as independent single-entity jobs. Instead:

1. **Build the dependency order first.** List every entity in scope and the lookup relationships
   between them (call `describe` on each to confirm). An entity with no lookup to another entity
   *in this package* goes first; an entity whose lookup target is also in the package must be
   migrated after that target. State the order to the user before starting (e.g. account →
   contact → opportunity, because contact looks up to account and opportunity looks up to both).
   If two entities in scope look up to each other (a genuine circular dependency), say so and
   agree with the user which direction to resolve first and fix up the reverse lookup in a second
   pass, rather than silently picking one.
2. **Maintain one ID crosswalk for the whole package**, not a fresh one per entity — a simple
   table of `(entity, source id, target id)`, built up as each entity's records are created at
   the target, in the dependency order from step 1.
3. **For each entity, in order:** run the single-entity recipe below (gather, dedupe, match,
   transform, preview, confirm, copy) exactly as written — except when building the record to
   write at the target, resolve every lookup column whose target entity is also in this package
   by looking up the source ID in the crosswalk from step 2, not by copying the source-side GUID.
   If a lookup's target record isn't in the crosswalk yet (out of order, or genuinely not in
   scope), flag that specific record rather than writing a broken or null lookup silently.
4. **Many-to-many (N:N) relationships**, once every entity they connect is migrated: query the
   source intersect table for the association rows, resolve both sides via the crosswalk, and
   `associate` (or create the equivalent intersect record) at the target — same preview-before-
   write rule as everything else in this skill.
5. **One coordinated summary for the whole package**, not one per entity in isolation: per-entity
   created/updated/skipped/failed counts, the N:N associations made, and every lookup that
   couldn't be resolved against the crosswalk, listed explicitly so the user can fix those by
   hand rather than discovering a silently broken relationship later.
6. **Rollback for a package** goes in *reverse* dependency order — delete the entities migrated
   last first (e.g. opportunity, then contact, then account), using the IDs tracked in the
   crosswalk, so you're never trying to delete a parent while a child created in this same run
   still references it.

## Single-entity recipe

### Gather (source)

Call `describe` on the source environment's connection first, then build the read-only query:

```sql
SELECT TOP 500 accountid, name, emailaddress1, createdon
FROM account
WHERE createdon >= '2026-01-01'
```

Always include a `TOP` clause (see `pp-data-ops-agent`'s `references/data-ops-recipes.md` for the
same guidance on choice/lookup columns). Present the row count and a sample before going further.

### Gather (target) — check for existing matches

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

### Deduplicate the source set itself, not just against the target

Before matching against the target, check whether the source result set has duplicates *among
itself* on the same key(s) — a plain re-export or an unclean source often does. Report any
duplicate groups found and ask the user which to keep (first/last by a date column, or let them
pick) rather than silently loading every duplicate as a separate target record.

### Field transformations, not just type coercion

A straight column-to-column copy isn't always the right mapping. Common transformations to call
out and apply, on confirmation, rather than skipping or forcing a bad fit:
- Splitting one source column into several target columns (e.g. a single "full name" field into
  `firstname`/`lastname`), or the reverse (concatenating several into one).
- Recoding source values into Dataverse choice-option values (e.g. a free-text "Active"/"Inactive"
  string into the target's actual choice numeric values) — enumerate the distinct source values
  and get the mapping confirmed before the load, the same way `legacy-to-dataverse.md` handles it.
- Computing a derived value (e.g. a full address built from several source fields) — state the
  exact formula/rule being applied, don't apply a silent default.

### Incremental / repeatable runs

If this isn't a one-time load — the user wants to run this lift & shift again later to pick up
new or changed records — agree on a high-water-mark column (typically `modifiedon` or
`createdon`) and have the user (or you, if tracking state across a session) record the latest
value copied. A later run filters the source query to only rows after that value
(`WHERE modifiedon > '<last-run-value>'`), instead of re-scanning and re-matching the entire
source set every time.

### Preview, both sides, before any write

Report: how many source records match, how many already appear to exist at the target (so the
user can choose first-load vs. incremental), and which columns will be copied.

### Confirm, then copy

For each source record with no match at the target: `create_record` against the target
connection with the mapped field values. For each source record that does match: `update_record`
against the matched target record, only if the user asked for an update-in-place rather than a
skip. Before any `update_record` call, capture the target record's current values for every
column about to change — this is the rollback data, not just a row count, and it must exist
before the write, not be reconstructed after. Batch at 100–200 records, report progress between
batches, isolate per-record failures (same as `pp-data-ops-agent`), and give a final summary:
created (with every created record's ID, so a rollback-by-delete is possible later), updated
(with the before-values captured, so an update can be manually reversed), skipped (already
existed and no update requested, or a within-source duplicate dropped per the user's choice
above), failed (with why). This is the data-quality report, not just a progress count — a user
relying on this instead of a dedicated migration tool needs to see exactly what happened to
every record, not just how many succeeded.

Lookup columns on the source almost never resolve correctly on the target as-is (foreign key IDs
differ between environments) — if a record being copied has a lookup to another table, resolve
the equivalent target-side ID first (by the same alternate-key or natural-key approach above) or
tell the user explicitly that this lookup needs manual remapping rather than copying a source ID
that's meaningless in the target.

### No-MCP fallback

If either environment's Dataverse MCP connection isn't available, generate:
1. The source `SELECT` (for the user to run and get results from, e.g. via `pac env fetch` or the
   TDS endpoint).
2. The per-record Web API calls against the target — `POST <target-org-url>/api/data/v9.2/<entityset>`
   for a create, `PATCH <target-org-url>/api/data/v9.2/<entityset>(<id>)` for an update-in-place —
   built from the source results the user provides back, exactly like `pp-data-ops-agent`'s
   no-MCP path.
