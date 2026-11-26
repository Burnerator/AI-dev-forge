#!/usr/bin/env bash
# Install AI-dev-forge rules, skills and MCP configs into a project.
#
# Usage: install.sh [--force] [--dry-run] <project-dir>
#
#   --force    overwrite files that already exist in the project
#   --dry-run  show what would be done without changing anything

set -euo pipefail

FORGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
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
TARGET="$(cd "$TARGET" && pwd -P)"

# Refuse the forge itself or anything inside it (e.g. template/), before any change.
if [[ "$TARGET/" == "$FORGE_DIR/"* ]]; then
  echo "Refusing to install the forge into itself or into a directory inside it." >&2; exit 1
fi

run() {
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "  [dry-run] $*"
  else
    "$@"
  fi
}

# safe_parents <dest>: refuse if any existing directory between the project root
# and <dest> is a symlink, so no write can be redirected outside the project.
safe_parents() {
  local rel="${1#"$TARGET"/}" path="$TARGET" part
  local IFS=/
  # shellcheck disable=SC2086 # word splitting on / is intended
  set -- $rel
  while [[ $# -gt 1 ]]; do
    part="$1"; shift
    path="$path/$part"
    if [[ -L "$path" ]]; then
      echo "ERROR: ${path#"$TARGET"/} is a symlink; refusing to write through it." >&2
      echo "       Replace it with a real directory and re-run." >&2
      exit 1
    fi
    if [[ -e "$path" && ! -d "$path" ]]; then
      echo "ERROR: ${path#"$TARGET"/} exists and is not a directory; nothing was installed." >&2
      exit 1
    fi
  done
}

# file_slot <dest>: the destination of a file must not be a real directory.
file_slot() {
  safe_parents "$1"
  if [[ -d "$1" && ! -L "$1" ]]; then
    echo "ERROR: ${1#"$TARGET"/} is a directory where a file is expected; nothing was installed." >&2
    exit 1
  fi
}

# copy_file <src> <dest>: copy unless dest exists (or --force). Never follows a
# symlink at dest: without --force it is skipped, with --force the link itself
# is replaced by a regular file.
copy_file() {
  local src="$1" dest="$2"
  safe_parents "$dest"
  if [[ -e "$dest" || -L "$dest" ]]; then
    if [[ $FORCE -eq 0 ]]; then
      echo "  skip    ${dest#"$TARGET"/} (exists; use --force to overwrite)"
      return
    fi
    run rm -f "$dest"
  fi
  run mkdir -p "$(dirname "$dest")"
  run cp "$src" "$dest"
  echo "  write   ${dest#"$TARGET"/}"
}

# Preflight: check every destination before writing anything, so a refusal
# (for example a symlinked directory) never leaves a half-installed project.
rules=(AGENTS.md CLAUDE.md .mcp.json .vscode/mcp.json
  .githooks/pre-push scripts/check.sh scripts/check_secrets.sh scripts/trust-scanner.sh
  .github/workflows/forge-gates.yml .github/pull_request_template.md)
for rel in "${rules[@]}"; do file_slot "$TARGET/$rel"; done
for skill_dir in "$FORGE_DIR"/skills/*/; do
  [[ -f "$skill_dir/SKILL.md" ]] || continue
  name="$(basename "$skill_dir")"
  safe_parents "$TARGET/.agents/skills/$name"
  root="$TARGET/.agents/skills/$name"
  if [[ -e "$root" && ! -d "$root" && ! -L "$root" ]]; then
    echo "ERROR: .agents/skills/$name exists and is not a directory; nothing was installed." >&2
    exit 1
  fi
  # Without --force an existing skill is skipped as a whole, so preflight skips it too.
  if [[ ( -e "$root" || -L "$root" ) && $FORCE -eq 0 ]]; then
    continue
  fi
  if [[ ! -L "$root" ]]; then
    while IFS= read -r -d '' src; do
      file_slot "$TARGET/.agents/skills/$name/${src#"$skill_dir"}"
    done < <(find "$skill_dir" -type f -print0)
  fi
done
safe_parents "$TARGET/.claude/skills"

echo "Installing AI-dev-forge into $TARGET"

echo "Rules, MCP configs and gates:"
for rel in "${rules[@]}"; do
  copy_file "$FORGE_DIR/template/$rel" "$TARGET/$rel"
done

echo "Skills (.agents/skills):"
for skill_dir in "$FORGE_DIR"/skills/*/; do
  [[ -f "$skill_dir/SKILL.md" ]] || continue
  name="$(basename "$skill_dir")"
  dest="$TARGET/.agents/skills/$name"
  safe_parents "$dest" # ancestors only; a link at $dest itself is handled below
  if [[ ( -e "$dest" || -L "$dest" ) && $FORCE -eq 0 ]]; then
    echo "  skip    .agents/skills/$name (exists; use --force to overwrite)"
    continue
  fi
  # Overwrite the forge's files, keep any project-only files in the skill.
  if [[ -L "$dest" ]]; then
    run rm -f "$dest" # a link in place of the skill: replace the link itself
  fi
  while IFS= read -r -d '' src; do
    rel="${src#"$skill_dir"}"
    copy_file "$src" "$dest/$rel" >/dev/null
  done < <(find "$skill_dir" -type f -print0)
  echo "  write   .agents/skills/$name"
done

echo "Claude Code skills link (.claude/skills -> ../.agents/skills):"
link="$TARGET/.claude/skills"
safe_parents "$link"
if [[ -L "$link" && "$(readlink "$link")" == "../.agents/skills" ]]; then
  echo "  ok      .claude/skills already links to ../.agents/skills"
elif [[ -L "$link" ]]; then
  if [[ $FORCE -eq 1 ]]; then
    old_target="$(readlink "$link")"
    run rm -f "$link"
    run ln -s ../.agents/skills "$link"
    echo "  link    .claude/skills (replaced a link to '$old_target')"
  else
    echo "  warn    .claude/skills links to '$(readlink "$link")', not ../.agents/skills."
    echo "          Claude Code will not see the forge skills. Re-run with --force to fix the link."
  fi
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
     and pin the scanner it trusts (after reading it):
     scripts/trust-scanner.sh refs/remotes/origin/main
     (needs gitleaks: https://github.com/gitleaks/gitleaks#installing)
  4. Set GITHUB_PAT in your environment for the GitHub MCP server.
  5. Commit the new files, then protect main and require the forge-gates
     checks (see docs/enforcement.md in AI-dev-forge).
EOF
