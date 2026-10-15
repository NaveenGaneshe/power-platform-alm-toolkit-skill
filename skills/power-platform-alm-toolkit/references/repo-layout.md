# Toolkit repository layout

Keep this layout so every module is discoverable, testable and deployable the same way. When the user's repo already has a different convention, follow theirs and say where you deviated.

```
pp-ops-toolkit/
├── README.md                         # catalog of modules (one row per module, link to its README)
├── LICENSE                           # MIT by default for open source
├── CONTRIBUTING.md
├── .gitattributes                    # *.xml text eol=lf, *.msapp binary, *.zip binary
├── .gitignore                        # out/, *.zip, bin/, obj/, node_modules/, snapshots/
├── .github/
│   ├── workflows/
│   │   ├── _reusable-deploy-solution.yml   # shared: pack → check → import (called by others)
│   │   ├── solution-export.yml             # dev → source control PR
│   │   ├── solution-build-deploy.yml       # PR validation + test → prod promotion
│   │   └── op-<module-name>.yml            # one citizen-facing runbook per operation module
│   ├── ISSUE_TEMPLATE/
│   └── CODEOWNERS                    # require review on workflows/ and shared/
├── shared/
│   ├── scripts/
│   │   ├── Dataverse.psm1            # auth, paging, batching, retry, snapshots
│   │   └── New-DeploymentSettings.ps1
│   └── tests/
│       └── Dataverse.Tests.ps1       # Pester
├── solutions/
│   └── <SolutionUniqueName>/
│       ├── module.json               # version + metadata (see below)
│       ├── deployment-settings.template.json  # ${TOKEN} placeholders, filled per GitHub environment; no secrets
│       └── src/                      # unpacked solution (Both): Other/, Entities/, Workflows/...
└── modules/
    └── <category>/<module-name>/     # category: data-schema | access-admin | automation-governance | environment-ops
        ├── module.json
        ├── README.md                 # Part 4 runbook
        ├── scripts/                  # Invoke-<Verb><Noun>.ps1 entry points
        ├── schemas/                  # input JSON Schema, FetchXML, query definitions
        ├── connector/                # if the module ships a custom connector
        ├── pcf/                      # if the module ships a micro-frontend
        └── tests/                    # Pester tests with mocked HTTP
```

Why the split: `solutions/` holds things Dataverse owns (round-tripped through export/unpack), `modules/` holds things Git owns (scripts and definitions authored here). Mixing them causes unpack to overwrite hand-written files.

## module.json

```json
{
  "$schema": "../../../shared/schemas/module.schema.json",
  "name": "bulk-deactivate-records",
  "category": "Data & Schema Management",
  "version": { "major": 1, "minor": 0 },
  "description": "Deactivates records in any table that match a filter, with preview and undo.",
  "entryPoint": "scripts/Invoke-BulkDeactivate.ps1",
  "runbookWorkflow": ".github/workflows/op-bulk-deactivate-records.yml",
  "solution": null,
  "requiredRole": "Basic User + custom role 'Toolkit Data Operator' (Read/Write on target tables)",
  "mutates": true
}
```

The pipeline reads `version.major`/`minor`; build and revision come from the run, so nobody hand-edits versions.

## Deployment settings template

Generated once with `pac solution create-settings --solution-zip <zip> --settings-file <file>`, then values replaced with `${VAR_NAME}` tokens. One template serves every environment: the pipeline fills tokens from the target GitHub environment's variables and secrets (`shared/scripts/New-DeploymentSettings.ps1`) and fails if any token is missing:

```json
{
  "EnvironmentVariables": [
    { "SchemaName": "<prefix>_ApiBaseUrl", "Value": "${PP_API_BASE_URL}" }
  ],
  "ConnectionReferences": [
    { "LogicalName": "<prefix>_sharedoffice365_ref", "ConnectionId": "${PP_CONN_OFFICE365}", "ConnectorId": "/providers/Microsoft.PowerApps/apis/shared_office365" }
  ]
}
```
