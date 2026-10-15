# GitHub Actions templates

Four workflows cover the toolkit. Adapt names and inputs; keep the structure. All run on `ubuntu-latest` (cheaper and faster than Windows; PAC actions and `pwsh` both work there).

## GitHub setup the pipelines assume

| GitHub environment | Protection | Variables (`vars`) | Secrets |
|---|---|---|---|
| `dev` | none | `PP_ENV_URL`, `PP_APP_ID`, `PP_TENANT_ID`, plus any `${TOKEN}` used in deployment settings | `PP_CLIENT_SECRET` (omit if using OIDC) |
| `test` | optional wait timer | same names, test values | same |
| `production` | **required reviewers**, deployment branch = `main` | same names, prod values | same |

Each environment can point at a different tenant or app registration. Because names are identical, the same workflow code deploys anywhere: that is the "environment-agnostic" guarantee.

Versioning rule: `major.minor` from `solutions/<Name>/module.json` → full version `major.minor.<run_number>.<run_attempt>`.

---

## 1. `solution-export.yml` (dev → pull request)

```yaml
name: "Solution: export from Dev into source control"

on:
  workflow_dispatch:
    inputs:
      solution_name:
        description: "Solution unique name (not the display name)"
        required: true
        type: string
      change_summary:
        description: "One line describing what changed in Dev"
        required: true
        type: string

permissions:
  contents: write
  pull-requests: write

concurrency:
  group: export-${{ inputs.solution_name }}
  cancel-in-progress: false

jobs:
  export:
    runs-on: ubuntu-latest
    environment: dev
    env:
      SOLUTION: ${{ inputs.solution_name }}
    steps:
      - uses: actions/checkout@v4

      - name: Install Power Platform tools
        uses: microsoft/powerplatform-actions/actions-install@v1

      - name: Publish all customizations in Dev
        uses: microsoft/powerplatform-actions/publish-solution@v1
        with:
          environment-url: ${{ vars.PP_ENV_URL }}
          app-id: ${{ vars.PP_APP_ID }}
          client-secret: ${{ secrets.PP_CLIENT_SECRET }}
          tenant-id: ${{ vars.PP_TENANT_ID }}

      - name: Export unmanaged
        uses: microsoft/powerplatform-actions/export-solution@v1
        with:
          environment-url: ${{ vars.PP_ENV_URL }}
          app-id: ${{ vars.PP_APP_ID }}
          client-secret: ${{ secrets.PP_CLIENT_SECRET }}
          tenant-id: ${{ vars.PP_TENANT_ID }}
          solution-name: ${{ env.SOLUTION }}
          solution-output-file: out/${{ env.SOLUTION }}.zip
          managed: false
          run-asynchronously: true
          overwrite: true

      - name: Export managed
        uses: microsoft/powerplatform-actions/export-solution@v1
        with:
          environment-url: ${{ vars.PP_ENV_URL }}
          app-id: ${{ vars.PP_APP_ID }}
          client-secret: ${{ secrets.PP_CLIENT_SECRET }}
          tenant-id: ${{ vars.PP_TENANT_ID }}
          solution-name: ${{ env.SOLUTION }}
          solution-output-file: out/${{ env.SOLUTION }}_managed.zip
          managed: true
          run-asynchronously: true
          overwrite: true

      # "Both" reads <name>.zip and <name>_managed.zip side by side, so the build can later pack a managed artifact from source.
      - name: Unpack (managed + unmanaged)
        uses: microsoft/powerplatform-actions/unpack-solution@v1
        with:
          solution-file: out/${{ env.SOLUTION }}.zip
          solution-folder: solutions/${{ env.SOLUTION }}/src
          solution-type: Both
          overwrite-files: true

      - name: Create module.json if this is a new solution
        shell: bash
        run: |
          f="solutions/$SOLUTION/module.json"
          if [ ! -f "$f" ]; then
            jq -n --arg n "$SOLUTION" '{name:$n, category:"Environment Operations", version:{major:1, minor:0}, solution:$n, mutates:false}' > "$f"
          fi

      - name: Open pull request
        uses: peter-evans/create-pull-request@v7
        with:
          branch: export/${{ env.SOLUTION }}-${{ github.run_number }}
          title: "Export ${{ env.SOLUTION }}: ${{ inputs.change_summary }}"
          commit-message: "Export ${{ env.SOLUTION }} from Dev: ${{ inputs.change_summary }}"
          body: |
            Exported by run ${{ github.run_id }} from ${{ vars.PP_ENV_URL }}.
            Requested by @${{ github.actor }}.
          add-paths: solutions/${{ env.SOLUTION }}/**
          delete-branch: true
```

