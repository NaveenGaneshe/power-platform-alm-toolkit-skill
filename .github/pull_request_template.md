## What changed and why

<!-- One topic per PR. Link the issue if there is one. -->

## Evidence

<!-- Factual changes to references: link the Microsoft docs / action.yml.
     Skill-instruction changes: short before/after excerpt of the output for a prompt from evals/ or examples/. -->

## Checklist

- [ ] `python3 scripts/validate.py`, `scripts/check_templates.py` and `scripts/build.py` pass
- [ ] PowerShell changes: PSScriptAnalyzer clean and Pester tests pass
- [ ] Safety defaults unchanged (test run, snapshots, approval gates, least privilege)
- [ ] No secrets, real tenant names or environment URLs
- [ ] `CHANGELOG.md` updated under *Unreleased*
