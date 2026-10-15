# PP Governance Agent Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a second Agent Skill, `pp-governance-agent`, that uses the Microsoft Dataverse MCP server (which the user already has connected in their AI tool) to run three live, read-first governance checks — security role drift, connection reference health, and post-import flow health — and proposes fixes that only execute on explicit confirmation.

**Architecture:** Pure content addition — one new skill folder (`SKILL.md` + three `references/*.md` files + `LICENSE.txt`), one new eval file, and a README update. No new runtime, server, or script. One existing script (`scripts/build.py`) has a pre-existing bug that must be fixed first: its portable-bundle instructions are hardcoded to the first skill's product description and would ship wrong instructions once a second skill exists.

**Tech Stack:** Markdown (Agent Skills format), Python 3 (existing `scripts/validate.py`, `scripts/check_templates.py`, `scripts/build.py`), Dataverse SQL (TDS endpoint, read-only `SELECT`) via the Dataverse MCP server's `read_query`/`describe` tools, `pac` CLI for the few gaps MCP doesn't cover.

**Spec:** `docs/superpowers/specs/2026-10-15-pp-governance-agent-design.md`

## Global Constraints

- Every mutating operation proposed by the skill must be read-only by default and require an explicit, separate confirmation before it writes anything (spec: Safety model).
- Never invent a `pac` CLI flag, Dataverse SQL table/column name, or Web API call that isn't verified — when uncertain, the skill must tell the agent to call `describe` first rather than assume a schema (spec: Architecture, "verify, don't invent" ethos already established by the sibling skill).
- A failure on one environment, record, or tool call must be reported inline and must not abort the rest of the run (spec: Error handling).
- `SKILL.md` frontmatter must pass `scripts/validate.py`: name matches folder, description 1–1024 chars with no angle brackets, body under 500 lines (detail goes in `references/`).
- Every fenced `yaml`/`yml`/`json` code block anywhere under `skills/` must parse cleanly under `scripts/check_templates.py`.
- No role-assignment fix may also remove an existing role assignment in the same confirmed action (spec: Safety model — additions and removals need separate confirmations).
- A flow must never be turned back on while a connection reference it depends on is still known-broken (spec: mode 3 fix rule).

## Review Focus

- **Dataverse MCP server not connected for a requested environment.** The skill must say so explicitly and give the exact `claude mcp add ...`-style fix command, not fail silently or guess at a URL.
- **User asks for a cross-environment check without having configured an MCP connection for every named environment.** The skill must list which environments it could and couldn't reach, not silently check only one and report it as complete.
- **A "fix" is proposed for a problem the skill cannot actually fix via available tools** (e.g., an active unmanaged layer — there is no verified `pac` or Web API command for this). The skill must say the specific manual step needed (maker portal path) instead of fabricating an automated fix.
- **User says something ambiguous like "apply it" after multiple proposed fixes were listed across different modes.** The skill must confirm which specific fix(es) are being applied rather than applying all proposed writes.
- **A role-drift or connection-reference query returns zero rows** (e.g., a brand-new environment with no roles assigned yet, or a solution with no connection references). The skill must report "no drift/issues found" distinctly from a tool-call failure, not conflate an empty result with an error.

---

### Task 1: Fix `scripts/build.py` portable-instructions bug before adding a second skill

