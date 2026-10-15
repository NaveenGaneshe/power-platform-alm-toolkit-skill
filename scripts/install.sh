#!/usr/bin/env bash
# Install the power-platform-alm-toolkit skill into one or more AI tools (macOS / Linux / WSL / Git Bash).
#
#   ./scripts/install.sh                          # interactive menu
#   ./scripts/install.sh --tool claude            # Claude Code, for your user
#   ./scripts/install.sh --tool agents --scope project   # .agents/skills in the current repo (Codex, Copilot, Cursor, Gemini CLI)
#   ./scripts/install.sh --tool all               # every supported tool, for your user
#   ./scripts/install.sh --uninstall --tool all
#
# Run it from a clone of this repository, or straight from GitHub:
#   curl -fsSL https://raw.githubusercontent.com/NaveenGaneshe/power-platform-alm-toolkit-skill/main/scripts/install.sh | bash -s -- --tool claude
set -euo pipefail

REPO_URL="${PP_SKILL_REPO_URL:-https://github.com/NaveenGaneshe/power-platform-alm-toolkit-skill.git}"
TOOLS=""
SCOPE="user"
UNINSTALL=0
FORCE=0

usage() {
  cat <<EOF
Usage: install.sh [--tool TOOL[,TOOL...]] [--scope user|project] [--force] [--uninstall]

TOOL is one of:
  claude    Claude Code                         user: ~/.claude/skills      project: .claude/skills
  agents    Shared folder read by Codex, GitHub Copilot, Cursor and Gemini CLI
                                                user: ~/.agents/skills      project: .agents/skills
  codex     OpenAI Codex (same folder as agents)
  copilot   GitHub Copilot                      user: ~/.copilot/skills     project: .github/skills
  cursor    Cursor                              user: ~/.cursor/skills      project: .cursor/skills
  gemini    Gemini CLI                          user: ~/.gemini/skills      project: .gemini/skills
  all       claude + agents (covers every tool above without duplicates)

Installs every skill under skills/ (currently: power-platform-alm-toolkit, pp-data-ops-agent, pp-governance-agent, pp-migration-agent, pp-integration-agent).
Claude apps (claude.ai / desktop / mobile) don't read local folders: upload the matching
dist/<skill-name>.zip instead.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tool|-t) TOOLS="$2"; shift 2 ;;
    --scope|-s) SCOPE="$2"; shift 2 ;;
    --uninstall) UNINSTALL=1; shift ;;
    --force|-f) FORCE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ "$SCOPE" != "user" && "$SCOPE" != "project" ]]; then
  echo "--scope must be 'user' or 'project'" >&2; exit 2
fi

if [[ -z "$TOOLS" ]]; then
  if [[ -t 0 ]]; then
    echo "Which AI tool should get the skill?"
    echo "  1) Claude Code"
    echo "  2) Codex / GitHub Copilot / Cursor / Gemini CLI (shared .agents folder)"
    echo "  3) All of the above"
    read -r -p "Choose 1-3 [3]: " choice
    case "${choice:-3}" in
      1) TOOLS="claude" ;;
      2) TOOLS="agents" ;;
      *) TOOLS="all" ;;
    esac
  else
    TOOLS="all"
  fi
fi

# Locate the skills/ folder: next to this script, or clone the repo to a temp dir.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || echo "")"
SKILLS_ROOT=""
if [[ -n "$SCRIPT_DIR" && -d "$SCRIPT_DIR/../skills" ]]; then
  SKILLS_ROOT="$(cd "$SCRIPT_DIR/../skills" && pwd)"
elif [[ "$UNINSTALL" -eq 0 ]]; then
  command -v git >/dev/null || { echo "git is required to download the skills." >&2; exit 1; }
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  echo "Downloading skills from $REPO_URL ..."
  git clone --depth 1 --quiet "$REPO_URL" "$TMP/repo"
  SKILLS_ROOT="$TMP/repo/skills"
  [[ -d "$SKILLS_ROOT" ]] || { echo "skills/ not found in downloaded repo." >&2; exit 1; }
fi

SKILL_NAMES=()
if [[ -n "$SKILLS_ROOT" ]]; then
  for d in "$SKILLS_ROOT"/*/; do
    [[ -f "$d/SKILL.md" ]] && SKILL_NAMES+=("$(basename "$d")")
  done
elif [[ "$UNINSTALL" -eq 1 ]]; then
  # Uninstall without a source checkout: fall back to the one skill name known at release time
  # plus any already-installed folder names, so --uninstall still works from a bare curl pipe.
  SKILL_NAMES=("power-platform-alm-toolkit" "pp-data-ops-agent" "pp-governance-agent" "pp-migration-agent" "pp-integration-agent")
fi

target_dir() {
  local tool="$1"
  if [[ "$SCOPE" == "user" ]]; then
    case "$tool" in
      claude) echo "$HOME/.claude/skills" ;;
      agents|codex) echo "$HOME/.agents/skills" ;;
      copilot) echo "$HOME/.copilot/skills" ;;
      cursor) echo "$HOME/.cursor/skills" ;;
      gemini) echo "$HOME/.gemini/skills" ;;
      *) return 1 ;;
    esac
  else
    case "$tool" in
      claude) echo "$PWD/.claude/skills" ;;
      agents|codex) echo "$PWD/.agents/skills" ;;
      copilot) echo "$PWD/.github/skills" ;;
      cursor) echo "$PWD/.cursor/skills" ;;
      gemini) echo "$PWD/.gemini/skills" ;;
      *) return 1 ;;
    esac
  fi
}

expanded=()
IFS=',' read -r -a requested <<< "$TOOLS"
for t in "${requested[@]}"; do
  t="$(echo "$t" | tr '[:upper:]' '[:lower:]' | xargs)"
  if [[ "$t" == "all" ]]; then expanded+=(claude agents); else expanded+=("$t"); fi
done

# Plain string instead of an associative array: macOS ships bash 3.2.
seen="|"
status=0
for tool in "${expanded[@]}"; do
  dir="$(target_dir "$tool")" || { echo "Unknown tool '$tool'. Run with --help." >&2; status=2; continue; }
  case "$seen" in *"|$dir|"*) continue ;; esac
  seen="$seen$dir|"
  for name in "${SKILL_NAMES[@]}"; do
    dest="$dir/$name"
    if [[ "$UNINSTALL" -eq 1 ]]; then
      if [[ -d "$dest" ]]; then rm -rf "$dest"; echo "Removed $dest"; else echo "Not installed at $dest"; fi
      continue
    fi
    src="$SKILLS_ROOT/$name"
    [[ -f "$src/SKILL.md" ]] || { echo "SKILL.md not found for $name." >&2; status=1; continue; }
    if [[ -d "$dest" && "$FORCE" -ne 1 ]]; then
      echo "Updating existing install at $dest"
    fi
    mkdir -p "$dir"
    rm -rf "$dest.tmp"
    cp -R "$src" "$dest.tmp"
    rm -rf "$dest"
    mv "$dest.tmp" "$dest"
    echo "Installed $name for $tool -> $dest"
  done
done

if [[ "$UNINSTALL" -eq 0 && "$status" -eq 0 ]]; then
  echo
  echo "Done. Restart your AI tool (or start a new session), then try:"
  echo "  \"Build a toolkit module that turns off all flows in the Invoicing solution before a release, with a test run first.\""
  echo "  \"How many contacts in my dev environment have no email address?\""
fi
exit "$status"
