# Runbook template (Part 4)

Write for two readers. The operator section assumes no Git, PowerShell or Dataverse knowledge. Test it mentally: could a busy admin who has never opened GitHub Actions run this correctly, and recognise when something went wrong? Keep sentences short and use the button and field labels exactly as they appear on screen.

Glossary to reuse when a term is unavoidable:
- **Environment**: one copy of your Power Platform setup (Dev for building, Test for checking, Production for real work).
- **Test run**: shows what would change, and changes nothing.
- **Snapshot**: a saved copy of the records before they were changed, used to undo.
- **Table**: what Dataverse calls a list of records (e.g. Accounts). The *logical name* is its lowercase system name, like `account`.

---

~~~markdown
# <Module name in plain words>

**What it does:** <one sentence a non-technical person understands, e.g. "Switches off every Power Automate flow in a solution, and can switch them back on later.">

**Category:** <Capability category> · **Changes data:** <Yes / No> · **Undo available:** <Yes, how / No>

## For operators (no code needed)

### Before you start
- You need permission to run workflows in this repository (ask <team/owner>).
- Production runs wait for approval from <approver group>. This is expected.

### What you'll fill in

| Field on the form | Type | Example | If left blank |
|---|---|---|---|
| Which environment? | Dropdown | `dev` | Uses `dev` |
| Test run (change nothing) | Tick box, ticked by default | ✅ | Stays ticked: a safe preview |
| <Field label> | Text box | `<example>` | <Required / default and what it means> |
| Confirm | Text box | `APPLY` | Required only when Test run is unticked |

### Steps
1. Open the repository on GitHub and select the **Actions** tab.
2. In the left list, select **Run: <workflow name>**.
3. Select **Run workflow** (top right), fill in the form above, then select the green **Run workflow** button.
4. Wait for the green tick (usually <N> minutes). Select the run, then read the **Summary**: it lists what was (or would be) changed.
5. Happy with the preview? Run it again with **Test run** unticked and `APPLY` typed in **Confirm**.

### Reading the result
- ✅ Green tick: finished. The summary shows how many records were changed and how many failed.
- ❌ Red cross: nothing further was changed after the error. Open the run, select the failed step, and send the red message to <support channel>.
- The **Artifacts** section at the bottom holds the snapshot file (kept 90 days).

### Undo
<Exact steps: e.g. "Run **Run: <undo workflow>** and paste the snapshot file name into Snapshot file." or "Not reversible: take an environment backup first.">

### Asking in plain language
If your team has the toolkit's Copilot Studio agent or Claude connected, you can ask:
- "<natural-language prompt 1, e.g. Do a test run that switches off all flows in the Invoicing solution in test>"
- "<prompt 2>"
- "<prompt 3>"

## For developers

### Prerequisites
- PowerShell 7.2+ (`pwsh`), Power Platform CLI (`dotnet tool install --global Microsoft.PowerApps.CLI.Tool`)
- An Entra ID app registration added as an **application user** in each environment with role: <least-privilege role>

### One-time setup
1. GitHub → Settings → Environments: create `dev`, `test`, `production` (add required reviewers on `production`).
2. In each environment add variables `PP_ENV_URL`, `PP_APP_ID`, `PP_TENANT_ID` and secret `PP_CLIENT_SECRET` (or configure a federated credential for `repo:<org>/<repo>:environment:<name>` and skip the secret).
3. <Module-specific setup: extra variables, solution import, connector connection, etc.>

### Run locally
```powershell
$env:DATAVERSE_URL = 'https://<org>.crm.dynamics.com'
$env:AZURE_TENANT_ID = '<tenant-guid>'
$env:AZURE_CLIENT_ID = '<app-guid>'
$env:AZURE_CLIENT_SECRET = '<secret>'   # local only, never commit
./modules/<category>/<module-name>/scripts/Invoke-<Operation>.ps1 -<Param> <value>            # preview
./modules/<category>/<module-name>/scripts/Invoke-<Operation>.ps1 -<Param> <value> -Apply     # apply
```

### Tests
`Invoke-Pester ./modules/<category>/<module-name>/tests`

### Extending
<Where to add a new parameter: script param block → workflow_dispatch input → this README's field table.>
~~~