---

## 2. `solution-build-deploy.yml` (validate → build → test → production)

```yaml
name: "Solution: validate, build and deploy"

on:
  pull_request:
    branches: [main]
    paths: ["solutions/**", "modules/**", "shared/**", ".github/workflows/**"]
  push:
    branches: [main]
    paths: ["solutions/**", "shared/**"]
  workflow_dispatch:

permissions:
  contents: read

concurrency:
  group: build-deploy-${{ github.ref }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Lint JSON
        shell: bash
        run: |
          set -euo pipefail
          find . -name '*.json' -not -path './node_modules/*' -not -path './out/*' -print0 \
            | xargs -0 -I{} sh -c 'jq empty "{}" || { echo "Invalid JSON: {}"; exit 1; }'

      - name: Lint YAML
        shell: bash
        run: |
          pip install --quiet yamllint
          yamllint -d '{extends: relaxed, rules: {line-length: disable}}' .github/

      - name: PowerShell analysis and tests
        shell: pwsh
        run: |
          Set-PSRepository PSGallery -InstallationPolicy Trusted
          Install-Module PSScriptAnalyzer -Scope CurrentUser -Force
          Install-Module Pester -Scope CurrentUser -Force -MinimumVersion 5.5.0 -SkipPublisherCheck
          $issues = Invoke-ScriptAnalyzer -Path . -Recurse -Severity Error,Warning -ExcludeRule PSAvoidUsingWriteHost
          $issues | Format-Table -AutoSize
          if ($issues | Where-Object Severity -eq 'Error') { throw 'PSScriptAnalyzer found errors.' }
          $cfg = New-PesterConfiguration
          $paths = @('shared/tests', 'modules') | Where-Object { Test-Path $_ }
          if (-not $paths) { Write-Host 'No tests found.'; return }
          $cfg.Run.Path = $paths
          $cfg.Run.Exit = $true
          $cfg.TestResult.Enabled = $true
          Invoke-Pester -Configuration $cfg

  discover:
    runs-on: ubuntu-latest
    outputs:
      solutions: ${{ steps.list.outputs.solutions }}
    steps:
      - uses: actions/checkout@v4
      - id: list
        shell: bash
        run: |
          if [ -d solutions ]; then
            list=$(find solutions -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | jq -R . | jq -cs .)
          else
            list='[]'
          fi
          echo "solutions=$list" >> "$GITHUB_OUTPUT"

  build:
    needs: [validate, discover]
    if: needs.discover.outputs.solutions != '[]'
    runs-on: ubuntu-latest
    environment: dev            # solution checker needs a tenant credential
    strategy:
      fail-fast: false
      matrix:
        solution: ${{ fromJSON(needs.discover.outputs.solutions) }}
    env:
      SOLUTION: ${{ matrix.solution }}
      SRC: solutions/${{ matrix.solution }}/src
    steps:
      - uses: actions/checkout@v4

      - name: Install Power Platform tools
        uses: microsoft/powerplatform-actions/actions-install@v1

      - name: Stamp version
        id: version
        shell: bash
        run: |
          set -euo pipefail
          major=$(jq -r '.version.major' "solutions/$SOLUTION/module.json")
          minor=$(jq -r '.version.minor' "solutions/$SOLUTION/module.json")
          version="$major.$minor.${{ github.run_number }}.${{ github.run_attempt }}"
          if [ -f "$SRC/Other/Solution.xml" ]; then
            # XML source format: replace the first <Version> (the solution manifest's)
            sed -i -E "0,/<Version>[^<]*<\/Version>/s//<Version>${version}<\/Version>/" "$SRC/Other/Solution.xml"
          else
            # YAML source format (Dataverse Git integration)
            sed -i -E "0,/^(\s*)version:.*/s//\1version: ${version}/" "$SRC/solutions/$SOLUTION/solution.yml"
          fi
          echo "version=$version" >> "$GITHUB_OUTPUT"
          echo "Solution $SOLUTION version $version" >> "$GITHUB_STEP_SUMMARY"

      - name: Pack managed
        uses: microsoft/powerplatform-actions/pack-solution@v1
        with:
          solution-folder: ${{ env.SRC }}
          solution-file: out/${{ env.SOLUTION }}_managed.zip
          solution-type: Managed

      - name: Solution checker
        uses: microsoft/powerplatform-actions/check-solution@v1
        with:
          environment-url: ${{ vars.PP_ENV_URL }}
          app-id: ${{ vars.PP_APP_ID }}
          client-secret: ${{ secrets.PP_CLIENT_SECRET }}
          tenant-id: ${{ vars.PP_TENANT_ID }}
          path: out/${{ env.SOLUTION }}_managed.zip
          geo: ${{ vars.PP_CHECKER_GEO || 'UnitedStates' }}
          checker-logs-artifact-name: checker-${{ env.SOLUTION }}
          fail-on-analysis-error: true

      - name: Upload build artifact
        uses: actions/upload-artifact@v4
        with:
          name: solution-${{ env.SOLUTION }}
          path: |
            out/${{ env.SOLUTION }}_managed.zip
            solutions/${{ env.SOLUTION }}/deployment-settings.template.json
          if-no-files-found: warn
          retention-days: 30

  deploy-test:
    needs: [build, discover]
    if: github.event_name != 'pull_request' && github.ref == 'refs/heads/main'
    strategy:
      fail-fast: false
      matrix:
        solution: ${{ fromJSON(needs.discover.outputs.solutions) }}
    uses: ./.github/workflows/_reusable-import-solution.yml
    with:
      environment: test
      solution: ${{ matrix.solution }}
    secrets: inherit

  deploy-production:
    needs: [deploy-test, discover]
    strategy:
      fail-fast: false
      matrix:
        solution: ${{ fromJSON(needs.discover.outputs.solutions) }}
    uses: ./.github/workflows/_reusable-import-solution.yml
    with:
      environment: production   # pauses here until a required reviewer approves
      solution: ${{ matrix.solution }}
    secrets: inherit
```

