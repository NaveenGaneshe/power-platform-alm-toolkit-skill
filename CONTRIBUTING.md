# Contributing

Thanks for helping. Most valuable contributions, in order:

1. **Corrections to the references.** A PAC CLI parameter changed, an action input was renamed, a Web API pattern is wrong. Include a link to the Microsoft docs or `action.yml` that proves it.
2. **New verified patterns** for `references/dataverse-patterns.md` (tested against a real environment, with the request and response shape).
3. **Bug reports** with the prompt you used, the AI tool and model, and what was wrong in the output.
4. **Improvements to the skill instructions** that are backed by an example where the output got better.

## Ground rules

- **Verified over plausible.** Don't add a command, flag or API shape you haven't checked in official docs or run yourself. Wrong-but-confident reference material is the main way this skill can fail.
- **Keep SKILL.md lean** (under 500 lines). Put detail in `references/` and point to it from SKILL.md with a "read when" note.
- **Explain the why.** Instructions that give a reason ("default to a test run because operators press the button without reading the code") work better than bare MUSTs.
- **Safety defaults stay on.** Changes must not weaken test-run defaults, snapshots, approval gates or least privilege.
- **No secrets, tenant names or real environment URLs** in examples. Use `<PLACEHOLDER>` or `contoso`.

## Local checks

```bash
pip install pyyaml
python3 scripts/validate.py
python3 scripts/check_templates.py
python3 scripts/build.py
```

```powershell
Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
Invoke-Pester ./tests -Output Detailed
```

CI runs all of these on Windows, macOS and Linux.

## Testing a change to the skill

1. Install your working copy: `./scripts/install.sh --tool claude` (or your tool).
2. Run a few prompts from `evals/evals.json` and `examples/prompts.md` in a fresh session.
3. In the pull request, paste a short before/after excerpt of the part of the output your change affects.

## Repository layout

```text
.
├── skills/                          # every skill; each folder is installed on its own
│   ├── power-platform-alm-toolkit/  #   generates ALM code and pipelines (assets/Dataverse.psm1 is tested)
│   ├── pp-data-ops-agent/           #   queries and bulk changes, live or generated
│   ├── pp-governance-agent/         #   role drift, connection reference and flow health
│   ├── pp-migration-agent/          #   environment copy, tenant migration, record and legacy moves
│   └── pp-integration-agent/        #   external platform connectors and sync (assets/IdempotentSync.psm1)
├── scripts/                         # install.sh / install.ps1, validate.py, check_templates.py, build.py
├── tests/                           # Pester tests, HTTP fully mocked
├── docs/                            # user guide, installation, chat assistants, scheduled check, publishing
├── examples/prompts.md              # prompt library
├── evals/                           # evaluation prompts, one file per skill
└── .github/workflows/               # CI, release, scheduled governance check
```

Each skill folder holds `SKILL.md` (instructions and trigger description), `references/` (detail
loaded only when needed) and `LICENSE.txt`.

## Releasing

Bump `metadata.version` in `SKILL.md`, update `CHANGELOG.md`, then publish a GitHub release with a
matching tag (for example `v0.2.0`). The release workflow builds and attaches each skill's zip, the
single-file bundles, the chat instructions and checksums.

## Roadmap

- [ ] Evaluation runs across the prompts in `evals/` with published results
- [ ] Ready-made reference modules (data dictionary, flow on/off, role sync) in a companion `pp-ops-toolkit` repo
- [ ] Azure DevOps pipeline variants
- [ ] Copilot Studio agent template that calls the toolkit's runbook workflows from natural language
- [ ] Power Pages and Dataverse elastic-table patterns

Ideas welcome: [open an issue](https://github.com/NaveenGaneshe/power-platform-alm-toolkit-skill/issues).

## Pull requests

- One topic per PR. Update `CHANGELOG.md` under *Unreleased*.
- Use clear commit messages (`references: fix import-solution input name`).
- By contributing you agree your work is licensed under the MIT License.

## Code of conduct

Be respectful and constructive. This project follows the [Contributor Covenant 2.1](https://www.contributor-covenant.org/version/2/1/code_of_conduct/). Report unacceptable behaviour to the maintainers privately (see [SECURITY.md](SECURITY.md) for how to reach them).
