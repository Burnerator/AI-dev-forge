#!/usr/bin/env bash
# Tests for scripts/install.sh. Plain bash, no framework.
set -euo pipefail
forge="$(cd "$(dirname "$0")/.." && pwd)"
install="$forge/scripts/install.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fails=0

# check <description> <command...>: passes when the command succeeds.
check() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then echo "  ok   $desc"; else echo "  FAIL $desc" >&2; fails=$((fails + 1)); fi
}
# refuses <description> <command...>: passes when the command fails.
refuses() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then echo "  FAIL $desc" >&2; fails=$((fails + 1)); else echo "  ok   $desc"; fi
}
snapshot() { (cd "$1" && find . -type f | LC_ALL=C sort | xargs shasum; find . -type l -exec readlink {} \;); }

expected=(AGENTS.md CLAUDE.md .mcp.json .vscode/mcp.json .githooks/pre-push
  scripts/check.sh scripts/check_secrets.sh .github/workflows/forge-gates.yml
  .github/pull_request_template.md .agents/skills/code-review/SKILL.md
  .agents/skills/commit-message/SKILL.md .agents/skills/open-pull-request/SKILL.md)

echo "fresh install"
p="$tmp/fresh"; mkdir "$p"
"$install" "$p" >/dev/null
for f in "${expected[@]}"; do check "creates $f" test -f "$p/$f"; done
check ".claude/skills is a symlink" test -L "$p/.claude/skills"
check ".claude/skills points to ../.agents/skills" test "$(readlink "$p/.claude/skills")" = ../.agents/skills
check "skills visible through the symlink" test -f "$p/.claude/skills/code-review/SKILL.md"
check "hook is executable" test -x "$p/.githooks/pre-push"
check "check.sh is executable" test -x "$p/scripts/check.sh"
check "check_secrets.sh is executable" test -x "$p/scripts/check_secrets.sh"
refuses "check.sh placeholder fails until configured" "$p/scripts/check.sh"

mkdir -p "$tmp/steps"; steps="$("$install" "$tmp/steps" | sed -n '/Next steps/,$p')"
check "next steps: bootstrap push comes before pinning" test "$(grep -n 'FORGE_BOOTSTRAP=1' <<<"$steps" | head -1 | cut -d: -f1)" -lt "$(grep -n 'trust-scanner.sh' <<<"$steps" | head -1 | cut -d: -f1)"

echo "idempotent"
before="$(snapshot "$p")"
out="$("$install" "$p")"
after="$(snapshot "$p")"
check "second run changes nothing" test "$before" = "$after"
check "second run reports skips" grep -q 'skip    AGENTS.md' <<<"$out"

echo "never overwrites"
p="$tmp/existing"; mkdir -p "$p/scripts"
echo "mine" > "$p/AGENTS.md"; echo "mine" > "$p/scripts/check.sh"
"$install" "$p" >/dev/null
check "keeps existing AGENTS.md" test "$(cat "$p/AGENTS.md")" = mine
check "keeps existing scripts/check.sh" test "$(cat "$p/scripts/check.sh")" = mine

echo "--force overwrites"
"$install" --force "$p" >/dev/null
check "AGENTS.md replaced" grep -q 'AI-dev-forge' "$p/AGENTS.md"

echo "--dry-run writes nothing"
p="$tmp/dry"; mkdir "$p"
"$install" --dry-run "$p" >/dev/null
check "directory still empty" test -z "$(ls -A "$p")"

echo "symlinks never redirect writes outside the project"
out_dir="$tmp/outside"; mkdir -p "$out_dir"
echo "sentinel" > "$out_dir/AGENTS.md"
p="$tmp/linked-parent"; mkdir "$p"; ln -s "$out_dir" "$p/scripts"
echo "mine" > "$p/AGENTS.md"
tree_before="$(snapshot "$p")"
refuses "rejects a symlinked parent directory" "$install" "$p"
refuses "rejects a symlinked parent directory with --force" "$install" --force "$p"
check "a refused install changes nothing in the project (preflight)" test "$(snapshot "$p")" = "$tree_before"
check "earlier files were not replaced before the refusal" test "$(cat "$p/AGENTS.md")" = mine
check "nothing written outside through the parent link" test "$(ls "$out_dir")" = AGENTS.md
p="$tmp/linked-file"; mkdir "$p"; ln -s "$out_dir/AGENTS.md" "$p/AGENTS.md"
"$install" "$p" >/dev/null
check "skips a symlinked destination" test -L "$p/AGENTS.md"
"$install" --force "$p" >/dev/null
check "--force replaces the link, not its target" test ! -L "$p/AGENTS.md"
check "link target untouched" test "$(cat "$out_dir/AGENTS.md")" = sentinel
p="$tmp/dangling"; mkdir "$p"; ln -s "$out_dir/new-file" "$p/CLAUDE.md"
"$install" "$p" >/dev/null
check "does not write through a dangling link" test ! -e "$out_dir/new-file"
p="$tmp/linked-agents"; mkdir "$p"; ln -s "$out_dir" "$p/.agents"
refuses "rejects a symlinked .agents directory" "$install" "$p"
check "no skills written outside" test ! -e "$out_dir/skills"

