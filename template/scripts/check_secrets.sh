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
#      exist in a merge commit (conflict resolutions)
#   3) every author/committer email is a GitHub noreply address
# What it cannot do: detect arbitrary personal data in file contents or commit
# messages. That still needs a human read of every diff before publishing.
set -euo pipefail

cd "$(dirname "$0")/.."
fail=0

# A shallow clone stops at its boundary: older commits would go unchecked.
if [[ "$(git rev-parse --is-shallow-repository)" == "true" ]]; then
  echo "ERROR: shallow clone; the full history cannot be checked." >&2
  echo "Fix: git fetch --unshallow (in CI: actions/checkout with fetch-depth: 0)." >&2
  exit 1
fi

revs=()
for rev in "$@"; do
  sha=$(git rev-parse --verify --quiet "${rev}^{commit}") || {
    echo "ERROR: not a commit: $rev" >&2
    exit 1
  }
  revs+=("$sha")
done

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

echo "==> gitleaks (full history, merge diffs included)"
if ! command -v gitleaks >/dev/null 2>&1; then
  echo "ERROR: gitleaks not installed (https://github.com/gitleaks/gitleaks#installing). Refusing to continue." >&2
  exit 1
fi
# Default gitleaks log options skip merge diffs; -m adds them.
log_opts="--all -m"
[[ ${#revs[@]} -gt 0 ]] && log_opts+=" ${revs[*]}"
gl_status=0
gl_out=$(gitleaks git --redact --no-banner --log-opts="$log_opts" . 2>&1) || gl_status=$?
printf '%s\n' "$gl_out"
# Fail closed: a gitleaks error, or zero commits scanned in a repo that has
# history, must never pass as "no leaks found".
if grep -q 'ERR' <<<"$gl_out"; then
  echo "ERROR: gitleaks reported an error; the scan cannot be trusted." >&2
  fail=1
elif git rev-parse --verify --quiet HEAD >/dev/null && grep -qE '(^|[^0-9])0 commits scanned' <<<"$gl_out"; then
  echo "ERROR: gitleaks scanned 0 commits; the scan cannot be trusted." >&2
  fail=1
elif [[ $gl_status -ne 0 ]]; then
  echo "ERROR: gitleaks found secrets. Revoke the key at the provider, then clean history." >&2
  fail=1
fi

echo "==> commit identities"
identities=$(git log --all --format='%ae%n%ce' ${revs[@]+"${revs[@]}"}) || { echo "ERROR: git log failed" >&2; exit 1; }
bad=$(printf '%s\n' "$identities" | sort -u \
  | grep -vE '^([0-9]+\+)?[A-Za-z0-9-]+(\[bot\])?@users\.noreply\.github\.com$|^noreply@github\.com$' || true)
if [[ -n "$bad" ]]; then
  # Do not print the addresses: CI logs of public repos are public.
  echo "ERROR: $(echo "$bad" | wc -l | tr -d ' ') non-noreply email(s) in commit metadata (not shown)." >&2
  echo "Inspect locally: git log --all --format='%h %ae %ce'" >&2
  echo "Fix: git config user.email '<id>+<login>@users.noreply.github.com' and rewrite." >&2
  fail=1
fi

if [[ $fail -ne 0 ]]; then
  exit 1
fi
echo "==> OK: no .env in history, no gitleaks findings, only noreply identities"
