# Entity mapping

Never name a specific commercial platform here — describe objects generically (contact/customer,
deal/order, invoice/payment, ticket, product), by category when it matters.

## Common object categories by platform type

Ask which objects are actually in scope — don't assume every category applies:

| Platform category | Typical objects | Typical Dataverse counterpart |
|---|---|---|
| CRM | contact, company/account, deal/opportunity, activity | `contact`, `account`, `opportunity` |
| Accounting/finance | customer, invoice, payment, item/product, tax code | `account`/`contact`, a custom invoice table, `product` |
| E-commerce | customer, order, line item, product, inventory level | `contact`/`account`, custom order/order-line tables |
| Marketing | contact/subscriber, campaign, list/segment | `contact`, `list` (Dataverse marketing list), `campaign` |
| Support/ticketing | contact, ticket/case, conversation | `contact`, `incident` |

These are starting points, not a fixed schema — confirm the actual fields with the user and (for
the Dataverse side) `describe`, never assume a column exists unchecked.

## Dependency order and the ID crosswalk (same approach as `pp-migration-agent`)

Any object that references another in-scope object (an order referencing a customer, a ticket
referencing a contact) must be mapped *after* the object it references, using one ID crosswalk
carried across the whole integration: `(object type, external-platform ID, Dataverse record ID)`.
When mapping a reference field, resolve it through the crosswalk — never copy the external
platform's raw ID into a Dataverse lookup column, and never copy a Dataverse GUID into the
external platform's reference field as-is; translate through the crosswalk both directions.

If the external platform's own API already returns its records with foreign keys resolved by a
natural key (e.g. an email address, an external reference number) rather than its own internal
ID, prefer matching on that over the crosswalk when it's available and reliable — ask the user
which identifier is stable on their platform before deciding.

## Transformations — state the rule, don't apply a silent default

- **Currency and rounding**: if currencies differ or the platforms round differently (2 decimal
  places vs. 4, banker's rounding vs. standard), state the exact rule being applied and get it
  confirmed. This is financial-correctness-sensitive even outside pure accounting platforms
  (e-commerce order totals, CRM deal values).
- **Status/stage mapping**: a CRM's deal stage, a support ticket's status, or an order's
  fulfillment state almost never maps one-to-one between two platforms. Enumerate the distinct
  source values and get the target mapping confirmed explicitly, the same way
  `pp-migration-agent`'s legacy-load recipe handles free-text status fields.
- **Date/fiscal period handling**: confirm time zone and fiscal-year-start assumptions before
  mapping any date that drives a report or a financial period, rather than assuming calendar-year
  semantics.
- **Fields with no equivalent on the other side**: say so, and ask whether to drop the field, add
  a new column/custom field for it, or map it elsewhere — never invent a destination for it.

## Many-to-many and cross-references

If the external platform models a many-to-many relationship (e.g. a contact belonging to
multiple segments, a product appearing on multiple orders), handle it last, once both sides it
connects are already mapped and present at the target — resolving both ends through the
crosswalk, same as `pp-migration-agent`'s N:N handling.
