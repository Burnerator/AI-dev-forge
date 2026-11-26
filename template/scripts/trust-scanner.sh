#!/usr/bin/env bash
# Pin the secrets scanner the pre-push hook trusts.
#
# Usage: scripts/trust-scanner.sh [--yes] <commit-or-ref>
#   Shows how the scanner (scripts/check_secrets.sh, .gitleaks.toml,
#   .gitleaksignore, and the files any of them link to) differs between the currently pinned commit and
#   <commit-or-ref>, asks for confirmation (unless --yes), and stores the full
#   commit ID in git config forge.trustedCommit. A pin never moves on fetch:
#   run this again, after reading the diff, to accept a new scanner version.
set -euo pipefail
export GIT_NO_REPLACE_OBJECTS=1

yes=0
if [[ "${1:-}" == "--yes" ]]; then yes=1; shift; fi
if [[ $# -ne 1 ]]; then
  sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//' >&2
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

# resolve <commit> <path>: print <path> and, if it is a symlink inside the tree,
# every path it leads to, so a change in the link target cannot hide behind an
# unchanged link.
normalize() {
  local IFS=/ part out=()
  # shellcheck disable=SC2086 # split on / is intended
  set -- $1
  for part in "$@"; do
    case "$part" in
      "" | .) ;;
      ..)
        if [[ ${#out[@]} -eq 0 ]]; then
          return 1 # climbs above the repository root
        fi
        unset 'out[${#out[@]}-1]'
        ;;
      *) out+=("$part") ;;
    esac
  done
  printf '%s\n' "${out[*]}"
}
resolve() {
  local commit="$1" path="$2" hops=0 mode target
  while [[ $hops -lt 10 ]]; do
    printf '%s\n' "$path"
    mode=$(git ls-tree "$commit" -- "$path" | awk '{print $1}')
    [[ "$mode" == "120000" ]] || return 0
    target=$(git cat-file -p "$commit:$path")
    [[ "$target" == /* ]] && { echo "ERROR: $path links outside the repository ($target)." >&2; return 1; }
    path=$(normalize "$(dirname "$path")/$target") || {
      echo "ERROR: $2 links outside the repository ($target)." >&2
      return 1
    }
    hops=$((hops + 1))
  done
  echo "ERROR: too many symlink hops from $2." >&2
  return 1
}

base_files=(scripts/check_secrets.sh .gitleaks.toml .gitleaksignore)
old=$(git config --get forge.trustedCommit || true)
files=()
for c in "$new" ${old:+"$old"}; do
  git cat-file -e "${c}^{commit}" 2>/dev/null || continue
  for f in "${base_files[@]}"; do
    # Command substitution, not process substitution, so a failure stops here
    # before anything is pinned.
    resolved=$(resolve "$c" "$f") || { echo "Not changed: cannot review $f at ${c:0:12}." >&2; exit 1; }
    while IFS= read -r r; do files+=("$r"); done <<<"$resolved"
  done
done
# Unique, order kept.
uniq_files=()
for f in "${files[@]}"; do
  [[ " ${uniq_files[*]-} " == *" $f "* ]] || uniq_files+=("$f")
done
files=("${uniq_files[@]}")
if [[ -n "$old" ]] && git cat-file -e "${old}^{commit}" 2>/dev/null; then
  if [[ "$old" == "$new" ]]; then
    echo "forge.trustedCommit is already ${new:0:12}."
    exit 0
  fi
  echo "Scanner changes from the pinned ${old:0:12} to ${new:0:12}:"
  git --no-pager diff --stat "$old" "$new" -- "${files[@]}"
  git --no-pager diff "$old" "$new" -- "${files[@]}"
else
  echo "Nothing pinned yet. Full scanner files at ${new:0:12} (links followed):"
  for f in "${files[@]}"; do
    git cat-file -e "$new:$f" 2>/dev/null || continue
    [[ "$(git ls-tree "$new" -- "$f" | awk '{print $1}')" == "120000" ]] && { echo "--- $f -> $(git cat-file -p "$new:$f")"; continue; }
    echo "--- $f"
    git --no-pager show "$new:$f"
  done
fi

if [[ $yes -eq 0 ]]; then
  read -r -p "Trust the scanner at ${new:0:12}? [y/N] " answer
  [[ "$answer" == "y" || "$answer" == "Y" ]] || { echo "Not changed."; exit 1; }
fi
git config forge.trustedCommit "$new"
echo "forge.trustedCommit = $new"
