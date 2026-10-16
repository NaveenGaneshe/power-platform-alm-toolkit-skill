# User guide: getting the most out of these skills

This repo ships five Agent Skills. One generates code for you to commit and run later. Four act
live, right now, in the conversation (or generate a ready-to-run equivalent if they can't act
live yet). This guide is about how to talk to them so you get a good result on the first try —
install instructions are in the [README](../README.md#installation); the full prompt library is
in [`examples/prompts.md`](../examples/prompts.md).

## The one-paragraph mental model

You never need to name a skill — each one triggers on the shape of your request. Say what you
want in plain language, the way you'd ask a colleague. If a skill needs something it doesn't
have (a live connection, a missing detail, explicit permission to write), it tells you exactly
what and why, rather than guessing or quietly failing.

| If your request is about... | You'll get... |
|---|---|
| Building a pipeline, a bulk-update script, a data dictionary, a custom connector | **Generated files** from `power-platform-alm-toolkit` — code + pipeline + runbook, ready to commit. |
| A question or a bulk change to Dataverse records, right now | **A live answer** from `pp-data-ops-agent`, or a ready-to-run query/script if you don't have the Dataverse MCP server connected. |
| Security roles, connection references, or flows that look broken | **A live audit** from `pp-governance-agent`, with fixes proposed and applied only on your confirmation. |
| Copying an environment, moving to a new tenant, or moving specific records/data | **A guided move** from `pp-migration-agent`, with the overwrite/backup/rollback path stated before anything runs. |
| Connecting Dataverse to a CRM, accounting system, or other external platform | **A mapped-out integration** from `pp-integration-agent`, with idempotent writes and no product names in anything it generates. |

## How to get a good result on the first ask

These apply across all five skills:

1. **Say the scale and the risk.** "10 records in dev" and "2 million records in production"
   produce very different plans. If you don't say, the skill will ask rather than guess wrong.
2. **Name your environments** if they're not literally called dev/test/production — and say who
   needs to approve production changes, if anyone.
3. **Say what "done" looks like for a check.** "Audit roles" is vaguer than "flag anyone with
   System Administrator in prod who doesn't have it in dev." The more specific the finding you
   want, the more specific the report.
4. **Ask for just the piece you need.** "Only the runbook," "just the pipeline," "just check,
   don't fix anything yet" — every skill scales its answer down to that, rather than always
   producing the full output.
5. **Expect a report before a write, every time.** None of the live agents write anything
   without showing you what's about to change first — if one proposes several fixes, you can
   confirm them one at a time rather than all at once.
6. **If you don't have the Dataverse MCP server connected**, you don't need to set it up before
   trying an agent — ask anyway. `pp-data-ops-agent`, `pp-governance-agent`,
   `pp-migration-agent`'s record/legacy modes, and `pp-integration-agent` will all generate the
   equivalent query, script, or runbook for you to run yourself instead of refusing. Connecting
   it (see [Installation](../README.md#installation)) gets you a live answer instead of a
   generated one next time.

## Per-skill notes

### `power-platform-alm-toolkit` (generates code)

- Ask for a module the way you'd describe the problem to a colleague: what needs to happen, how
  big, how risky. You'll get the four-part blueprint (capability mapping → code/schemas →
  repo/pipeline → runbooks) scaled to how much you asked for.
- "Let it write files" — in Claude Code, Codex, Copilot agent mode, or Cursor, ask it to create
  the files directly in your toolkit repo rather than pasting them yourself.

### `pp-data-ops-agent` (live queries and bulk changes)

- Good: "How many contacts have no email address?" Better, for a bulk change: "deactivate every
  case open over 90 days, show me a preview first." The agent always previews a bulk change
  before asking you to confirm it.
- A delete gets its own, separate confirmation from everything else in the plan — if you want a
  delete, say so explicitly rather than assuming "yes" covers it.

### `pp-governance-agent` (security role / connection reference / flow health)

- Works equally well as a targeted question ("why won't my flows turn on after the import?") or
  a broad one ("health check my environment") — the broad version runs all three checks.
- For a cross-environment check ("compare roles between dev and prod"), make sure you have an
  MCP connection for *each* environment named, or the agent will tell you exactly which one it's
  missing rather than silently checking only the one it can reach.

### `pp-migration-agent` (environment copy, tenant migration, record/legacy data moves)

- Four different blast radii live under one skill — be specific about which one you mean: "copy
  this environment" (same tenant) vs. "move to a new tenant" vs. "move just these records" vs.
  "load this data from our old system." If it's ambiguous, the agent asks rather than guessing.
- For a multi-entity move ("these accounts, their contacts, and their open opportunities"), say
  the relationship explicitly — that's what triggers the dependency-ordered, relationship-aware
  package path instead of three separate, disconnected moves.
- Every environment-level or data-moving step states a backup/rollback plan before it runs. If
  you're not sure the target is disposable, ask the agent to check first rather than assuming.

### `pp-integration-agent` (external platform connectors and sync)

- You can name the actual platform in your request ("connect to our CRM," "sync invoices to our
  accounting system") — the agent will never write that name into anything it generates, but it
  still understands what you mean.
- If you want this running continuously, say so — the agent will design the trigger/queue/
  processing Power Automate pattern for that, rather than a one-time load, and will tell you it
  can't run an ongoing sync from the chat session itself.
- If you expect high volume, say the rough number — that's what decides whether the agent
  suggests Azure resources (Key Vault, Service Bus, Functions) as an upgrade, instead of
  defaulting to them when a simpler setup would do.

## If something feels off

Every agent's self-check includes "did I say what I was about to do before doing it, and wait
for confirmation on anything that writes." If an agent seems to have skipped that, that's a bug
worth reporting — see [Contributing, security and license](../README.md#contributing-security-and-license)
in the README.
