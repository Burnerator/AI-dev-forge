#!/usr/bin/env bash
# Secrets gate. Used by the pre-push hook and by CI.
#
# Usage: check_secrets.sh [<commit-or-tag>...]
#        check_secrets.sh --only <commit-or-tag>...
#   Default: scans every local ref (git log --all, local tags included) plus the
#   given revisions. The pre-push hook uses this, passing the pushed commits, so
#   a commit that no local ref points to is scanned too.
#        check_secrets.sh --tag <tag-ref> <expected-object-id>
#   --only: scans just the history of the given revisions (and the given tags).
#   --tag: CI on a tag push. Verifies that <tag-ref> still resolves to the exact
#   object the push event reported (a moved tag fails), then scans it as --only.
#   CI uses this, so a required check depends only on the commit under test,
#   not on unrelated branches or tags of the repository.
#
# What it checks:
#   0) the clone is not shallow (otherwise older history would go unchecked)
#   1) no .env, .env.* (except .env.example) or .envrc file, at any depth, in any
#      scanned commit, merge and root commits included
#   2) gitleaks finds no secrets in any scanned commit, including changes that only
#      exist in a merge commit (conflict resolutions) and files git treats as binary.
#      Only a count and commit IDs are printed, never gitleaks' raw findings.
#   3) no secrets in commit messages (gitleaks only reads patches)
#   3b) annotated tags (arguments and, by default, local refs/tags): no secrets in the message
#   4) every author, committer and tagger email is a GitHub noreply address
# What it cannot do: detect arbitrary personal data in file contents or commit
# messages. That still needs a human read of every diff before publishing.
set -euo pipefail

cd "$(dirname "$0")/.."
fail=0

# Read the real objects: replacement refs (git replace) would otherwise let the
# scan see substitute content while a push transfers the original commits.
export GIT_NO_REPLACE_OBJECTS=1
# Legacy grafts (.git/info/grafts) could rewrite the ancestry the scans walk
# while a push still sends the real history: ignore them.
export GIT_GRAFT_FILE=/nonexistent/forge-ignores-grafts # a path that never exists; /dev/null would count as a graft file
# The scanner policy is the reviewed one in this checkout or gitleaks' built-in
# rules, never an override inherited from the environment.
unset GITLEAKS_CONFIG GITLEAKS_CONFIG_TOML
# Scanner policy files must be regular files: a link would let a change to its
# target, outside the Code Owner paths, alter the policy unreviewed.
for f in .gitleaks.toml .gitleaksignore; do
  if [[ -L "$f" ]]; then
    echo "ERROR: $f is a symlink; scanner policy files must be regular files." >&2
    exit 1
  fi
done
# policy_uses_extend_path <file>: parse the TOML for real (tomllib, Python
# 3.11+) and succeed if it sets extend.path in any spelling. Exit 2 when no
# parser is available: the caller fails closed.
policy_uses_extend_path() {
  local py
  for py in python3 python3.14 python3.13 python3.12 python3.11; do
    command -v "$py" >/dev/null 2>&1 || continue
    "$py" -I -c 'import tomllib' 2>/dev/null || continue
    "$py" -I -c '
import sys, tomllib
try:
    data = tomllib.load(open(sys.argv[1], "rb"))
except Exception as exc:
    print(f"invalid TOML: {exc}", file=sys.stderr)
    sys.exit(3)
ext = data.get("extend")
sys.exit(0 if isinstance(ext, dict) and "path" in ext else 1)' "$1"
    return $?
  done
  return 2
}
# No extend.path: rules or allowlists loaded from another file would escape
# the pin review and the Code Owner paths. [extend] useDefault is fine.
if [[ -f .gitleaks.toml ]]; then
  ep_status=0
  policy_uses_extend_path .gitleaks.toml || ep_status=$?
  case $ep_status in
    0) echo "ERROR: .gitleaks.toml uses [extend] path; keep the whole policy in .gitleaks.toml." >&2; exit 1 ;;
    1) ;;
    2) echo "ERROR: .gitleaks.toml needs Python 3.11+ (tomllib) to be validated; refusing to scan with an unchecked policy." >&2; exit 1 ;;
    *) echo "ERROR: .gitleaks.toml is not valid TOML." >&2; exit 1 ;;
  esac
fi
gl_config=()
[[ -f .gitleaks.toml ]] && gl_config=(--config "$PWD/.gitleaks.toml")

# A shallow clone stops at its boundary: older commits would go unchecked.
if [[ "$(git rev-parse --is-shallow-repository)" == "true" ]]; then
  echo "ERROR: shallow clone; the full history cannot be checked." >&2
  echo "Fix: git fetch --unshallow (in CI: actions/checkout with fetch-depth: 0)." >&2
  exit 1
fi

