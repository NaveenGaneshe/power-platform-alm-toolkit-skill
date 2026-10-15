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
    └── sync-safety.md            # idempotency keys, sandbox-first testing, backup-before-enable,
                                     reconciliation reporting
```

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
