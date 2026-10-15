# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.0] - 2026-10-15

### Added
- `power-platform-alm-toolkit` skill in the open Agent Skills (`SKILL.md`) format, with the four-part operational blueprint: capability mapping, solution architecture and schemas, repository and ALM pipelines, end-user and developer runbooks.
- References: PAC CLI and `microsoft/powerplatform-actions` (verified October 2026, including the YAML source-control format), Dataverse Web API patterns, toolkit repository layout, GitHub Actions templates, runbook template.
- `assets/Dataverse.psm1`: cross-platform PowerShell 7 module (client-secret and GitHub OIDC auth, paging, `UpdateMultiple` batching with PATCH fallback, 429 retry, preview/`-WhatIf`, snapshots, job summaries), with Pester tests.
- Installers for Claude Code, Codex, GitHub Copilot, Cursor and Gemini CLI (`install.sh`, `install.ps1`), user and project scope.
- Portable single-file bundle and instructions for ChatGPT custom GPTs, Gemini Gems, Microsoft Copilot Studio, Claude Projects and any LLM.
- CI (spec validation, template parsing, PSScriptAnalyzer, Pester on Windows/macOS/Linux, installer smoke tests) and tag-driven releases.

[Unreleased]: https://github.com/NaveenGaneshe/power-platform-alm-toolkit-skill/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/NaveenGaneshe/power-platform-alm-toolkit-skill/releases/tag/v0.1.0