echo "--force keeps project-only files in a skill"
p="$tmp/skill-extra"; mkdir -p "$p/.agents/skills/code-review"
echo "ours" > "$p/.agents/skills/code-review/helper.sh"; echo "old" > "$p/.agents/skills/code-review/SKILL.md"
"$install" --force "$p" >/dev/null
check "project-only file kept" test "$(cat "$p/.agents/skills/code-review/helper.sh")" = ours
check "forge file updated" grep -q '^name: code-review' "$p/.agents/skills/code-review/SKILL.md"

echo "a symlink in place of a skill directory"
p="$tmp/skill-link"; mkdir -p "$p/.agents/skills" "$tmp/elsewhere"
echo "theirs" > "$tmp/elsewhere/SKILL.md"
ln -s "$tmp/elsewhere" "$p/.agents/skills/code-review"
"$install" "$p" >/dev/null
check "without --force the link is left alone" test -L "$p/.agents/skills/code-review"
"$install" --force "$p" >/dev/null
check "--force replaces the link with the real skill" test ! -L "$p/.agents/skills/code-review"
check "the replaced skill is the forge's" grep -q '^name: code-review' "$p/.agents/skills/code-review/SKILL.md"
check "the link target is untouched" test "$(cat "$tmp/elsewhere/SKILL.md")" = theirs

echo ".claude/skills link is verified"
p="$tmp/stale-link"; mkdir -p "$p/.claude"; ln -s /nonexistent/skills "$p/.claude/skills"
out="$("$install" "$p")"
check "warns about a link to somewhere else" grep -q "warn    .claude/skills links to '/nonexistent/skills'" <<<"$out"
check "leaves it alone without --force" test "$(readlink "$p/.claude/skills")" = /nonexistent/skills
"$install" --force "$p" >/dev/null
check "--force repoints the link" test "$(readlink "$p/.claude/skills")" = ../.agents/skills
check "skills visible after the repair" test -f "$p/.claude/skills/code-review/SKILL.md"

echo "preflight rejects wrong file types before writing"
p="$tmp/file-parent"; mkdir "$p"; echo "mine" > "$p/AGENTS.md"; echo "not a dir" > "$p/scripts"
tree_before="$(snapshot "$p")"
refuses "rejects a regular file where a directory is needed" "$install" --force "$p"
check "nothing changed (file parent)" test "$(snapshot "$p")" = "$tree_before"
p="$tmp/dir-slot"; mkdir -p "$p/CLAUDE.md"; echo "mine" > "$p/AGENTS.md"
tree_before="$(snapshot "$p")"
refuses "rejects a directory where a file is expected" "$install" --force "$p"
check "nothing changed (directory slot)" test "$(snapshot "$p")" = "$tree_before"

p="$tmp/skill-file"; mkdir -p "$p/.agents/skills"; echo "not a dir" > "$p/.agents/skills/code-review"; echo "mine" > "$p/AGENTS.md"
tree_before="$(snapshot "$p")"
refuses "rejects a file in place of a skill directory" "$install" --force "$p"
check "nothing changed (skill file)" test "$(snapshot "$p")" = "$tree_before"

p="$tmp/skill-conflict"; mkdir -p "$p/.agents/skills/code-review/SKILL.md"
check "without --force an existing skill is skipped, even with an internal conflict" "$install" "$p"
refuses "with --force the internal conflict is refused" "$install" --force "$p"

echo "refusals"
refuses "rejects missing directory" "$install" "$tmp/nope"
refuses "rejects installing into the forge" "$install" "$forge"
src_before="$(snapshot "$forge/template")"
refuses "rejects installing into a directory inside the forge" "$install" --force "$forge/template"
check "forge template left intact" test "$(snapshot "$forge/template")" = "$src_before"
refuses "rejects unknown option" "$install" --bogus "$tmp"

if [[ $fails -ne 0 ]]; then
  echo "$fails test(s) failed" >&2
  exit 1
fi
echo "all installer tests passed"
