# Connector options

Never name a specific commercial platform in anything written here or generated from this file
— write "the external platform" or name the category (CRM, accounting system, e-commerce
platform, marketing tool, support/ticketing system), never the product.

## Checking for an existing connector (manual, not automatable from here)

There is no `pac` command or Dataverse MCP tool that searches the Power Platform connector
gallery. Tell the user to check themselves: **Power Apps (make.powerapps.com) → Data →
Connections → New connection**, then search for their platform's name. Connector coverage
across CRM, accounting, e-commerce, and marketing platforms is inconsistent — some have a
certified or third-party-published connector (sometimes Preview tier, sometimes requiring
Premium licensing), others have none, or only a narrow one (e.g. a connector that covers
contacts but not orders). Don't assume either way; ask the user to confirm what they found.

If a connector exists and covers the objects in scope, prefer it — skip the custom connector
work below entirely.

## Building a custom connector (when no suitable connector exists)

This is the same verified pattern `power-platform-alm-toolkit` documents, repeated here
self-contained so this skill works standalone. Three files, in
`modules/<module>/connector/` if following that skill's repo layout, or wherever the user's
project keeps connectors:

- **`apiDefinition.swagger.json`** — OpenAPI **2.0** (not 3.x) describing the external
  platform's REST endpoints you need (e.g. "get customers," "create invoice/order," "update
  ticket status"). Include `x-ms-summary` and `description` on every parameter so Power
  Automate/Power Apps makers see friendly labels, and `x-ms-visibility`
  (`important`/`advanced`/`internal`) to keep the action list usable.
- **`apiProperties.json`** — `properties.connectionParameters` (most business SaaS platforms
  use OAuth2 — set `identityProvider` per the platform's actual auth flow, never guess at a
  different one; some older or simpler APIs use a static API key instead, in which case use
  an `apiKey` connection parameter type, never embed the key in the swagger file itself),
  `iconBrandColor`, optional `scriptOperations` for request/response transformation the
  OpenAPI spec can't express.
- **`icon.png`** (optional), **`script.csx`** (optional C# request/response transform).

Deploy: `pac connector create --api-definition-file <path> --api-properties-file <path>
--solution-unique-name <SOLUTION> --environment <url>`. Update an existing one with
`pac connector update --connector-id <id> ...`. Once in a solution, it travels via normal
solution export/import, same as any other component.

Never invent an endpoint path, parameter name, or auth flow for the external platform — ask the
user for its API documentation if you don't already have enough from what they've described,
and build the swagger definition from that, not from assumption.

## Rate limits and retries

Most external business platforms enforce their own API rate limits, independent of Dataverse's
service protection limits. Ask the user for their platform's documented limits if the sync
volume is non-trivial, and apply the same retry-with-backoff discipline `pp-data-ops-agent` uses
for Dataverse throttling — on the external platform's side this time, not Dataverse's.
