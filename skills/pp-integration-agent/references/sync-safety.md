# Sync safety: idempotency, validation, reconciliation, and the Azure upgrade path

## Idempotency keys — mandatory, not optional

Every write this skill designs or performs carries an idempotency key: a stored external-ID or
correlation field present on both the Dataverse record and the external platform's record,
generated once per logical transaction and reused on every retry of that same transaction.
Without one, a retried sync (after a timeout, a throttling error, or a flow re-run) can create
the same order, invoice, contact, or ticket twice. Before designing any write path, confirm:

- Where the key is generated (usually Dataverse, since it's the system initiating most syncs).
- Where it's stored on both sides (a dedicated column on the Dataverse table, and whichever
  field the external platform's API uses for idempotent request handling — ask the user to check
  their platform's API docs for this, since conventions vary and this skill can't guess).

**Storing a key on your own side does nothing by itself — something has to enforce uniqueness
with it.** There are exactly two ways that happens, and the hardest case to design for is not "a
retry before anything happened," it's: the write actually commits on the external platform, but
the response is lost (timeout, dropped connection, a crash between the write and the
acknowledgement) before the processing flow learns it succeeded. From the retrying side, a
committed-but-unacknowledged write is indistinguishable from one that never happened — so the
retry *will* be attempted, and the only question is what stops it from creating a duplicate:

1. **The external platform's write API natively supports idempotent requests** (commonly an
   `Idempotency-Key`-style request header or field it documents itself) — if so, send the same
   key on every retry and trust the platform to return the original record instead of creating a
   second one. Confirm this is actually documented before relying on it; don't assume it.
2. **No native support — fall back to a pre-write existence check.** Before every write attempt,
   including retries, query the external platform (or Dataverse, for an inbound sync) for an
   existing record matching the idempotency key, and skip the write if one is found. This turns
   "write, maybe twice" into "check, then write," which is safe under retries as long as the
   check itself is reliable — call out explicitly that this doesn't protect against two
   *concurrent* retries racing each other (the processing-flow design in
   `sync-infrastructure.md` processes one queue row at a time specifically to avoid that).

Decide and state which of these two applies before calling the write safe — "it has an
idempotency key" is not itself an answer to "what happens on a lost-ack retry."

When mechanism 2 applies and the generated output is a PowerShell script, copy
`assets/IdempotentSync.psm1`'s `Invoke-IdempotentWrite` pattern (check, then create) rather than
writing the check-then-write logic from scratch — it's the same pre-write existence check
described above, already verified against the lost-acknowledgement scenario in
`tests/IdempotentSync.Tests.ps1`.
- That a retry re-sends the same key rather than generating a new one.

## Sandbox-first validation

Many external business platforms offer a test/demo/sandbox account or company, separate from
production data. Ask whether the user's platform has one, and recommend validating the full
mapping and sync flow there first — same "test migration first" discipline `pp-migration-agent`
applies to environment moves, applied here to external-platform writes instead.

## Staged rollout: sample-tested vs. live, always separate confirmations

1. Design the mapping and connector/flow.
2. Load or sync a small sample (a handful of records) and show the user the result on both
   sides.
3. **Stop.** Get an explicit, separate confirmation specifically to move from "sample-tested" to
   "enabled against real, live data" — this is never the same confirmation as approving the
   design or the sample.

## Reconciliation, not just a success response

An HTTP 200 from the external platform's API doesn't guarantee the record is correct, or that
nothing silently failed downstream in the external platform's own processing. After any
load/sync batch, recommend a reconciliation pass: compare counts (and, for a sample of records,
field values) on both sides using the idempotency key, and report any mismatch explicitly rather
than treating "the API call succeeded" as the end of verification.

## When to suggest Azure resources instead of (or alongside) the Dataverse + Power Automate default

Only as an upgrade path — most syncs are fine with the Dataverse-table-plus-Power-Automate design
in `sync-infrastructure.md`. Suggest these only when the user describes a volume, durability, or
ordering need that design won't comfortably handle, each with the one-line reason it solves:

| Azure resource | Suggest when |
|---|---|
| **Key Vault** | The custom-connector pattern needs its own managed secret rather than relying on a Power Platform connection's built-in credential storage. |
| **Service Bus** (queue/topic) | Volume, strict ordering, or dead-lettering semantics matter more than a Dataverse queue table and Power Automate's native retry can offer. |
| **Functions** | Retry/backoff or transformation logic is more complex than Power Automate's expression language handles comfortably — called from a flow via an HTTP action. |
| **Application Insights** | Centralized monitoring/alerting across many sync runs is needed, beyond what querying the Dataverse sync log table gives. |

Present this as a named option with its reason, not an assumed requirement for every
integration — over-building infrastructure for a low-volume sync is its own kind of mistake.
