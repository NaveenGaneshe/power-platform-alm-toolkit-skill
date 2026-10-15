# Power Platform Governance Agent — design

## Purpose

Add a second skill to this repo — a "governance agent" — that complements the
existing `power-platform-alm-toolkit` skill. Where that skill *generates*
ALM code and pipelines for a human to run later, this skill is triggered by
a user's AI tool (Claude Code, Claude Desktop, GitHub Copilot, etc.) and
*executes* live read-only checks (and, on confirmation, fixes) against a
real Dataverse environment, using the environment's connection the user
already has through the Microsoft Dataverse MCP server.

## Why

Microsoft retired the Power Platform CoE Starter Kit in May 2026. Admins
lost their main governance tool. The documented gap, repeated across
vendor write-ups, is specific: the CoE Kit gave *visibility without
actionability* — it could surface an orphaned flow or a drifted role
assignment but couldn't fix it from the same interface — and it required a
dedicated environment and ongoing maintenance to run at all.

Three recurring, well-documented admin pain points map directly onto this
gap and were confirmed via web research (Dynamics Community forums,
GitHub issues, troubleshooting docs):

- Security role assignments drifting between environments, found only when
  someone notices a permission problem in production.
- Connection references breaking on solution import — missing from the
  solution, pointing to a stale connection ID, or blocked by an unmanaged
  layer — a problem repeated often enough that multiple blog posts exist
  walking through the same manual fix.
- Flows failing to turn on (or silently broken) after a solution import,
  requiring an admin to click through every step of every flow by hand.

This skill targets exactly those three, framed as a lightweight,
zero-setup alternative to the piece of the CoE Starter Kit that's gone:
find it *and* fix it, with no dedicated environment.

## Non-goals

- Not a new MCP server. The Microsoft Dataverse MCP server (GA, Dec 2025)
  already provides authenticated, security-role-respecting access to
  Dataverse tables (`read_query`, `describe`, `search`, `update_record`,
  etc.). This skill assumes the user has already connected it for each
  environment they want checked (e.g. `claude mcp add dataverse-dev ...`).
- Not a scheduled/unattended background service. Per user decision, these
  agents are triggered by the user's AI tool on demand, not by a cron job
  or hosted daemon. (A GitHub Actions wrapper that runs the user's AI
  tool headlessly is a possible future extension, out of scope here.)
- Not a dashboard or UI. Output is a Markdown report in the AI tool's
  normal response, matching how the existing skill already replies.

## Architecture

New skill folder, sibling to the existing one:

```
skills/
├── power-platform-alm-toolkit/        # existing — unchanged
└── pp-governance-agent/
    ├── SKILL.md                        # frontmatter + the 4-step workflow below
    ├── LICENSE.txt                     # copy of existing MIT license
    └── references/
        ├── mcp-tool-reference.md       # Dataverse MCP tool catalog: what each
        │                                 tool does, its params, and what it
        │                                 CANNOT do (the gaps this skill fills)
        ├── admin-api-patterns.md       # pac CLI commands for the gaps: flow
        │                                 connection ownership, unmanaged layer
        │                                 detection, environment listing
        └── check-recipes.md            # one recipe per mode: exact queries,
                                          comparison logic, severity rules,
                                          report table format
```

