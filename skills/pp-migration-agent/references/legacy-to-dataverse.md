# Legacy system → Dataverse migration

This skill has no live connection to an arbitrary legacy system (on-prem SQL, another vendor's
CRM API, a SharePoint list, an old CRM export). What it does live is the Dataverse side: propose
a mapping, create/update schema on confirmation, and load data the user provides — via the
target environment's Dataverse MCP connection, or a generated script if that's not available.

## Multi-table packages: the legacy source almost always has more than one table

A legacy "customers and orders" export is two (or more) related tables, not one — follow the
same dependency-order and ID-crosswalk approach as `record-lift-shift.md`'s "Multi-entity
packages" section, applied to the legacy side instead of a second Dataverse environment:

1. Identify every source table in scope and the foreign-key relationships between them (ask the
   user, or infer from the provided schema/sample). Order the load so a table referenced by
   another table's foreign key is loaded first (e.g. customers before orders).
2. Build one ID crosswalk for the whole package: `(source table, source key, target Dataverse
   record id)`, filled in as each table's records are created.
3. When mapping a legacy foreign-key column (Step 2 below) whose target table is also in this
   package, resolve it through the crosswalk once that table's records exist at the target —
   never copy the legacy system's raw foreign-key value into a Dataverse lookup column, since it
   means nothing there.
4. If the legacy source also has its own many-to-many structure (a join table), handle it last,
   once both sides it connects are loaded, the same way `record-lift-shift.md` handles N:N.
5. Rollback for a package goes in reverse load order — delete the last-loaded table's records
   first, using the crosswalk, before the tables they depend on.

Everything below (Steps 1–4) applies per table in the package, in the order from step 1 above.

## Step 1: get the source data or schema from the user

Ask for one of: a sample of the actual data (CSV/JSON, a handful of rows is enough to infer
types), an exported schema (column names and types from the source system), or a plain-language
description of the fields if neither is available. Don't proceed on assumptions about what the
legacy system contains.

## Step 2: propose the field mapping

One row per source field: source field name/type → target Dataverse table + column name/type.
Call `describe` on the target table (if it already exists) to check for an existing column that
already fits, rather than assuming a new one is needed. Flag explicitly:

- **Type mismatches** — e.g. a free-text status field in the source mapping to a Dataverse
  choice column needs its distinct values enumerated and mapped to specific choice options, not
  silently coerced.
- **Fields with no obvious Dataverse equivalent** — say so rather than inventing a column to put
  them in; ask the user whether to drop the field, add a new column for it, or map it elsewhere.
- **Lookup/relationship fields** — a foreign key in the source system doesn't resolve to a
  meaningful Dataverse record ID. If the related table is also part of this package, resolve it
  through the ID crosswalk above once that table is loaded. If it isn't part of this package,
  match by a natural/alternate key (e.g. an external ID or name) against records that already
  exist in Dataverse — never copy a raw legacy foreign-key value into a lookup column.

Present the full mapping table and get it confirmed before moving to schema or data.

## Step 3: schema changes (separate confirmation from the data load)

If the target table or a mapped column doesn't exist yet, state exactly what you're about to
create before creating it:

- A **new table**: reversible — if it turns out wrong, it can be deleted. Say this.
- A **new column on an existing table**: effectively permanent in practice — removing it back
  out later is its own destructive change. Say this plainly before adding one, especially to a
  table with existing production data.

Use the Dataverse MCP server's `create_table`/`update_table` tools for this, on confirmation —
never invent a parameter shape for these; if uncertain what a tool needs, call `describe` first
or ask the user to confirm the exact schema details rather than guessing.

## Step 3.5: deduplicate and check for existing matches before loading

Legacy exports are often messier than a live Dataverse-to-Dataverse copy — check the provided
data for duplicates on whatever natural/alternate key applies (e.g. an external ID, an email, a
legacy record number) before loading anything, and ask the user which to keep if duplicates are
found. If the target table already has records that might correspond to legacy rows (a second
or later load from the same source), check for matches the same way `record-lift-shift.md` does,
so this can be an upsert (create what's new, update or skip what already exists) rather than
blindly re-creating everything on every run.

## Step 4: staged load

1. **Sample batch first** — 10 to 20 records, loaded via `create_record`. Show the result to the
   user (the created records, as they now look in Dataverse) before going further. This step is
   not optional, regardless of how small the full dataset is.
2. **Full batched load** — only after the sample looks right. Same batching (100–200 records per
   batch), per-record failure isolation, and retry-on-throttling as `pp-data-ops-agent`'s bulk
   mode.
3. **Track every created record's ID** in the running summary — this is the only practical
   rollback path for a bad load (delete by ID), since there's no single "undo this import"
   command.
4. **Final summary**: created (with IDs), skipped (e.g. a row that failed the mapping's
   validation before any write was attempted), failed (with why, during the write itself).

## No-MCP fallback

If the target environment's Dataverse MCP connection isn't available, generate instead of
running: the `create_table`/`update_table` Web API calls for the schema (per the mapping), and a
batched `POST <org-url>/api/data/v9.2/<entityset>` script for the load, built from the data the
user already provided in Step 1 — same staged (sample-first, then full) structure, just handed
over as a script.
