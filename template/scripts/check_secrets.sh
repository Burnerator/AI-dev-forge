#!/usr/bin/env bash
# Secrets gate. Used by the pre-push hook and by CI.
#
# Usage: check_secrets.sh [<commit>...]
#   Scans every ref (git log --all) plus any extra commits given as arguments.
#   The pre-push hook passes the commits being pushed, so a commit that no local
#   ref points to is scanned too.
#
# What it checks:
#   0) the clone is not shallow (otherwise older history would go unchecked)
#   1) no .env file (only .env.example) in any scanned commit, merge commits included
#   2) gitleaks finds no secrets in any scanned commit, including changes that only
#      exist in a merge commit (conflict resolutions) and files git treats as binary.
#      Only a count and commit IDs are printed, never gitleaks' raw findings.
#   3) annotated tags (arguments and local refs/tags): no secrets in the message
#   4) every author, committer and tagger email is a GitHub noreply address
# What it cannot do: detect arbitrary personal data in file contents or commit
# messages. That still needs a human read of every diff before publishing.
set -euo pipefail

cd "$(dirname "$0")/.."
fail=0

# Read the real objects: replacement refs (git replace) would otherwise let the
# scan see substitute content while a push transfers the original commits.
export GIT_NO_REPLACE_OBJECTS=1

# A shallow clone stops at its boundary: older commits would go unchecked.
if [[ "$(git rev-parse --is-shallow-repository)" == "true" ]]; then
  echo "ERROR: shallow clone; the full history cannot be checked." >&2
  echo "Fix: git fetch --unshallow (in CI: actions/checkout with fetch-depth: 0)." >&2
  exit 1
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
# Every local annotated tag too: tags are pushed with --tags/--follow-tags.
while IFS= read -r obj; do
  [[ -n "$obj" ]] && tags+=("$obj")
done < <(git for-each-ref --format='%(if:equals=tag)%(objecttype)%(then)%(objectname)%(end)' refs/tags)

echo "==> .env files in history (incl. merge commits)"
# NUL-delimited paths: no quoting of special characters, so nothing can hide.
paths_file="$(mktemp)"
trap 'rm -f "$paths_file"' EXIT
# A failed git log must abort, never look like "no matches".
git log --all -m --name-only -z --format= ${revs[@]+"${revs[@]}"} >"$paths_file" \
  || { echo "ERROR: git log failed" >&2; exit 1; }
env_count=0
while IFS= read -r -d '' path; do
  [[ -z "$path" ]] && continue
  base="${path##*/}"
  if [[ "$base" == ".env" || ( "$base" == .env.* && "$base" != ".env.example" ) ]]; then
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
log_opts="--all -m --text"
[[ ${#revs[@]} -gt 0 ]] && log_opts+=" ${revs[*]}"
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
gl_out=$(gitleaks git --redact --no-banner --no-color --exit-code 3 --ignore-gitleaks-allow \
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
  tagger_emails+="$(sed -n 's/^tagger .*<\([^>]*\)>.*/\1/p' <<<"$body")"$'\n'
  t_status=0
  git cat-file tag "$obj" | gitleaks stdin --redact --no-banner --no-color --exit-code 3 \
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
identities=$(git log --all --format='%ae%n%ce' ${revs[@]+"${revs[@]}"}) || { echo "ERROR: git log failed" >&2; exit 1; }
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