---

## 3. `_reusable-import-solution.yml` (inject settings → import)

```yaml
name: "Reusable: import a solution into an environment"

on:
  workflow_call:
    inputs:
      environment:
        type: string
        required: true
      solution:
        type: string
        required: true

jobs:
  import:
    runs-on: ubuntu-latest
    environment: ${{ inputs.environment }}
    env:
      SOLUTION: ${{ inputs.solution }}
    steps:
      - uses: actions/checkout@v4
        with:
          sparse-checkout: shared/scripts

      - uses: actions/download-artifact@v4
        with:
          name: solution-${{ inputs.solution }}
          path: artifact

      - name: Install Power Platform tools
        uses: microsoft/powerplatform-actions/actions-install@v1

      - name: Build deployment settings for ${{ inputs.environment }}
        id: settings
        shell: pwsh
        env:
          GH_VARS: ${{ toJSON(vars) }}
          GH_SECRETS: ${{ toJSON(secrets) }}
        run: |
          $template = Get-ChildItem artifact -Recurse -Filter 'deployment-settings.template.json' | Select-Object -First 1
          if (-not $template) {
            "file=" >> $env:GITHUB_OUTPUT
            Write-Host 'No deployment settings template; importing without one.'
            return
          }
          ./shared/scripts/New-DeploymentSettings.ps1 -TemplatePath $template.FullName -OutputPath out/deployment-settings.json
          "file=out/deployment-settings.json" >> $env:GITHUB_OUTPUT

      - name: Import (stage and upgrade)
        uses: microsoft/powerplatform-actions/import-solution@v1
        with:
          environment-url: ${{ vars.PP_ENV_URL }}
          app-id: ${{ vars.PP_APP_ID }}
          client-secret: ${{ secrets.PP_CLIENT_SECRET }}
          tenant-id: ${{ vars.PP_TENANT_ID }}
          solution-file: artifact/out/${{ inputs.solution }}_managed.zip
          use-deployment-settings-file: ${{ steps.settings.outputs.file != '' }}
          deployment-settings-file: ${{ steps.settings.outputs.file }}
          stage-and-upgrade: true
          activate-plugins: true
          run-asynchronously: true
          max-async-wait-time: 60
```

`upload-artifact` strips the paths' common prefix. The two uploaded paths (`out/...` and `solutions/...`) share only the repo root, so the zip lands at `artifact/out/<name>_managed.zip`. If you upload only the zip, it lands at `artifact/<name>_managed.zip` instead.

### `shared/scripts/New-DeploymentSettings.ps1`

