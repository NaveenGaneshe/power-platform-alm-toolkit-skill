# Publishing checklist (maintainers)

Follow these steps once to put this project on GitHub. Delete this file afterwards if you like.

## 1. Repository name

All links point to `github.com/NaveenGaneshe/power-platform-alm-toolkit-skill`, so create the repository with exactly that name. If you choose a different name, replace `power-platform-alm-toolkit-skill` throughout the files. Keep the skill folder name `power-platform-alm-toolkit`: it must match `name:` in `SKILL.md`.

## 2. Create the repository and push

```bash
git init -b main
git add .
git commit -m "Initial release: power-platform-alm-toolkit skill v0.1.0"
gh repo create NaveenGaneshe/power-platform-alm-toolkit-skill --public --source . --push \
  --description "Agent Skill that turns Claude, Codex, Copilot, Cursor & Gemini into a Power Platform ALM architect"
```

Without the GitHub CLI: create an empty public repo on github.com, then `git remote add origin <url> && git push -u origin main`.

## 3. Configure the repository

- **Actions:** confirm the *CI* workflow ran green on `main`.
- **Settings → Code security:** enable *Private vulnerability reporting* (SECURITY.md relies on it), *Dependabot alerts* and *Secret scanning*.
- **Settings → Branches:** protect `main` (require the CI checks and one review).
- **About (gear icon):** add topics so people can find it, such as `agent-skills`, `claude-skills`, `power-platform`, `dataverse`, `power-automate`, `alm`, `github-actions`, `pac-cli`, `codex`, `github-copilot`, `cursor`, `gemini-cli`.

## 4. Publish the first release

1. On the repository page, select **Releases → Draft a new release**.
2. **Choose a tag:** type `v0.1.0` and select *Create new tag on publish* (target: `main`).
3. **Title:** `v0.1.0`. Select **Generate release notes**, edit them if you like, then **Publish release**.

The *Release* workflow then checks the tag matches `metadata.version` in `SKILL.md`, rebuilds, and attaches these files to the release within a couple of minutes:
- `power-platform-alm-toolkit.zip`
- `power-platform-alm-toolkit.md`
- `power-platform-alm-toolkit.instructions.md`
- `SHA256SUMS.txt`

## 5. Spread the word (optional)

- Check that `npx skills add NaveenGaneshe/power-platform-alm-toolkit-skill` finds the skill.
- Submit it to skill directories and "awesome" lists for Agent Skills, Claude Code and Power Platform.
- Share it in the Power Platform community forums and your CoE channels.

## Later releases

1. Change the skill, then update `CHANGELOG.md`.
2. Bump `metadata.version` in `skills/power-platform-alm-toolkit/SKILL.md`.
3. Publish a GitHub release tagged `vX.Y.Z` (as in step 4).