**Files:**
- Modify: `scripts/build.py:88-101` (the `build_portable` function's hardcoded instructions string)
- Test: manual run of `python3 scripts/build.py`, inspecting `dist/portable/*.instructions.md`

**Interfaces:**
- Consumes: `fm` — nothing new; this task adds frontmatter parsing to `build_portable` using the same `parse_frontmatter(text) -> tuple[dict, str]` function already defined in `scripts/validate.py`.
- Produces: `build_portable(skill: Path) -> tuple[Path, Path]` — same signature, but the instructions file content is now derived from `skill`'s own frontmatter (`name`, `description`) instead of a hardcoded "Elite Enterprise Cloud Architect... four-part blueprint" paragraph, so it stays correct for every skill in `skills/`, not just the first one.

Today `build_portable` writes identical, ALM-toolkit-specific prose into every skill's `*.instructions.md` file. Once `pp-governance-agent` exists, running `scripts/build.py` would ship that skill with instructions describing a "four-part blueprint" it doesn't have. Fix this first so later tasks' validation runs produce correct output.

- [ ] **Step 1: Write a manual regression check for current (broken) behavior**

Run the existing build to see today's output for the existing skill, so you have a baseline to compare after the fix:

```bash
python3 scripts/build.py
cat dist/portable/power-platform-alm-toolkit.instructions.md
```

Expected: the instructions mention "four-part blueprint" — confirm this text is present (it's the thing we're about to make generic).

- [ ] **Step 2: Import frontmatter parsing into build.py and rewrite the instructions template**

In `scripts/build.py`, add the import and rewrite `build_portable` so the instructions come from the skill's own frontmatter rather than hardcoded prose:

```python
sys.path.insert(0, str(Path(__file__).resolve().parent))
from validate import parse_frontmatter  # noqa: E402
```

Place that near the top of the file, after the existing imports (after line 23, before `ROOT = ...`).

Replace the body of `build_portable` (the `instructions = f"""..."""` block, lines ~88-101) with:

```python
def build_portable(skill: Path) -> tuple[Path, Path]:
    portable = DIST / "portable"
    portable.mkdir(parents=True, exist_ok=True)
    skill_md_text = (skill / "SKILL.md").read_text(encoding="utf-8")
    fm, _ = parse_frontmatter(skill_md_text)
    parts = [
        f"<!-- Portable bundle of the '{skill.name}' Agent Skill. Generated by scripts/build.py; do not edit by hand. -->",
        "",
        "# How to use this file",
        "",
        "This single file contains a complete skill: the main instructions (SKILL.md) followed by every",
        "supporting file. Wherever the instructions mention a path such as `references/tooling.md` or",
        "`assets/Dataverse.psm1`, use the section with that path as its heading further down this file.",
        "",
        "---",
        "",
        "## File: SKILL.md",
        "",
        skill_md_text.strip(),
        "",
    ]
    for f in files_of(skill):
        rel = f.relative_to(skill).as_posix()
        if rel == "SKILL.md" or f.suffix.lower() not in TEXT_SUFFIXES:
            continue
        text = f.read_text(encoding="utf-8")
        parts += ["---", "", f"## File: {rel}", ""]
        if f.suffix.lower() == ".md":
            parts.append(text.strip())
        else:
            fence = fence_for(text)
            parts += [f"{fence}{FENCE_LANG.get(f.suffix.lower(), '')}", text.rstrip(), fence]
        parts.append("")
    bundle = portable / f"{skill.name}.md"
    bundle.write_text("\n".join(parts), encoding="utf-8")

    instructions = f"""You are following a packaged AI Agent Skill named "{fm.get('name', skill.name)}".

{fm.get('description', '')}

Your knowledge files include `{skill.name}.md`. It is this skill's complete operating manual: its main
instructions (the "File: SKILL.md" section), followed by its reference files and assets, each under a
"File: <path>" heading.

1. Read the "File: SKILL.md" section of `{skill.name}.md` first and follow it exactly, including its
   stated workflow and self-check.
2. When it points to a path such as `references/tooling.md` or `assets/Dataverse.psm1`, open the section
   headed "File: <that path>" in the same knowledge file before acting on it. Use the exact names,
   parameters, commands and query shapes given there; never invent one that isn't written down.
3. Follow any safety rules stated in the skill exactly (for example: read-only by default, confirm before
   writing, never put secrets or environment URLs directly in code).

If the knowledge file is unavailable, say so and ask the user to upload `{skill.name}.md` rather than
improvising.
"""
    if len(instructions) > INSTRUCTIONS_LIMIT:
        raise SystemExit(f"instructions for {skill.name} exceed {INSTRUCTIONS_LIMIT} characters")
    instr = portable / f"{skill.name}.instructions.md"
    instr.write_text(instructions, encoding="utf-8")
    return bundle, instr
```

- [ ] **Step 3: Run the build again and verify the fix**

```bash
python3 scripts/build.py
cat dist/portable/power-platform-alm-toolkit.instructions.md
```

Expected: the instructions now read generically ("You are following a packaged AI Agent Skill named...") and include the actual `description` text from that skill's frontmatter, with no hardcoded "four-part blueprint" prose. The build must still exit 0.

- [ ] **Step 4: Commit**

```bash
git add scripts/build.py
git commit -m "fix: generate portable skill instructions from frontmatter, not hardcoded prose

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 2: Scaffold the `pp-governance-agent` skill folder and `SKILL.md`

**Files:**
- Create: `skills/pp-governance-agent/SKILL.md`
- Create: `skills/pp-governance-agent/LICENSE.txt`
- Test: `python3 scripts/validate.py skills` (frontmatter/name/description checks)

**Interfaces:**
- Produces: the skill's public contract — its `name` (`pp-governance-agent`), its `description` (the trigger text every later task's eval scenarios target), and the three named modes (`role-drift`, `connection-reference-health`, `post-import-flow-health`) that `references/check-recipes.md` (Task 5) implements in detail. `SKILL.md` only states the workflow shape and defers all query/command detail to `references/`.

- [ ] **Step 1: Create the folder and copy the license**

```bash
mkdir -p skills/pp-governance-agent/references
cp skills/power-platform-alm-toolkit/LICENSE.txt skills/pp-governance-agent/LICENSE.txt
```

- [ ] **Step 2: Write `SKILL.md`**

```markdown
---
name: pp-governance-agent
description: Runs live, read-first governance checks against a Microsoft Dataverse environment using the Dataverse MCP server the user already has connected in their AI tool (Claude Code, Claude Desktop, GitHub Copilot, Copilot Studio): security role drift between environments, broken or stale connection references, and flows that failed to turn on after a solution import. Always reports before it writes, and only writes after explicit confirmation. Use whenever the user asks to audit, check, diagnose or health-check security roles, user access, connection references, flows, or an environment's overall health, including after a solution import, before or after a release, or as a lightweight alternative to the retired Power Platform CoE Starter Kit.
license: MIT (see LICENSE.txt)
compatibility: Requires the Microsoft Dataverse MCP server connected for each environment to check (for example `claude mcp add dataverse-dev -t stdio -- npx -y @microsoft/dataverse mcp https://yourorg-dev.crm.dynamics.com`, repeated per environment, or the equivalent in GitHub Copilot / Copilot Studio). Fix actions that fall outside the Dataverse MCP tool set use the Power Platform CLI (`pac`); PAC CLI auth must already be set up for those. Web lookups are optional.
metadata:
  version: "0.1.0"
  category: "power-platform-governance"
---

# Power Platform Governance Agent

You are acting as a Power Platform governance agent. You run live checks against real Dataverse environments — through the Dataverse MCP server tools already available to you — and report what's wrong before you ever change anything. You are not generating code for someone else to run later: you are running the check yourself, right now, in this conversation.

## Before you start

Confirm the Dataverse MCP server is connected for every environment the user wants checked. If a named environment has no MCP connection available to you, say so explicitly and give the exact command to add it, for example:

```
claude mcp add dataverse-dev -t stdio -- npx -y @microsoft/dataverse mcp https://yourorg-dev.crm.dynamics.com
```

Never guess at an environment URL or silently skip an environment — list which ones you could and couldn't reach.

## Workflow

1. **Pick the mode(s).** From the user's request, decide which of the three checks in `references/check-recipes.md` apply: role drift, connection reference health, or post-import flow health. A vague request ("health check my environment") runs all three against the environment(s) named. A specific request ("why won't my flows turn on") runs only the relevant mode(s), but still check mode 2 first if mode 3 is requested, since a broken flow is often caused by a broken connection reference (see `references/check-recipes.md`, mode 3).
2. **Gather.** Call `describe` first to confirm table/column names actually exist in this environment before writing a `read_query`, then run the exact query shapes in `references/check-recipes.md` for the chosen mode(s). For anything the Dataverse MCP tools don't expose (see `references/mcp-tool-reference.md` for the full tool catalog and its gaps), use the `pac` commands in `references/admin-api-patterns.md` — never invent a flag or table name that isn't written down in one of these two files.
3. **Compare and report.** Build the Markdown table specified for that mode in `references/check-recipes.md`: what's wrong, severity, and the proposed fix in plain language. If a mode finds nothing wrong, report that explicitly ("no drift found" / "no broken references found") rather than staying silent — silence reads as "I didn't check."
4. **Stop. Do not write anything yet.** Always finish the report before proposing to fix anything.
5. **Fix only on explicit confirmation**, and only the specific fix(es) the user confirms — if multiple fixes were proposed across modes and the user says something as general as "apply it", ask which ones before acting. State the exact Dataverse Web API call or `pac` command you are about to run before running it. Never bundle a role removal into the same confirmed action as a role addition (see Safety rules below).

## Safety rules

- Every mode is read-only until the report is produced and the user explicitly confirms a fix.
- Role-drift fixes only ever *add* a missing role assignment. Removing a role assignment the user didn't ask about requires its own separate confirmation, even if it was found during the same audit.
- Never turn on a flow (mode 3) while a connection reference it depends on is still reported broken by mode 2 — fix the reference first, or say the flow fix is blocked on it.
- If a proposed fix has no verified tool, command, or API call behind it (for example, an active unmanaged layer has no `pac` or Web API equivalent — see `references/admin-api-patterns.md`), say so and give the manual step instead of fabricating an automated one.
- A failed tool call against one environment or one record is reported against that specific item; it never stops the rest of the run.

## Self-check before replying

- Did you confirm the Dataverse MCP connection exists for every environment you're about to query?
- Did you call `describe` before assuming a table/column name that wasn't already verified in `references/check-recipes.md`?
- Does the report come before any write, with every write gated on explicit confirmation?
- Is every proposed fix backed by a real command/call from `references/check-recipes.md`, `references/mcp-tool-reference.md`, or `references/admin-api-patterns.md` — nothing invented?
- Did an empty result get reported as "nothing found," distinct from an error?

## References

| File | Read when |
|---|---|
| `references/mcp-tool-reference.md` | Before any Dataverse MCP tool call — confirms what each tool does and what it can't do |
| `references/check-recipes.md` | Running any of the three modes — exact query shapes, comparison logic, severity rules, report format |
| `references/admin-api-patterns.md` | A check needs something outside the Dataverse MCP tool set (environment listing, security role listing, FetchXML, confirmed gaps like unmanaged layers) |
```

- [ ] **Step 3: Run the validator**

```bash
python3 scripts/validate.py skills
```

Expected: `FAIL pp-governance-agent` at this point is fine — the references it mentions (`references/mcp-tool-reference.md`, `references/check-recipes.md`, `references/admin-api-patterns.md`) don't exist yet, which Tasks 3–5 create. Confirm the *only* errors reported are "referenced file not found" for those three paths, not a frontmatter or name error.

- [ ] **Step 4: Commit**

```bash
git add skills/pp-governance-agent/SKILL.md skills/pp-governance-agent/LICENSE.txt
git commit -m "feat: scaffold pp-governance-agent skill

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 3: Write `references/mcp-tool-reference.md`

**Files:**
- Create: `skills/pp-governance-agent/references/mcp-tool-reference.md`
- Test: `python3 scripts/check_templates.py` (parses any yaml/json fenced blocks under `skills/`)

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces: the tool catalog that Task 5 (`check-recipes.md`) cites by name (`read_query`, `describe`, `search`, `update_record`) — Task 5 must use exactly these tool names and the parameter shapes documented here.

- [ ] **Step 1: Write the file**

```markdown
# Dataverse MCP server — tool catalog and gaps

The Microsoft Dataverse MCP server (GA since December 2025) is the live connection this skill
depends on. It respects the calling user's Dataverse security role — no separate permission
model is needed. Connect one server per environment you want to check (`claude mcp add
<name> -t stdio -- npx -y @microsoft/dataverse mcp <org-url>`, or your AI tool's equivalent).

## Tools this skill uses

| Tool | What it does | How this skill uses it |
|---|---|---|
| `describe` | Returns schema/metadata for tables, searching matched results from `search`. Replaces the older `describe_table`/`list_tables`/`fetch` tools. | Call this **before** any `read_query` to confirm a table or column actually exists in this environment and under the name you expect — never assume `systemuserroles`, `connectionreferences`, etc. exist unchanged across every Dataverse version without checking. |
| `search` | Searches table schemas and metadata by keyword (not row data). | Use to find the right table name when you're unsure (e.g. searching "connection reference" to confirm the table's exact logical name in this environment). |
| `read_query` | Runs a read-only Dataverse SQL `SELECT` query against the TDS endpoint. No `INSERT`/`UPDATE`/`DELETE` — this is why all three check modes are safe to run freely in the "gather" step. | The primary tool for every "gather" and "compare" step in `references/check-recipes.md`. |
| `update_record` | Updates an existing row in a Dataverse table. | The only tool this skill uses to apply a confirmed fix (e.g. adding a role assignment, re-pointing a connection reference, turning a flow back on) — never called until the user has explicitly confirmed that specific fix. |
| `search_data` | Searches structured/unstructured row data (only available when Dataverse search is enabled for the environment). | Not used by this skill's core modes; mentioned here so you don't confuse it with `read_query` — `search_data` is relevance search, not a SQL filter. |

## Tools that exist but this skill does not use

`create_record`, `delete_record`, `create_table`, `update_table`, `delete_table`, `upsert_skill`,
`delete_skill`, `init_file_upload`, `commit_file_upload`, `file_download` are all part of the same
MCP server but outside this skill's scope (none of the three modes create or delete rows, change
schema, or move files). Do not reach for them unless a user explicitly asks for something beyond
the three modes this skill covers — if they do, that's a new check, not this skill.

## What the Dataverse MCP server cannot do (the gaps `admin-api-patterns.md` fills)

- **No cross-environment comparison.** Each MCP server connection is scoped to one environment.
  Role drift (mode 1) requires calling `read_query` once per environment server and diffing the
  results yourself — there's no built-in "compare" tool.
- **No unmanaged-layer detection.** Nothing in the Dataverse MCP tool set, the Dataverse Web API,
  or the `pac` CLI exposes whether a component has an active unmanaged layer — this is a Maker
  Portal–only concept (Solution → component → "See solution layers"). `references/admin-api-patterns.md`
  states this gap explicitly; do not fabricate a command for it.
- **No environment listing or tenant-wide security role listing.** These come from `pac admin list`
  and `pac admin list-roles` respectively (see `references/admin-api-patterns.md`), not the
  Dataverse MCP server, which only ever talks to the one environment it's connected to.

## Cost note

Dataverse MCP tool calls from non-Copilot-Studio clients (including Claude Code, Claude Desktop,
and GitHub Copilot) are billed per Microsoft's published rates unless the caller has a qualifying
Dynamics 365 Premium or Microsoft 365 Copilot license. Mention this to the user the first time a
session runs a check that will make several tool calls (e.g. one `read_query` per environment in
a multi-environment role-drift audit), so they aren't surprised by it.
```

- [ ] **Step 2: Validate**

```bash
python3 scripts/check_templates.py
python3 scripts/validate.py skills
```

Expected: `check_templates.py` reports 0 failures (no yaml/json fenced blocks in this file to break). `validate.py` still reports the same two missing references as Task 2 (`check-recipes.md`, `admin-api-patterns.md`) — `mcp-tool-reference.md` should no longer be listed as missing.

- [ ] **Step 3: Commit**

```bash
git add skills/pp-governance-agent/references/mcp-tool-reference.md
git commit -m "docs: add Dataverse MCP tool catalog reference for pp-governance-agent

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 4: Write `references/admin-api-patterns.md`

**Files:**
- Create: `skills/pp-governance-agent/references/admin-api-patterns.md`
- Test: `python3 scripts/check_templates.py`

**Interfaces:**
- Consumes: the gap list from Task 3's `mcp-tool-reference.md` (environment listing, tenant-wide role listing, unmanaged layers).
- Produces: the verified `pac` commands Task 5 cites for anything outside the Dataverse MCP tool set.

- [ ] **Step 1: Write the file**

```markdown
# pac CLI patterns for gaps the Dataverse MCP server doesn't cover

Everything here is verified against the current Power Platform CLI reference
(`learn.microsoft.com/power-platform/developer/cli/reference/admin` and `.../solution`). Use these
exact commands and flags; don't guess at variants. PAC CLI must already be authenticated
(`pac auth create ...`) for the tenant/environment in question — this skill does not set that up.

## List environments (for "across my environments" requests)

```
pac admin list
pac admin list --type Sandbox
```

`--json` returns machine-readable output if you need to parse it rather than read it directly:

```
pac admin list --json
```

## List security roles in an environment

Useful to confirm a role name actually exists in the target environment before proposing to
assign it as a mode-1 fix:

```
pac admin list-roles --environment <url-or-id>
pac admin list-roles --environment <url-or-id> --business-unit <name-or-id>
```

## Run a FetchXML query directly (fallback if `read_query`'s SQL surface can't express something)

```
pac env fetch --environment <url-or-id> --xml "<fetch><entity name='connectionreference'><attribute name='connectionreferencelogicalname' /></entity></fetch>"
```

Prefer `read_query` (via the Dataverse MCP server) for anything it can express — this is a fallback,
not the default path, since it requires the user to have `pac` installed and authenticated locally
in addition to the MCP connection.

## Confirmed gap: unmanaged layers have no CLI or API command

There is no `pac solution` subcommand, and no documented Dataverse Web API call, that lists or
removes an unmanaged layer on a component. The only documented path is the Maker Portal: open the
component, select **...** → **See solution layers**, select the unmanaged layer, then **Remove
active customizations**. This cannot be reversed.

When mode 3 (post-import flow health) finds a flow that's still broken after its connection
reference is fixed, and nothing else explains it, report this as a possible cause and give the
Maker Portal steps above — do not invent a `pac` command or attempt to automate it.

## Confirmed gap: no cross-environment diff tool

`pac` and the Dataverse MCP server both operate against one environment (or tenant-wide listing)
at a time. There is no single command that diffs role assignments between two environments — mode
1's comparison step is done by the agent itself, by running the same `read_query` against each
environment's MCP connection and comparing the two result sets in-context.
```

- [ ] **Step 2: Validate**

```bash
python3 scripts/check_templates.py
python3 scripts/validate.py skills
```

Expected: same as Task 3's check, minus `admin-api-patterns.md` from the missing-references list — only `check-recipes.md` should remain missing now.

- [ ] **Step 3: Commit**

```bash
git add skills/pp-governance-agent/references/admin-api-patterns.md
git commit -m "docs: add verified pac CLI patterns for pp-governance-agent's MCP gaps

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 5: Write `references/check-recipes.md`

**Files:**
- Create: `skills/pp-governance-agent/references/check-recipes.md`
- Test: `python3 scripts/validate.py skills` (this is the last missing reference — the skill should pass clean after this)

**Interfaces:**
- Consumes: tool names/parameters from Task 3 (`read_query`, `describe`, `update_record`), commands from Task 4 (`pac admin list-roles`, the unmanaged-layer and cross-environment-diff gap statements).
- Produces: the exact query shapes and report table columns that `SKILL.md`'s workflow (Task 2) points to by mode name.

- [ ] **Step 1: Write the file**

```markdown
# Check recipes

Call `describe` first in every mode below to confirm the named tables/columns exist in the
target environment before running the `read_query` shown — these are the standard Dataverse
table/column names, not guesses, but confirm before relying on them, per `SKILL.md`'s workflow
step 2.

## Mode 1: Role drift audit

**Gather** (once per named environment, via that environment's Dataverse MCP connection):

```sql
SELECT u.fullname, u.domainname, u.isdisabled, r.name AS role_name
FROM systemuserroles AS ur
INNER JOIN systemuser AS u ON ur.systemuserid = u.systemuserid
INNER JOIN role AS r ON ur.roleid = r.roleid
WHERE u.isdisabled = 0
ORDER BY u.fullname
```

**Compare:** build one row per (user, role) pair found in any environment, with a column per
environment showing present/absent. A user+role combination present in one environment and
absent in another is drift.

**Severity:** a high-privilege role (System Administrator, System Customizer, or any role whose
name contains "Admin") present in production but absent elsewhere is **high**. Any other drift is
**informational**.

**Report table:** `User | Role | Present in | Missing in | Severity`

**Fix on confirm:** only ever adds the missing assignment, via `update_record`-equivalent Web API
call `POST systemusers(<userid>)/systemuserroles_association/$ref` with body
`{ "@odata.id": "<env-url>/api/data/v9.2/roles(<roleid>)" }`, against the environment where it's
missing. Never remove a role assignment as part of this same confirmed action — a removal found
during the same audit needs its own separate confirmation (see `SKILL.md` Safety rules).

## Mode 2: Connection reference health

**Gather:**

```sql
SELECT connectionreferencelogicalname, connectionreferencedisplayname, connectionid, connectorid
FROM connectionreference
```

```sql
SELECT connectionid, connectorid, statecode
FROM connection
```

**Compare:** for each `connectionreference`, check whether its `connectionid` matches a row in
`connection` with `statecode = 0` (enabled). Three outcomes:
- `connectionid` is null/empty → reference was never bound to a connection in this environment.
- `connectionid` doesn't match any row in `connection` → stale, likely carried over from the
  source environment on import.
- Matches a `connection` row but that connection's `statecode` isn't 0 → connection itself is
  disabled.

Also check for an active unmanaged layer on the connection reference's solution component, per
the confirmed gap in `references/admin-api-patterns.md` — this cannot be checked automatically;
mention it as a possible secondary cause only if the reference still looks broken after the
checks above find nothing.

**Report table:** `Connection reference | Used by (flow/app) | Problem | Proposed fix`

**Fix on confirm:** if an existing enabled connection of the same connector type exists in this
environment, re-point the reference to it. If none exists, report that a new connection must be
created manually — creating a connection requires interactive OAuth sign-in, which this skill
cannot and must not attempt to automate.

## Mode 3: Post-import flow health

Run mode 2 first if this mode is requested — a broken flow is very often explained by a
connection reference problem mode 2 already found, and the report should say so rather than list
it as a second, unrelated issue.

**Gather:**

```sql
SELECT workflowid, name, statecode, statuscode, category
FROM workflow
WHERE category = 5
```

(`category = 5` is cloud flows; `category = 0` is classic workflows, out of scope for this check.)

**Compare:** a flow with `statecode = 0` (off) is a candidate. Cross-reference its connection
references against mode 2's findings: if any are broken, that's the root cause. If all of its
connection references check out fine and it's still off, the cause is unknown from these tools
alone — report it as "off, cause not determined from available data" rather than guessing.

**Report table:** `Flow | State | Root cause (if known) | Proposed fix`

**Fix on confirm:** turn the flow on via `PATCH workflows(<id>)` with body
`{ "statecode": 1, "statuscode": 2 }` — but only after any connection reference it depends on has
either been confirmed healthy by mode 2 or fixed in this same session. Per `SKILL.md`'s safety
rules, never turn on a flow against a connection reference still reported broken.
```

- [ ] **Step 2: Validate — this should now be fully clean**

```bash
python3 scripts/validate.py skills
python3 scripts/check_templates.py
```

Expected: `OK   pp-governance-agent` with zero errors from `validate.py` (both skills pass), and `check_templates.py` reports 0 failures (the only fenced blocks in these three reference files are `sql` and plain command examples, not `yaml`/`json`, so none are parsed by that script — confirm the failure count is still 0, not that these blocks were silently skipped due to a bug).

- [ ] **Step 3: Commit**

```bash
git add skills/pp-governance-agent/references/check-recipes.md
git commit -m "docs: add the three check recipes for pp-governance-agent

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 6: Add eval scenarios

**Files:**
- Create: `evals/pp-governance-agent.evals.json`
- Test: `python3 -c "import json; json.load(open('evals/pp-governance-agent.evals.json'))"` (valid JSON)

**Interfaces:**
- Consumes: the three mode names and report table shapes from Task 5.
- Produces: nothing consumed by later tasks — this is a leaf artifact, matching the existing `evals/evals.json` schema (`skill_name`, `evals: [{id, prompt, expected_output, files}]`).

- [ ] **Step 1: Write the file**

```json
{
  "skill_name": "pp-governance-agent",
  "evals": [
    {
      "id": 1,
      "prompt": "Can you check if anyone has different security roles in our prod environment compared to dev? I have MCP connections set up as dataverse-dev and dataverse-prod.",
      "expected_output": "Runs mode 1 (role drift) by calling read_query against both named MCP connections, reports a user/role/present-in/missing-in/severity table, flags any admin-type role present only in prod as high severity, and does not attempt any write without a separate confirmation step.",
      "files": []
    },
    {
      "id": 2,
      "prompt": "We just imported the Invoicing solution into UAT and three flows won't turn on. What's wrong?",
      "expected_output": "Runs mode 2 first (connection reference health) then mode 3 (post-import flow health), cross-references broken connection references as the likely root cause for the flows that won't turn on, reports a flow/state/root-cause/proposed-fix table, and does not turn any flow on without explicit confirmation and without first resolving its connection reference.",
      "files": []
    },
    {
      "id": 3,
      "prompt": "Give me a full health check on our contoso-test environment, like what the old CoE Starter Kit used to do but actually able to fix things.",
      "expected_output": "Confirms the dataverse MCP connection for contoso-test exists (or asks the user to add it if not), runs all three modes against it, reports each as its own table (reporting 'no issues found' for any mode with nothing wrong, not silence), and offers to apply specific confirmed fixes rather than applying everything at once.",
      "files": []
    }
  ]
}
```

- [ ] **Step 2: Validate it's well-formed JSON**

```bash
python3 -c "import json; json.load(open('evals/pp-governance-agent.evals.json'))"
```

Expected: no output (success) — `json.load` raises on invalid JSON, so silent completion confirms it parses.

- [ ] **Step 3: Commit**

```bash
git add evals/pp-governance-agent.evals.json
git commit -m "test: add eval scenarios for pp-governance-agent's three modes

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 7: Update root `README.md` to introduce the second skill

**Files:**
- Modify: `README.md` (root of the repo, not the skill's own file)
- Test: manual read-through; no automated check (README prose)

**Interfaces:**
- Consumes: the skill's positioning from the spec ("alternative to the retired CoE Starter Kit") and its three modes.
- Produces: nothing consumed by other tasks — this is the repo's front door.

- [ ] **Step 1: Add a new section after "Why this exists" introducing the second skill**

In `README.md`, insert a new section immediately after the existing "Why this exists" section (after the line ending `### Benefits` table, before `## Features`):

```markdown
---

## Two skills, one toolkit

| Skill | What it does | Trigger |
|---|---|---|
| [`power-platform-alm-toolkit`](skills/power-platform-alm-toolkit) | **Generates** ALM code for you: scripts, pipelines, runbooks, ready to commit and run later. | Any Power Platform ALM request. |
| [`pp-governance-agent`](skills/pp-governance-agent) | **Runs** live governance checks for you, right now, through the Dataverse MCP server you already have connected: security role drift, connection reference health, and post-import flow health — with fixes proposed and applied only on your confirmation. | "Audit my security roles," "why won't my flows turn on," "health check my environment." |

Microsoft retired the Power Platform CoE Starter Kit in May 2026. Its most-cited gap was
*visibility without actionability* — it could show you a problem but not fix it from the same
place. `pp-governance-agent` is built to close exactly that gap, with no dedicated environment or
setup required: it runs inside the AI tool you already use.

---
```

- [ ] **Step 2: Read the rendered section back to confirm it fits the surrounding doc's tone and table style**

No command — just re-read the inserted block in context against the sections immediately before and after it to confirm heading levels and table formatting match the rest of the file.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: introduce pp-governance-agent alongside the existing skill in the README

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 8: Full-repo build and final regression check

**Files:**
- None created or modified — this task only runs existing scripts across the whole repo to confirm Tasks 1–7 compose correctly.
- Test: `python3 scripts/validate.py`, `python3 scripts/check_templates.py`, `python3 scripts/build.py`

**Interfaces:**
- Consumes: everything from Tasks 1–7.
- Produces: `dist/pp-governance-agent.zip`, `dist/portable/pp-governance-agent.md`, `dist/portable/pp-governance-agent.instructions.md` — confirms Task 1's fix actually works for a real second skill, not just in theory.

- [ ] **Step 1: Run the full validation and build pipeline**

```bash
python3 scripts/validate.py
python3 scripts/check_templates.py
python3 scripts/build.py
```

Expected: all three exit 0. `validate.py` prints `OK   power-platform-alm-toolkit` and `OK   pp-governance-agent`. `build.py` lists both skills' zip and portable outputs.

- [ ] **Step 2: Inspect the new skill's generated instructions file**

```bash
cat dist/portable/pp-governance-agent.instructions.md
```

Expected: the text names `pp-governance-agent` and includes its actual frontmatter `description` (the governance-check one from Task 2), not any trace of "four-part blueprint" or the first skill's persona — this is the concrete proof that Task 1's fix works for a second skill, which was the whole reason Task 1 came first.

- [ ] **Step 3: Confirm nothing is left uncommitted**

```bash
git status
```

Expected: clean working tree (every prior task already committed its own files; `dist/` should already be covered by `.gitignore` — if `git status` shows `dist/` as untracked, confirm `.gitignore` excludes it and do not commit build output).
```
