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
