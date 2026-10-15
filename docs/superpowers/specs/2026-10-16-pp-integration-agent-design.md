# Integration Agent (`pp-integration-agent`) — design

## Purpose

Add a fifth skill, `pp-integration-agent`, that connects Dataverse to widely used external
business platforms — accounting/finance, invoicing, payments, and similar line-of-business SaaS
— without naming any specific platform anywhere in the skill's name, description, references, or
generated output. The user asks about "QuickBooks," "Xero," "MYOB" or similar by name in their
own message; the skill itself always responds in generic terms (the external platform, the
accounting system, the target API) and never echoes a specific vendor name into committed files.

## Why

Verified against the Microsoft connector reference (`learn.microsoft.com/connectors/connector-reference/`)
rather than assumed: connector coverage for accounting/finance platforms is **patchy and
third-party**, not a clean, uniform "Microsoft supports this" story:

- Some accounting-adjacent platforms have a non-Microsoft-published connector in the gallery
  (built by a third-party ISV, often Preview tier, sometimes Premium-licensed).
- Others have no suitable connector at all, or only a narrow one (e.g. time-tracking, not full
  invoicing/payments).
- There is no `pac` command or Dataverse MCP tool that searches the global connector gallery —
  checking what's available for a specific platform is a manual step in the Power Apps maker
  portal (**Data → Connections → New connection → search**), not something this skill can verify
  live. Say so rather than pretending to check automatically.

Because of that, this skill can't assume a certified connector exists. Its real, reliable value
is the same custom-connector pattern already verified and documented in
`power-platform-alm-toolkit`'s `references/dataverse-patterns.md` (§9: OpenAPI 2.0
`apiDefinition.swagger.json` + `apiProperties.json`, OAuth2, `pac connector create`) — written
generically here as its own self-contained reference so this skill works standalone — plus the
mapping, sync-flow, and financial-data safety discipline that custom connector alone doesn't
give you.

## Non-goals

- **Never name a specific commercial platform** in this skill's `SKILL.md`, references, eval
  scenarios, or any generated code/output. Refer to "the external platform," "the accounting
  system," "the target API." If the user names one in their own request, respond in kind without
  echoing the brand name into anything written to disk.
- **No live, ongoing sync execution.** A recurring sync runs inside a Power Automate flow once
  built, not inside this chat session. This skill designs, generates, and (on confirmation) helps
  validate that flow — it does not become the thing that runs it on a schedule.
- **No connector-gallery search tool.** This skill cannot verify live whether a certified
  connector exists for a named platform; it says so and tells the user where to check manually.
- **No direct financial write without idempotency protection and explicit confirmation** — see
  Safety model.

## Architecture

```
skills/pp-integration-agent/
├── SKILL.md
├── LICENSE.txt
└── references/
    ├── connector-options.md      # certified-connector-vs-custom-connector decision guide,
    │                                self-contained custom connector pattern (OpenAPI 2.0, OAuth2)
    ├── entity-mapping.md         # generic accounting-object mapping (customer, invoice, payment,
    │                                item) + transformations, reusing record-lift-shift.md's
    │                                dependency-order/crosswalk approach for related objects
    ├── sync-infrastructure.md    # configurable Dataverse log/queue/connection-metadata tables,
    │                                the Power Automate producer/consumer pattern for live sync
    └── sync-safety.md            # idempotency keys, sandbox-first testing, backup-before-enable,
                                     reconciliation reporting, and the Azure-resource upgrade path
```

## Sync infrastructure: log, queue, and connection metadata tables (in Dataverse, configurable)

Per follow-up requirement: this skill creates (on confirmation) the supporting Dataverse tables
a sync needs, not just the mapping. Three tables, each optional and independently configurable
(the user may want only the log, or all three):

- **Sync log** — one row per sync attempt: entity, direction, source/target record reference,
  idempotency key, status, timestamp, retry count, error message. This is the audit trail and
  the first thing to check when a sync looks wrong.
- **Sync queue** — one row per pending unit of work: entity, record reference, operation,
  status (pending/processing/completed/failed), next-attempt time, retry count, idempotency key.
  Exists so a fast Dataverse trigger can hand work off instead of doing the external call inline
  (see the Power Automate pattern below).
- **Connection metadata** — **never the secret itself.** A pointer/health table only: connection
  name, a generic platform label the user chooses, which Power Platform connection or Key Vault
  secret it refers to, status, last successful sync time. The actual OAuth token/API key lives in
  the Power Platform connection (managed by whichever connector is in use) or Azure Key Vault —
  never in a Dataverse column. State this as a hard safety rule, not a preference: a plaintext
  secret in a Dataverse column is readable by anyone with table access, which is a much wider
  blast radius than a managed connection or a vaulted secret.

