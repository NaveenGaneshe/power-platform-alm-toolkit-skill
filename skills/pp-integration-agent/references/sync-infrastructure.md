# Sync infrastructure: log, queue, connection metadata

All three tables are optional and independently configurable — ask which the user wants, don't
create all three by default. Schema prefix should match the user's existing Dataverse
customization prefix if they have one; ask if unsure. Confirm the exact `create_table`/
`update_table` calls before running them, same discipline as `pp-migration-agent`'s mode 4.

## Sync log table

One row per sync attempt — the audit trail, and the first place to look when a sync looks wrong.

| Column | Type | Notes |
|---|---|---|
| `<prefix>_entityname` | text | Which object type (e.g. "contact", "order") |
| `<prefix>_direction` | choice | Inbound (external → Dataverse) / Outbound (Dataverse → external) |
| `<prefix>_sourcereference` | text | Source-side ID/key for this attempt |
| `<prefix>_targetreference` | text | Target-side ID/key, once known |
| `<prefix>_idempotencykey` | text | See `sync-safety.md` — must be unique per logical transaction |
| `<prefix>_status` | choice | Success / Failed / Retrying |
| `<prefix>_attemptedon` | datetime | |
| `<prefix>_retrycount` | whole number | |
| `<prefix>_errormessage` | multiline text | Null on success |

## Sync queue table

One row per pending unit of work — exists so a fast trigger can hand work off instead of calling
the external platform inline (see the Power Automate pattern below).

| Column | Type | Notes |
|---|---|---|
| `<prefix>_entityname` | text | |
| `<prefix>_recordreference` | text | The Dataverse record ID or external ID driving this item |
| `<prefix>_operation` | choice | Create / Update / Delete |
| `<prefix>_status` | choice | Pending / Processing / Completed / Failed |
| `<prefix>_nextattemptat` | datetime | For backoff — don't retry before this |
| `<prefix>_retrycount` | whole number | |
| `<prefix>_idempotencykey` | text | Carried through to the log table on completion |
| `<prefix>_payload` | multiline text | Small payloads only; for anything large, reference the source record instead of duplicating its data into the queue row |

## Connection metadata table — never a stored secret

| Column | Type | Notes |
|---|---|---|
| `<prefix>_connectionname` | text | A name the user chooses |
| `<prefix>_platformcategory` | text | e.g. "CRM", "accounting system" — category, never a product name |
| `<prefix>_connectionreferencename` | text | Points to the Power Platform connection reference, or the Key Vault secret name if using a custom connector backed by Key Vault |
| `<prefix>_status` | choice | Active / Expired / Disabled |
| `<prefix>_lastsuccessfulsync` | datetime | |

**Never add a column here for the actual API key, OAuth client secret, or token.** If the user
asks for "auth details" to be stored, clarify explicitly that this table stores a *pointer* to
where the real credential lives (a Power Platform connection, or Azure Key Vault), not the
credential itself — a secret in a plain Dataverse column is readable by anyone with read access
to this table, a much wider exposure than a managed connection or a vaulted secret.

## Retention

Ask whether log rows should be cleaned up after a retention period (e.g. 90 days). If so, this
is a job for `pp-data-ops-agent`'s bulk mode later (`deactivate`/delete rows older than a
date), not something this skill needs to build its own mechanism for.

## The Power Automate pattern for genuinely live sync

This skill generates these flow definitions; it does not run them. Two flows, not one:

1. **Trigger flow** — a Dataverse "row added/modified" trigger (or the external platform's own
   webhook/trigger if its connector offers one) that does only one thing: write a row to the
   sync queue table. Keep this fast and simple so it never times out waiting on the external
   platform's API.
2. **Processing flow** — triggered by new queue rows (or on a schedule, e.g. every few minutes)
   that reads pending rows in batches, calls the connector/custom-connector action, writes the
   result to the sync log, updates the queue row's status, and retries failed rows with backoff
   up to a configured maximum, respecting `<prefix>_nextattemptat`.

This decoupling (trigger hands off fast, processing does the slow/fallible work) is the standard
reason to use a queue table at all rather than one flow doing everything inline — state this
rationale to the user so they understand why there are two flows, not one.