scope=(--all)
if [[ "${1:-}" == "--tag" ]]; then
  if [[ $# -ne 3 ]]; then
    echo "ERROR: --tag needs <tag-ref> <expected-object-id>." >&2
    exit 1
  fi
  actual=$(GIT_NO_REPLACE_OBJECTS=1 git rev-parse --verify --quiet "$2") || {
    echo "ERROR: tag $2 is not available in this checkout." >&2
    exit 1
  }
  if [[ "$actual" != "$3" ]]; then
    echo "ERROR: tag $2 now points to ${actual:0:12}, not ${3:0:12} from the push event (moved?)." >&2
    exit 1
  fi
  set -- --only "$3"
fi
if [[ "${1:-}" == "--only" ]]; then
  shift
  scope=()
  if [[ $# -eq 0 ]]; then
    echo "ERROR: --only needs at least one revision." >&2
    exit 1
  fi
fi

revs=()
tags=() # annotated tag objects among the arguments
for rev in "$@"; do
  sha=$(git rev-parse --verify --quiet "${rev}^{commit}") || {
    echo "ERROR: not a commit: $rev" >&2
    exit 1
  }
  revs+=("$sha")
  obj=$(git rev-parse --verify --quiet "$rev")
  [[ "$(git cat-file -t "$obj")" == "tag" ]] && tags+=("$obj")
done
# Every local annotated tag too (default scope): tags are pushed with --tags/--follow-tags.
if [[ ${#scope[@]} -gt 0 ]]; then
  while IFS= read -r obj; do
    [[ -n "$obj" ]] && tags+=("$obj")
  done < <(git for-each-ref --format='%(if:equals=tag)%(objecttype)%(then)%(objectname)%(end)' refs/tags)
fi

echo "==> .env files in history (incl. merge commits)"
# NUL-delimited paths: no quoting of special characters, so nothing can hide.
paths_file="$(mktemp)"
trap 'rm -f "$paths_file"' EXIT
# A failed git log must abort, never look like "no matches".
# --root: show what the root commit adds, whatever log.showRoot says.
git log ${scope[@]+"${scope[@]}"} --root -m --name-only -z --format= ${revs[@]+"${revs[@]}"} >"$paths_file" \
  || { echo "ERROR: git log failed" >&2; exit 1; }
env_count=0
while IFS= read -r -d '' path; do
  [[ -z "$path" ]] && continue
  base="${path##*/}"
  # Policy: .env, .env.<anything> except .env.example, and .envrc (direnv), at
  # any depth.
  if [[ "$base" == ".env" || "$base" == ".envrc" || ( "$base" == .env.* && "$base" != ".env.example" ) ]]; then
    env_count=$((env_count + 1))
  fi
done <"$paths_file"
if [[ $env_count -gt 0 ]]; then
  echo "ERROR: .env file(s) present in git history: $env_count occurrence(s)." >&2
  echo "Fix: remove from history before publishing, and revoke any key it contained." >&2
  fail=1
fi

echo "==> gitleaks (full history, merge diffs and binary files included)"
if ! command -v gitleaks >/dev/null 2>&1; then
  echo "ERROR: gitleaks not installed (https://github.com/gitleaks/gitleaks#installing). Refusing to continue." >&2
  exit 1
fi
# -m: include merge diffs (default gitleaks log options skip them).
# --text: include the contents of files git classifies as binary.
# Built without stray spaces: gitleaks splits this string, and an empty word
# becomes an empty pathspec that makes git log scan nothing.
# --no-textconv/--no-ext-diff: scan the stored bytes, never a diff driver's view.
log_words=(${scope[@]+"${scope[@]}"} --root -m --text --no-textconv --no-ext-diff ${revs[@]+"${revs[@]}"})
log_opts="${log_words[*]}"
report="$(mktemp)"
trap 'rm -f "$paths_file" "$report"' EXIT
gl_status=0
# Exit code 3 means "findings"; anything else nonzero is an operational error.
# Raw gitleaks output is never printed: findings carry author names, emails and
# paths, and CI logs of public repositories are public.
# --ignore-gitleaks-allow: inline "gitleaks:allow" comments in the scanned code
# never suppress a finding. .gitleaksignore and .gitleaks.toml are read from the
# checkout this script runs in: in the hook that is the trusted revision; in CI
# they need required Code Owner review (docs/enforcement.md).
gl_out=$(gitleaks git ${gl_config[@]+"${gl_config[@]}"} --redact --no-banner --no-color --exit-code 3 --ignore-gitleaks-allow \
  --report-format json --report-path "$report" --log-opts="$log_opts" . 2>&1) || gl_status=$?
scanned=$(grep -oE '[0-9]+ commits scanned' <<<"$gl_out" | head -1 || true)
echo "    ${scanned:-commit count unknown}"
# Fail closed: a gitleaks error, or zero commits scanned in a repo that has
# history, must never pass as "no leaks found". gitleaks exits 0 on some git errors.
if [[ $gl_status -ne 0 && $gl_status -ne 3 ]] || grep -q 'ERR' <<<"$gl_out"; then
  echo "ERROR: gitleaks failed to run (exit $gl_status); the scan cannot be trusted." >&2
  echo "Run it locally to see why: gitleaks git -v --log-opts=\"$log_opts\" ." >&2
  fail=1
elif git rev-parse --verify --quiet HEAD >/dev/null && [[ "$scanned" == "0 commits scanned" || -z "$scanned" ]]; then
  echo "ERROR: gitleaks scanned no commits; the scan cannot be trusted." >&2
  fail=1
elif [[ $gl_status -eq 3 ]]; then
  findings=$(grep -c '"RuleID"' "$report" || true)
  echo "ERROR: gitleaks found $findings secret(s). Commits (details not shown, CI logs may be public):" >&2
  grep -oE '"Commit": *"[0-9a-f]+"' "$report" | grep -oE '[0-9a-f]{40}' | sort -u | cut -c1-12 | sed 's/^/  /' >&2
  echo "Inspect locally: gitleaks git -v --log-opts=\"$log_opts\" ." >&2
  echo "Fix: revoke the key at the provider first, then clean history." >&2
  fail=1
fi

echo "==> commit messages"
# gitleaks reads patches, not commit messages, so scan the messages separately.
msg_status=0
git log ${scope[@]+"${scope[@]}"} --format='%B%x00' ${revs[@]+"${revs[@]}"} \
  | gitleaks stdin ${gl_config[@]+"${gl_config[@]}"} --redact --no-banner --no-color --exit-code 3 --ignore-gitleaks-allow \
    --report-format json --report-path "$report" >/dev/null 2>&1 || msg_status=$?
if [[ $msg_status -eq 3 ]]; then
  echo "ERROR: commit messages contain $(grep -c '"RuleID"' "$report" || true) secret(s) (not shown)." >&2
  echo "Inspect locally: git log --format='%h %s' | gitleaks stdin -v" >&2
  echo "Fix: revoke the key at the provider first, then reword the commit." >&2
  fail=1
elif [[ $msg_status -ne 0 ]]; then
  echo "ERROR: gitleaks failed on commit messages (exit $msg_status); the scan cannot be trusted." >&2
  fail=1
fi

echo "==> annotated tags (messages and tagger identities, nested tags included)"
# A tag can point to another tag; git transfers the whole chain, so follow it.
all_tags=()
for obj in ${tags[@]+"${tags[@]}"}; do
  while [[ "$(git cat-file -t "$obj")" == "tag" ]]; do
    all_tags+=("$obj")
    obj="$(git cat-file tag "$obj" | sed -n 's/^object //p' | head -1)"
  done
done
tag_leaks=0
tagger_emails=""
while IFS= read -r obj; do
  [[ -z "$obj" ]] && continue
  body="$(git cat-file tag "$obj")"
  # Header block only (up to the first blank line): the message may contain
  # lines that look like headers.
  tagger_emails+="$(sed -n '/^$/q; s/^tagger .*<\([^>]*\)>.*/\1/p' <<<"$body")"$'\n'
  t_status=0
  git cat-file tag "$obj" | gitleaks stdin ${gl_config[@]+"${gl_config[@]}"} --redact --no-banner --no-color --exit-code 3 \
    --ignore-gitleaks-allow >/dev/null 2>&1 || t_status=$?
  if [[ $t_status -eq 3 ]]; then
    tag_leaks=$((tag_leaks + 1))
  elif [[ $t_status -ne 0 ]]; then
    echo "ERROR: gitleaks failed on tag ${obj:0:12} (exit $t_status)." >&2
    fail=1
  fi
done < <(printf '%s\n' ${all_tags[@]+"${all_tags[@]}"} | sort -u)
if [[ $tag_leaks -gt 0 ]]; then
  echo "ERROR: $tag_leaks annotated tag(s) contain secrets in their message." >&2
  fail=1
fi

echo "==> commit and tagger identities"
identities=$(git log ${scope[@]+"${scope[@]}"} --format='%ae%n%ce' ${revs[@]+"${revs[@]}"}) || { echo "ERROR: git log failed" >&2; exit 1; }
identities+=$'\n'"$tagger_emails"
bad=$(printf '%s\n' "$identities" | sort -u \
  | grep -v '^$' \
  | grep -vE '^([0-9]+\+)?[A-Za-z0-9-]+(\[bot\])?@users\.noreply\.github\.com$|^noreply@github\.com$' || true)
if [[ -n "$bad" ]]; then
  # Do not print the addresses: CI logs of public repos are public.
  echo "ERROR: $(echo "$bad" | wc -l | tr -d ' ') non-noreply email(s) in commit or tag metadata (not shown)." >&2
  echo "Inspect locally: git log --all --format='%h %ae %ce'; git for-each-ref refs/tags --format='%(refname) %(taggeremail)'" >&2
  echo "Fix: git config user.email '<id>+<login>@users.noreply.github.com' and rewrite." >&2
  fail=1
fi

if [[ $fail -ne 0 ]]; then
  exit 1
fi
echo "==> OK: no .env in history, no gitleaks findings, only noreply identities"
