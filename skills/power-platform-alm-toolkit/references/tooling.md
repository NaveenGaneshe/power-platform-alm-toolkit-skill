# Power Platform tooling reference

Verified against Microsoft Learn PAC CLI reference and `microsoft/powerplatform-actions` main branch, October 2026. Use these exact names; if the user reports a flag error, ask them to run `pac <group> <command> help` and adapt.

## Installing PAC CLI

- In GitHub Actions, use the action: `microsoft/powerplatform-actions/actions-install@v1` (works on `ubuntu-latest` and `windows-latest`).
- For `run:` steps that call `pac` directly, install the .NET global tool, which is cross-platform:
  ```bash
  dotnet tool install --global Microsoft.PowerApps.CLI.Tool
  echo "$HOME/.dotnet/tools" >> "$GITHUB_PATH"
  ```
- Locally: same `dotnet tool install` command, or `pac install latest` to update.

## Authentication

```bash
# Service principal with client secret
pac auth create --name ci --applicationId "$PP_APP_ID" --clientSecret "$PP_CLIENT_SECRET" --tenant "$PP_TENANT_ID" --environment "$PP_ENV_URL"

# GitHub OIDC federation (no secret stored). Needs `permissions: id-token: write` in the workflow
# and a federated credential on the Entra app for repo:<org>/<repo>:environment:<env>.
pac auth create --name ci --githubFederated --applicationId "$PP_APP_ID" --tenant "$PP_TENANT_ID" --environment "$PP_ENV_URL"

pac auth who        # confirm the active profile
pac auth token      # print a Power Platform API access token for the active profile
```

Other switches: `--certificateDiskPath`, `--certificatePassword`, `--managedIdentity`, `--deviceCode`, `--cloud Public|UsGov|UsGovHigh|UsGovDod|China`.

The service principal must also exist as an **application user** in each Dataverse environment with a security role (Power Platform admin center → Environment → Settings → Users + permissions → Application users).

## pac solution

| Command | Key parameters |
|---|---|
| `pac solution export` | `--name` (req), `--path`, `--managed` (switch), `--overwrite`, `--async`, `--include general,autonumbering,...`, `--environment` |
| `pac solution unpack` | `--zipfile` (req), `--folder`, `--packagetype Unmanaged\|Managed\|Both` (default Unmanaged), `--allowWrite`, `--allowDelete`, `--clobber`, `--localize`, `--map` |
| `pac solution pack` | `--zipfile` (req), `--folder`, `--packagetype Unmanaged\|Managed\|Both`, `--map`, `--localize` |
| `pac solution import` | `--path`, `--settings-file`, `--activate-plugins`, `--force-overwrite`, `--publish-changes`, `--stage-and-upgrade`, `--import-as-holding`, `--skip-lower-version`, `--async`, `--max-async-wait-time`, `--environment` |
| `pac solution create-settings` | `--solution-zip` or `--solution-folder`, `--settings-file` |
| `pac solution check` | `--path` (globs ok), `--geo UnitedStates\|Europe\|India\|...`, `--outputDirectory`, `--ruleLevelOverride`, `--ruleSet` |
| `pac solution version` | `--solutionPath`, `--buildversion`, `--revisionversion`, `--strategy None\|GitTags\|FileTracking\|Solution` (`--patchversion` is deprecated and ignored) |
| `pac solution online-version` | `--solution-name` (req), `--solution-version`, `--environment` |
| `pac solution clone` | `--name` (req), `--outputDirectory`, `--packagetype`, `--include` |
| `pac solution list` | `--environment`, `--json` |
| `pac solution publish` | `--async`, `--environment` |
| `pac solution upgrade` | `--solution-name`, `--async` |
| `pac solution add-solution-component` | `--solutionUniqueName`, `--component`, `--componentType`, `--AddRequiredComponents` |

Notes:
- To build a **managed** zip from source, the source must come from an unpack with `--packagetype Both` (export both unmanaged and managed zips from dev, unpack together). Packing `Managed` from an unmanaged-only unpack fails.
- **Source formats**: classic unpack writes the XML layout (`Other/Solution.xml`, `Other/Customizations.xml`). PAC CLI 2.4.1+ also packs the **YAML source-control format** written by native Dataverse Git integration (`solutions/<Name>/solution.yml`, `publishers/...`). Pack auto-detects which one. Default to XML unless the user says they use Dataverse Git integration. `pac solution version` edits `Other/Solution.xml`, so in YAML repos bump the `version` field in `solution.yml` instead.
- Canvas apps: `pac canvas unpack --msapp <file> --sources <dir>` / `pac canvas pack`. The `pack-solution` action has a preview `process-canvas-apps` input.

## Other PAC groups commonly needed

- `pac admin list`, `pac admin create`, `pac admin backup`, `pac admin assign-user --environment <url> --user <upn|objectId> --role "<role name>"`
- `pac data export` / `pac data import` (Configuration Migration schema-based data moves)
- `pac connector create|update|download|list --api-definition-file --api-properties-file --solution-unique-name --environment`
- `pac pcf init --namespace <ns> --name <name> --template field|dataset --framework react --run-npm-install`, then `pac pcf push --publisher-prefix <prefix>` for dev
- `pac org who`, `pac env select`

## microsoft/powerplatform-actions (@v1)

Common auth inputs on every action that talks to an environment: `environment-url`, plus either `app-id` + `client-secret` + `tenant-id` **or** `user-name` + `password-secret`. Optional `cloud` (default `Public`).

| Action | Inputs (beyond auth) |
|---|---|
| `actions-install` | none |
| `who-am-i` | none |
| `export-solution` | `solution-name`, `solution-output-file`, `managed` (`'true'/'false'`), `working-directory`, `run-asynchronously`, `overwrite`, `export-general-settings` etc. |
| `unpack-solution` | `solution-file`, `solution-folder`, `solution-type` (`Unmanaged\|Managed\|Both`), `overwrite-files` |
| `pack-solution` | `solution-file`, `solution-folder`, `solution-type`, `map-file`, `process-canvas-apps` |
| `check-solution` | `path`, `geo`, `rule-level-override`, `checker-logs-artifact-name`, `fail-on-analysis-error` (default `'true'`) |
| `import-solution` | `solution-file`, `use-deployment-settings-file`, `deployment-settings-file`, `activate-plugins` (default `'true'`), `force-overwrite`, `publish-changes`, `stage-and-upgrade`, `skip-lower-version`, `run-asynchronously`, `max-async-wait-time`, `convert-to-managed` |
| `publish-solution` | none beyond auth |
| `update-solution-version` | `build-version`, `revision-version`, `strategy`, `tracker-file` |
| `set-online-solution-version` | solution name and version (check action.yml) |
| `branch-solution` | `solution-folder`, `solution-target-folder`, `token` |
| `assign-user`, `assign-group` | user/group and role (check action.yml) |
| `export-data` / `import-data` | Configuration Migration data files |
| `create-environment`, `copy-environment`, `backup-environment`, `restore-environment`, `reset-environment`, `delete-environment`, `deploy-package`, `upgrade-solution`, `delete-solution`, `add-solution-component`, `download-paportal`, `upload-paportal` | see each action.yml |

If you need an input not listed here, read `https://raw.githubusercontent.com/microsoft/powerplatform-actions/main/<action>/action.yml` rather than guessing.
