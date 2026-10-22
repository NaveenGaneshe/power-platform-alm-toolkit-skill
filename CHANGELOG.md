# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- All four live agents: a "Keep MCP calls lean (they're billed)" section. Dataverse MCP calls from tools other than Copilot Studio have been billed in Copilot Credits since December 15, 2025, so the agents warn once before a high-volume run, aggregate in the query, reuse `describe` results and always use `TOP`, without skipping any safety step. They also explain the admin allow-list when the MCP server refuses the client.
- `power-platform-alm-toolkit`: cross-tenant promotion guidance. "When environments span tenants" in `references/pipeline-template.md` covers the per-tenant app registration, federated credential and connections, tenant isolation, and why the solution artifact is never rewritten per tenant. Added a matching runbook setup step, a Part 3 pointer and self-check line in `SKILL.md`, and eval case 4. No workflow YAML changes: the existing template already reads tenant and app per GitHub environment.
- Docs: the per-environment admin step to allow non-Copilot Studio clients on the Dataverse MCP server (user guide, README, scheduled governance check), plus a cost section for the scheduled check.

### Fixed
- Scheduled governance check: refuses to run in a public repository, because the report it posts as an issue names users, roles and connections.
- Scheduled governance check: installs the skills before the run. Claude Code doesn't discover the repo's `skills/` folder, so the run previously went ahead without the skill.
- Scheduled governance check: signs in with the `@microsoft/dataverse` proxy's own GitHub federated auth (`dataverse auth create --githubFederated`). The previous `--access-token` flag doesn't exist in the proxy (checked against v1.0.82), so the connect step would have failed. This also removes the Azure login and per-environment token steps. Setup step 3 now allows the service principal's app ID on each environment's MCP allowed-clients list.
- Live agents: the allow-list guidance now names the **Dataverse CLI** client (app ID `0c412cc3-0dd6-449b-987f-05b053db9457`) that Claude Code and Claude Desktop use through the proxy, plus the one-time tenant consent. It also fires when tools don't load or fail with a generic error, because the proxy reports the 403 only as "An error occurred" (found in a live test against a real environment).
- Scheduled governance check: pre-approves only the Dataverse MCP read tools (`read_query`, `describe`, `search`) with `--allowedTools`. Unattended runs can't approve tool calls, so the checks previously couldn't query Dataverse, and write tools now stay blocked at the tool layer. Environment names are validated because they become part of the tool names.

- Live agents: `read_query` returns at most 20 rows and rejects a larger `TOP`, and `OFFSET … FETCH` is silently ignored (all confirmed live). Recipes that used `TOP 50`/`TOP 500` failed on first try. The agents and recipes now count first, sample at most 20 rows, and page by primary key when every row is needed; role drift pages by `systemuserroleid`.
- `pp-governance-agent` mode 2 queried the `connection` table, which in Dataverse links two business records and holds no Power Platform connections. It now reads `connectionreference` and `connectioninstance`, treats a reference with a `connectionid` but no tracked instance as not verifiable from Dataverse (with a read-only `Get-AdminPowerAppConnection` check), and never concludes an environment has no connections.
- Live agents: when `describe` fails with an internal error, fall back to `search` or a `TOP 1` query instead of stopping. Data-ops and governance fallbacks fill in known values (such as the environment URL) instead of placeholders.

### Changed
- `pp-governance-agent` cost note: the license exemption covers Dynamics 365 data only, and the per-tool billing rates are stated.

## [0.1.0] - 2026-10-15

### Added
- `power-platform-alm-toolkit` skill in the open Agent Skills (`SKILL.md`) format, with the four-part operational blueprint: capability mapping, solution architecture and schemas, repository and ALM pipelines, end-user and developer runbooks.
- References: PAC CLI and `microsoft/powerplatform-actions` (verified October 2026, including the YAML source-control format), Dataverse Web API patterns, toolkit repository layout, GitHub Actions templates, runbook template.
- `assets/Dataverse.psm1`: cross-platform PowerShell 7 module (client-secret and GitHub OIDC auth, paging, `UpdateMultiple` batching with PATCH fallback, 429 retry, preview/`-WhatIf`, snapshots, job summaries), with Pester tests.
- Installers for Claude Code, Codex, GitHub Copilot, Cursor and Gemini CLI (`install.sh`, `install.ps1`), user and project scope.
- Portable single-file bundle and instructions for ChatGPT custom GPTs, Gemini Gems, Microsoft Copilot Studio, Claude Projects and any LLM.
- CI (spec validation, template parsing, PSScriptAnalyzer, Pester on Windows/macOS/Linux, installer smoke tests) and automated release packaging.

[Unreleased]: https://github.com/NaveenGaneshe/power-platform-alm-toolkit-skill/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/NaveenGaneshe/power-platform-alm-toolkit-skill/releases/tag/v0.1.0