Schema prefix, which of the three tables to create, and retention (e.g. auto-cleanup of log rows
past N days, which `pp-data-ops-agent`'s bulk mode can help execute later) are all asked, not
assumed.

## Recommending Power Automate for genuinely live/continuous sync

This skill designs and can create the Dataverse side, but it does not run a continuous sync
itself (see Non-goals). When the user wants near-real-time sync rather than a one-time or
scheduled batch load, recommend the standard decoupled pattern rather than one flow doing
everything inline:

1. A **trigger flow** (Dataverse "row added/modified" trigger) that only writes a row to the
   sync queue table — fast, so it never times out waiting on an external API.
2. A **processing flow** (queue-triggered or scheduled) that reads pending queue rows in
   batches, calls the connector/custom-connector action, writes the result to the sync log,
   updates the queue row's status, and retries failed rows with backoff up to a configured limit.

State this as the recommended architecture, generated as flow definitions for the user to
import and review — not run from this chat session.

## When to suggest Azure resources instead of (or alongside) the Dataverse+Power Automate approach

Only as an upgrade path, not a default — the Dataverse-table-plus-Power-Automate design above is
right for most low/medium-volume syncs. Suggest Azure resources when the user describes a volume,
durability, or ordering need the Dataverse queue table and Power Automate's native retry won't
comfortably handle:

- **Azure Key Vault** — if the custom-connector pattern needs its own managed secret rather than
  relying on a Power Platform connection's built-in credential storage.
- **Azure Service Bus** (queue or topic) — in place of the Dataverse queue table, when volume,
  strict ordering, or dead-lettering semantics matter more than a Dataverse table can offer.
- **Azure Functions** — for retry/backoff or transformation logic more complex than Power
  Automate's expression language handles comfortably, called from a flow via an HTTP action.
- **Application Insights** — for centralized monitoring/alerting across many sync runs, beyond
  what querying the Dataverse sync log table gives you.

Present these as a named option with a one-line reason each, not an assumed requirement — most
users asking for "sync my data with my accounting platform" want the simpler path.

## The shape (one coherent flow, not separate "modes")

1. **Scope the integration.** What external platform (described generically in all output), what
   objects (customers, invoices, payments, products — ask, don't assume all of them), one-way or
   two-way sync, one-time load or ongoing.
2. **Check for an existing connector, but honestly.** Ask the user to check the maker portal's
   connector gallery for their platform (give the exact navigation path); this skill can't check
   automatically. If one exists and covers what's needed, prefer it over building a custom
   connector. If not, or if it doesn't cover a needed object/action, build a custom connector
   using the verified pattern in `references/connector-options.md`.
3. **Map the objects**, using the same dependency-order + ID-crosswalk approach as
   `pp-migration-agent`'s multi-entity packages (a customer must exist before an invoice that
   references it, on both sides), plus accounting-specific transformations: currency and
   rounding rules, tax-code mapping, and date/fiscal-period handling — state the exact rule for
   each, don't apply a silent default on financial data.
4. **Design the sync mechanism**: a Power Automate flow (trigger + the connector's actions, or
   the custom connector's operations), generated as a file for the user to import and review, not
   run from this chat session.
5. **Validate before going live.** Recommend testing against the platform's own sandbox/demo
   environment if it has one (generic: "check whether your platform offers a test/demo company"),
   load a small sample first, and require a separate, explicit confirmation to move from
   "designed and sample-tested" to "enabled for real financial data" — these are different blast
   radii and must not be the same confirmation.
6. **Every write carries an idempotency key** (a stored external-ID / correlation field on both
   sides) so a retried sync run creates a transaction once, not twice — this is the single most
   important safety property for financial data and is not optional.

## Safety model

- Treat every write to a financial system the same way `pp-migration-agent` treats a destructive
  step: state the backup/rollback or reconciliation path before it runs, not after.
- Idempotency keys are mandatory for any create/update against the external platform or
  Dataverse that this skill helps design — a duplicated invoice or payment is a real-world
  financial error, not a cosmetic one.
- "Designed and sample-tested" and "enabled against real production financial data" are always
  two separate, explicit confirmations.
- Recommend a reconciliation report after any load/sync (counts matched on both sides, by the
  idempotency key) rather than assuming success from an API 200 response alone.
- Never invent a connector action, custom-connector parameter, or API shape not confirmed by the
  user's own description of their platform's API, or by a documented pattern in the references.
- Never write a specific platform's name into any generated file, reference, or eval scenario.

## Testing / rollout

- Add `evals/pp-integration-agent.evals.json` with scenarios phrased generically (e.g. "connect
  our Dataverse accounts to our accounting platform's customer records") plus one scenario where
  the user names a real platform in their prompt, checking the expected output still responds
  generically and doesn't echo the brand name into any proposed file.
- README gets a fifth row in "Skills in this repo," described generically, consistent with every
  other entry's format.
