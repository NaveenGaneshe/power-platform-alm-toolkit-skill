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

SKILL_NAME="power-platform-alm-toolkit"
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

Claude apps (claude.ai / desktop / mobile) don't read local folders: upload dist/${SKILL_NAME}.zip instead.
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

# Locate the skill source: next to this script, or clone the repo to a temp dir.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || echo "")"
SRC=""
if [[ -n "$SCRIPT_DIR" && -f "$SCRIPT_DIR/../skills/$SKILL_NAME/SKILL.md" ]]; then
  SRC="$(cd "$SCRIPT_DIR/../skills/$SKILL_NAME" && pwd)"
elif [[ "$UNINSTALL" -eq 0 ]]; then
  command -v git >/dev/null || { echo "git is required to download the skill." >&2; exit 1; }
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  echo "Downloading skill from $REPO_URL ..."
  git clone --depth 1 --quiet "$REPO_URL" "$TMP/repo"
  SRC="$TMP/repo/skills/$SKILL_NAME"
  [[ -f "$SRC/SKILL.md" ]] || { echo "SKILL.md not found in downloaded repo." >&2; exit 1; }
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
  dest="$dir/$SKILL_NAME"
  if [[ "$UNINSTALL" -eq 1 ]]; then
    if [[ -d "$dest" ]]; then rm -rf "$dest"; echo "Removed $dest"; else echo "Not installed at $dest"; fi
    continue
  fi
  if [[ -d "$dest" && "$FORCE" -ne 1 ]]; then
    echo "Updating existing install at $dest"
  fi
  mkdir -p "$dir"
  rm -rf "$dest.tmp"
  cp -R "$SRC" "$dest.tmp"
  rm -rf "$dest"
  mv "$dest.tmp" "$dest"
  echo "Installed for $tool -> $dest"
done

if [[ "$UNINSTALL" -eq 0 && "$status" -eq 0 ]]; then
  echo
  echo "Done. Restart your AI tool (or start a new session), then try:"
  echo "  \"Build a toolkit module that turns off all flows in the Invoicing solution before a release, with a test run first.\""
fi
exit "$status"