`SKILL.md` frontmatter `description` must cover natural-language phrasings
for all three modes ("audit my security roles", "check connection
references", "health check my environment", "why did my flows break after
import") so the skill triggers regardless of which check the user actually
means — the skill decides the mode(s) internally, the way the existing
skill already scales its response to the request.

Repo root `README.md` gains a short second section introducing this skill
alongside the existing one, repositioning the repo as: *"Skills that write
Power Platform ALM code for you, and an agent that runs live governance
checks for you."*

## The three check modes

All three share one shape: **gather → compare → report → fix-on-confirm.**

### 1. Role drift audit

- **Gather**: for each named environment the user gives (or all configured
  Dataverse MCP connections if they say "across my environments"), run
  `read_query` against `systemuserroles` joined to `systemusers` and
  `roles` (per `references/mcp-tool-reference.md` for exact tool call
  shape).
- **Compare**: diff the user→role mapping between environments. A user
  present in prod but not dev/test (or with a higher-privilege role than
  their counterpart environment) is drift.
- **Report**: Markdown table — user, role, environments where present,
  environments where missing/different, severity (a System Administrator
  role present in prod only is high severity; a minor role gap is
  informational).
- **Fix on confirm**: `POST .../systemuserroles_association/$ref` (via the
  MCP `update_record`-equivalent or documented Web API call) to add the
  missing role assignment — only ever adds, never removes, without a
  second explicit confirmation, since removing access is higher blast
  radius than adding it.

### 2. Connection reference health

- **Gather**: `read_query` on `connectionreferences` for the target
  environment/solution, then `read_query` on `connections` to check each
  reference resolves to a live connection; check for unmanaged layers per
  `references/admin-api-patterns.md` (this part needs `pac solution
  list-unmanaged-layers` or equivalent, since it's not exposed via the
  generic Dataverse MCP tools).
- **Compare**: flag references with no matching connection, a connection
  ID that doesn't exist in this environment (stale from source
  environment), or blocked by an active unmanaged layer.
- **Report**: table — connection reference, flow(s)/app(s) using it,
  problem, proposed fix.
- **Fix on confirm**: point the reference at an existing equivalent
  connection if one exists; otherwise report that a new connection must be
  created manually (creating a connection requires interactive OAuth —
  this skill cannot and should not try to automate that part).

### 3. Post-import flow health

- **Gather**: `read_query` on `workflows` where `category eq 5`
  (cloud flows), filtered to the solution/environment in question;
  for each flow that's off (`statecode = 0`) or whose connection
  references failed, note it.
- **Compare**: cross-reference against mode 2's connection reference
  findings (a flow is often broken *because of* a connection reference
  problem — report the two together rather than as separate issues).
- **Report**: table — flow, current state, root cause (if traceable to a
  connection reference issue, link it), proposed fix.
- **Fix on confirm**: turn the flow on (`PATCH workflows(<id>)` statecode
  update) only after any underlying connection reference problem from
  mode 2 is resolved — never turn on a flow whose connection is still
  broken, since that produces a flow that runs and fails repeatedly
  rather than one that's simply off.

## Error handling

A failure on one environment, one record, or one tool call (permission
denied by the caller's security role, missing MCP server connection for a
named environment, `pac` not authenticated) is reported inline against
that specific item and the run continues — never aborts the whole report.
If the Dataverse MCP server itself isn't connected for a requested
environment, the skill says so explicitly and gives the `claude mcp add
dataverse ...`-style command to fix it, rather than failing silently.

## Safety model

- Every mode is read-only by default. The report is always produced
  first.
- Nothing is written without an explicit, separate confirmation after the
  report — mirrors the existing skill's dry-run-first / type-`APPLY`
  pattern.
- Role additions never also remove existing roles in the same confirmed
  action.
- Flows are never turned on while a known-broken connection reference
  still points at them.
- The skill states, for every proposed fix, the exact Dataverse Web API
  call or `pac` command it will make — no opaque "fixing now."

## Testing / rollout

- Add one eval scenario per mode to `evals/evals.json`, following the
  existing format, checking the skill picks the right mode(s) from varied
  natural-language phrasing and that its proposed report format matches
  the spec above.
- Before publishing or announcing this skill, run all three modes against
  a real (non-production) Dataverse environment with deliberately seeded
  problems (a drifted role, a broken connection reference, an off flow),
  and confirm the report and fix-on-confirm flow both work end to end.
  This is the "prove it works, publicly" demo material for the
  announcement post.
- `scripts/validate.py` and `scripts/check_templates.py` already validate
  any `SKILL.md` + referenced files in the repo; no changes needed to
  those scripts, since the new skill follows the same structure.

## Open questions for later (not blocking this skill)

- Whether to also register successful check recipes as Dataverse
  "skills/playbooks" via the MCP server's `upsert_skill` tool, so
  Copilot Studio agents can reuse them natively — deferred; interesting
  but not required for v1.
- Whether a GitHub Actions headless-trigger wrapper (for the "nightly
  audit" unattended use case raised earlier) gets added later as a
  separate, explicitly-opt-in mode. Out of scope for this spec.
