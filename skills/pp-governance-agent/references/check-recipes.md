# Check recipes

Call `describe` first in every mode below to confirm the named tables/columns exist in the
target environment before running the `read_query` shown — these are the standard Dataverse
table/column names, not guesses, but confirm before relying on them, per `SKILL.md`'s workflow
step 2.

`read_query` returns at most 20 rows per call; a `TOP` above 20 is rejected, and `OFFSET … FETCH`
is silently ignored. For any gather query that can return more, count first, then page by the
key named in that mode: add `TOP 20` and `ORDER BY <key>`, then repeat with
`WHERE <key> > '<last key seen>'` until a page returns fewer than 20 rows.

## Mode 1: Role drift audit

**Gather** (once per named environment, via that environment's Dataverse MCP connection):

```sql
SELECT TOP 20 ur.systemuserroleid, u.fullname, u.domainname, u.isdisabled, r.name AS role_name
FROM systemuserroles AS ur
INNER JOIN systemuser AS u ON ur.systemuserid = u.systemuserid
INNER JOIN role AS r ON ur.roleid = r.roleid
WHERE u.isdisabled = 0
ORDER BY ur.systemuserroleid
```

Page by `ur.systemuserroleid` (see above); sort by user name yourself when building the report.

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
SELECT connectionreferenceid, connectionreferencelogicalname, connectionreferencedisplayname,
       connectionid, connectorid, statecode
FROM connectionreference
```

```sql
SELECT connectionreferenceid, connectioninternalid, connectionstatus, statecode
FROM connectioninstance
```

Page both by their `connectionreferenceid` if there are more than 20. Don't use the `connection`
table: in Dataverse it links two business records and has nothing to do with Power Platform
connections. Power Platform connections live in Power Platform's own connection service, outside
Dataverse. `connectioninstance` holds a row only for connections Dataverse tracks for a
connection reference, so a missing row, or an empty table, never proves a connection doesn't
exist. Never report "this environment has no connections" from these queries.

**Compare:** for each `connectionreference`, four outcomes:
- `connectionid` is null/empty → **broken**: the reference was never bound to a connection in this
  environment. This is certain from Dataverse alone.
- A `connectioninstance` row for this reference has `statecode` ≠ 0, or a `connectionstatus` that
  reports an error → **broken**: quote `connectionstatus` as-is rather than interpreting it.
- A `connectioninstance` row with `statecode = 0` and no error in `connectionstatus` → **healthy**.
- `connectionid` is set but there's no `connectioninstance` row → **not verifiable from Dataverse**.
  Don't call it broken or healthy. Give the user this read-only check (needs the
  `Microsoft.PowerApps.Administration.PowerShell` module and environment admin rights), using the
  `shared_…` connector name from `connectorid`, and compare the connection names it returns with
  `connectionid`:
  `Get-AdminPowerAppConnection -EnvironmentName <environment-id> -ConnectorName <shared_connector_name>`.
  No match means the reference is stale, most likely carried over from the source environment on
  import.

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
references against mode 2's findings. `workflow.connectionreferences` is often empty, so match
through the flow definition instead, once per broken reference:

```sql
SELECT TOP 20 workflowid, name
FROM workflow
WHERE category = 5 AND clientdata LIKE '%<connectionreferencelogicalname>%'
```

Then: if any are broken, that's the root cause. If all of its
connection references check out fine and it's still off, the cause is unknown from these tools
alone — report it as "off, cause not determined from available data" rather than guessing.

**Report table:** `Flow | State | Root cause (if known) | Proposed fix`

**Fix on confirm:** turn the flow on via `PATCH workflows(<id>)` with body
`{ "statecode": 1, "statuscode": 2 }` — but only after any connection reference it depends on has
either been confirmed healthy by mode 2 or fixed in this same session. Per `SKILL.md`'s safety
rules, never turn on a flow against a connection reference still reported broken.