```powershell
#Requires -Version 7.2
<#
.SYNOPSIS Fills ${TOKEN} placeholders in a deployment settings template from GitHub vars/secrets JSON.
          Fails if any token stays unresolved, so a missing variable can never deploy an empty value.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$TemplatePath,
    [Parameter(Mandatory)][string]$OutputPath
)
$ErrorActionPreference = 'Stop'
$lookup = @{}
foreach ($src in @($env:GH_VARS, $env:GH_SECRETS)) {
    if ([string]::IsNullOrWhiteSpace($src)) { continue }
    $obj = $src | ConvertFrom-Json -AsHashtable
    foreach ($k in $obj.Keys) { $lookup[$k] = [string]$obj[$k] }
}
# Plain environment variables work too, for local runs.
Get-ChildItem env: | ForEach-Object { if (-not $lookup.ContainsKey($_.Name)) { $lookup[$_.Name] = $_.Value } }

$text = Get-Content -Raw -Path $TemplatePath
$missing = [System.Collections.Generic.List[string]]::new()
$result = [regex]::Replace($text, '\$\{([A-Za-z_][A-Za-z0-9_]*)\}', {
    param($m)
    $name = $m.Groups[1].Value
    if ($lookup.ContainsKey($name) -and $lookup[$name] -ne '') {
        # JSON-escape the value so quotes or backslashes can't break the file
        return ($lookup[$name] | ConvertTo-Json -Compress).Trim('"')
    }
    $missing.Add($name); return $m.Value
})
if ($missing.Count) { throw "Unresolved settings tokens: $($missing | Sort-Object -Unique | Join-String -Separator ', '). Add them as GitHub environment variables or secrets." }
$null = $result | ConvertFrom-Json   # validate JSON
New-Item -ItemType Directory -Force -Path (Split-Path $OutputPath) | Out-Null
Set-Content -Path $OutputPath -Value $result -Encoding utf8
Write-Host "Deployment settings written to $OutputPath"
```

---

## 4. `op-<module-name>.yml` (citizen-developer runbook form)

Pattern for every operation module. `workflow_dispatch` inputs render as a form in GitHub: `string` → text field, `boolean` → checkbox toggle, `choice` → dropdown, `environment` → environment picker.

```yaml
name: "Run: <Plain-language operation name>"

on:
  workflow_dispatch:
    inputs:
      environment:
        description: "Which environment?"
        type: choice
        options: [dev, test, production]
        default: dev
      test_run:
        description: "Test run: show what would change, change nothing (untick to apply)"
        type: boolean
        default: true
      # --- module-specific inputs below (plain-language descriptions) ---
      table_name:
        description: "Table logical name, e.g. account or contoso_project"
        type: string
        required: true
      confirm:
        description: "When the test run box is unticked, type APPLY to confirm"
        type: string
        required: false

permissions:
  contents: read
  id-token: write          # enables secretless OIDC sign-in when no client secret is set

concurrency:
  group: op-<module-name>-${{ inputs.environment }}
  cancel-in-progress: false

jobs:
  run:
    runs-on: ubuntu-latest
    environment: ${{ inputs.environment }}
    timeout-minutes: 120
    steps:
      - uses: actions/checkout@v4

      - name: Check inputs
        shell: pwsh
        env:
          TEST_RUN: ${{ inputs.test_run }}
          CONFIRM: ${{ inputs.confirm }}
          TABLE: ${{ inputs.table_name }}
        run: |
          if ($env:TABLE -notmatch '^[a-z][a-z0-9_]{1,63}$') { throw "Table name '$($env:TABLE)' doesn't look like a logical name (lowercase, no spaces)." }
          if ($env:TEST_RUN -eq 'false' -and $env:CONFIRM -ne 'APPLY') { throw 'To apply changes, untick "Test run" AND type APPLY in the confirm box.' }

      - name: Run operation
        shell: pwsh
        env:
          DATAVERSE_URL: ${{ vars.PP_ENV_URL }}
          AZURE_TENANT_ID: ${{ vars.PP_TENANT_ID }}
          AZURE_CLIENT_ID: ${{ vars.PP_APP_ID }}
          AZURE_CLIENT_SECRET: ${{ secrets.PP_CLIENT_SECRET }}
          TABLE: ${{ inputs.table_name }}
          TEST_RUN: ${{ inputs.test_run }}
        run: |
          ./modules/<category>/<module-name>/scripts/Invoke-<Operation>.ps1 `
            -TableName $env:TABLE `
            -Apply:($env:TEST_RUN -eq 'false') `
            -OutputDirectory out

      - name: Keep snapshot and results
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: results-${{ inputs.environment }}-${{ github.run_number }}
          path: out/
          retention-days: 90
```

Notes:
- Never interpolate `${{ inputs.* }}` directly inside `run:` script bodies: a value containing quotes becomes code (script injection). Pass inputs through `env:` and read `$env:NAME`, as both steps above do.
- Production runs, including test runs, wait for approval because the `production` environment has required reviewers. Say so in the runbook.
- `-Apply:$true/$false` makes the script's default (no `-Apply`) the safe preview.
