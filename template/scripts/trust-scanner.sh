#!/usr/bin/env bash
# Pin the secrets scanner the pre-push hook trusts.
#
# Usage: scripts/trust-scanner.sh [--yes] <commit-or-ref>
#   Shows how the scanner (scripts/check_secrets.sh, .gitleaks.toml,
#   .gitleaksignore) differs between the currently pinned commit and
#   <commit-or-ref>, asks for confirmation (unless --yes), and stores the full
#   commit ID in git config forge.trustedCommit. A pin never moves on fetch:
#   run this again, after reading the diff, to accept a new scanner version.
set -euo pipefail
export GIT_NO_REPLACE_OBJECTS=1

yes=0
if [[ "${1:-}" == "--yes" ]]; then yes=1; shift; fi
if [[ $# -ne 1 ]]; then
  sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//' >&2
  exit 2
fi

new=$(git rev-parse --verify --quiet "${1}^{commit}") || {
  echo "ERROR: not a commit: $1" >&2
  exit 1
}
if ! git cat-file -e "$new:scripts/check_secrets.sh" 2>/dev/null; then
  echo "ERROR: ${new:0:12} has no scripts/check_secrets.sh; nothing to trust." >&2
  exit 1
fi

files=(scripts/check_secrets.sh .gitleaks.toml .gitleaksignore)
old=$(git config --get forge.trustedCommit || true)
if [[ -n "$old" ]] && git cat-file -e "${old}^{commit}" 2>/dev/null; then
  if [[ "$old" == "$new" ]]; then
    echo "forge.trustedCommit is already ${new:0:12}."
    exit 0
  fi
  echo "Scanner changes from the pinned ${old:0:12} to ${new:0:12}:"
  git --no-pager diff --stat "$old" "$new" -- "${files[@]}"
  git --no-pager diff "$old" "$new" -- "${files[@]}"
else
  echo "Nothing pinned yet. Scanner files at ${new:0:12}:"
  git --no-pager show --stat --format='%h %s' "$new" -- "${files[@]}" | tail -n +2
  echo "Read them with: git show ${new:0:12}:scripts/check_secrets.sh"
fi

if [[ $yes -eq 0 ]]; then
  read -r -p "Trust the scanner at ${new:0:12}? [y/N] " answer
  [[ "$answer" == "y" || "$answer" == "Y" ]] || { echo "Not changed."; exit 1; }
fi
git config forge.trustedCommit "$new"
echo "forge.trustedCommit = $new"
