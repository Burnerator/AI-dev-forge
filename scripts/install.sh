#!/usr/bin/env bash
# Install AI-dev-forge rules, skills and MCP configs into a project.
#
# Usage: install.sh [--force] [--dry-run] <project-dir>
#
#   --force    overwrite files that already exist in the project
#   --dry-run  show what would be done without changing anything

set -euo pipefail

FORGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FORCE=0
DRY_RUN=0
TARGET=""

usage() {
  sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force) FORCE=1 ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    *)
      if [[ -n "$TARGET" ]]; then
        echo "Only one project directory can be given." >&2; exit 2
      fi
      TARGET="$1"
      ;;
  esac
  shift
done

if [[ -z "$TARGET" ]]; then
  usage >&2; exit 2
fi
if [[ ! -d "$TARGET" ]]; then
  echo "Not a directory: $TARGET" >&2; exit 1
fi
TARGET="$(cd "$TARGET" && pwd)"

if [[ "$TARGET" == "$FORGE_DIR" ]]; then
  echo "Refusing to install the forge into itself." >&2; exit 1
fi

run() {
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "  [dry-run] $*"
  else
    "$@"
  fi
}

# copy_file <src> <dest>: copy unless dest exists (or --force)
copy_file() {
  local src="$1" dest="$2"
  if [[ -e "$dest" && $FORCE -eq 0 ]]; then
    echo "  skip    ${dest#"$TARGET"/} (exists; use --force to overwrite)"
    return
  fi
  run mkdir -p "$(dirname "$dest")"
  run cp "$src" "$dest"
  echo "  write   ${dest#"$TARGET"/}"
}

echo "Installing AI-dev-forge into $TARGET"

echo "Rules, MCP configs and gates:"
for rel in AGENTS.md CLAUDE.md .mcp.json .vscode/mcp.json \
  .githooks/pre-push scripts/check.sh scripts/check_secrets.sh \
  .github/workflows/forge-gates.yml .github/pull_request_template.md; do
  copy_file "$FORGE_DIR/template/$rel" "$TARGET/$rel"
done

echo "Skills (.agents/skills):"
for skill_dir in "$FORGE_DIR"/skills/*/; do
  [[ -f "$skill_dir/SKILL.md" ]] || continue
  name="$(basename "$skill_dir")"
  dest="$TARGET/.agents/skills/$name"
  if [[ -e "$dest" && $FORCE -eq 0 ]]; then
    echo "  skip    .agents/skills/$name (exists; use --force to overwrite)"
    continue
  fi
  run rm -rf "$dest"
  run mkdir -p "$TARGET/.agents/skills"
  run cp -R "$skill_dir" "$dest"
  echo "  write   .agents/skills/$name"
done

echo "Claude Code skills link (.claude/skills -> ../.agents/skills):"
link="$TARGET/.claude/skills"
if [[ -L "$link" ]]; then
  echo "  ok      .claude/skills is already a symlink"
elif [[ -e "$link" ]]; then
  echo "  skip    .claude/skills exists and is not a symlink."
  echo "          Move its skills into .agents/skills, remove it, and re-run."
else
  run mkdir -p "$TARGET/.claude"
  if run ln -s ../.agents/skills "$link" 2>/dev/null; then
    echo "  link    .claude/skills"
  else
    echo "  warn    could not create symlink; copying skills instead"
    run cp -R "$TARGET/.agents/skills" "$link"
  fi
fi

cat <<'EOF'

Done. Next steps:
  1. Edit AGENTS.md: fill in the PROJECT sections (build/test commands, style).
  2. Put your real lint + test commands in scripts/check.sh (it fails until you do).
  3. Enable the hook in each clone: git config core.hooksPath .githooks
     (needs gitleaks: https://github.com/gitleaks/gitleaks#installing)
  4. Set GITHUB_PAT in your environment for the GitHub MCP server.
  5. Commit the new files, then protect main and require the forge-gates
     checks (see docs/enforcement.md in AI-dev-forge).
EOF
