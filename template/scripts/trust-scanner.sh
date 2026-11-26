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

# resolve <commit> <path>: print <path> and every path it leads to through
# symlinks, so a change in a link target cannot hide behind an unchanged link.
resolve() {
  # Walk the path one component at a time inside the commit's tree, following
  # symlinks wherever they appear (a link to a directory included). Prints every
  # path visited. Fails if a component is missing, a link leaves the tree, or
  # the walk does not end at a tracked regular file. Prints nothing (success)
  # only if the starting path does not exist at all.
  local commit="$1" start="$2" hops=0 done_path="" rest="$2" comp entry mode cand target
  while [[ -n "$rest" ]]; do
    comp="${rest%%/*}"
    if [[ "$rest" == */* ]]; then rest="${rest#*/}"; else rest=""; fi
    [[ -z "$comp" || "$comp" == "." ]] && continue
    if [[ "$comp" == ".." ]]; then
      if [[ -z "$done_path" ]]; then
        echo "ERROR: $start links outside the repository." >&2
        return 1
      fi
      [[ "$done_path" == */* ]] && done_path="${done_path%/*}" || done_path=""
      continue
    fi
    cand="${done_path:+$done_path/}$comp"
    entry="$(git ls-tree "$commit" -- "$cand")"
    if [[ -z "$entry" ]]; then
      if [[ "$cand" == "$start" && $hops -eq 0 ]]; then
        return 0 # the file simply does not exist (optional policy files)
      fi
      echo "ERROR: $start resolves through $cand, which is not tracked at ${commit:0:12}." >&2
      return 1
    fi
    mode="${entry%% *}"
    if [[ "$mode" == "120000" ]]; then
      hops=$((hops + 1))
      if [[ $hops -gt 20 ]]; then
        echo "ERROR: too many symlink hops from $start." >&2
        return 1
      fi
      printf '%s\n' "$cand"
      target="$(git cat-file -p "$commit:$cand")"
      if [[ "$target" == /* ]]; then
        echo "ERROR: $start links outside the repository ($target)." >&2
        return 1
      fi
      rest="$target${rest:+/$rest}" # relative to the link's directory, done_path
      continue
    fi
    done_path="$cand"
    if [[ -n "$rest" && "$mode" != "040000" ]]; then
      echo "ERROR: $start resolves through $cand, which is not a directory." >&2
      return 1
    fi
  done
  if [[ "$mode" != "100644" && "$mode" != "100755" ]]; then
    echo "ERROR: $start does not resolve to a tracked regular file." >&2
    return 1
  fi
  printf '%s\n' "$done_path"
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
    while IFS= read -r r; do [[ -n "$r" ]] && files+=("$r"); done <<<"$resolved"
  done
done
# The scanner itself must end at a tracked executable.
scanner_final="$(resolve "$new" scripts/check_secrets.sh | tail -1)"
if [[ "$(git ls-tree "$new" -- "$scanner_final" | awk '{print $1}')" != "100755" ]]; then
  echo "Not changed: scripts/check_secrets.sh at ${new:0:12} does not resolve to a tracked executable." >&2
  exit 1
fi
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
  # Literal text: no binary attribute, no external diff, no textconv can hide
  # or transform what the scanner really contains.
  git --no-pager -c diff.external= diff --no-ext-diff --no-textconv --text --stat "$old" "$new" -- "${files[@]}"
  git --no-pager -c diff.external= diff --no-ext-diff --no-textconv --text "$old" "$new" -- "${files[@]}"
else
  echo "Nothing pinned yet. Full scanner files at ${new:0:12} (links followed):"
  for f in "${files[@]}"; do
    git cat-file -e "$new:$f" 2>/dev/null || continue
    [[ "$(git ls-tree "$new" -- "$f" | awk '{print $1}')" == "120000" ]] && { echo "--- $f -> $(git cat-file -p "$new:$f")"; continue; }
    echo "--- $f"
    git cat-file -p "$new:$f" # raw blob, no filters
  done
fi

if [[ $yes -eq 0 ]]; then
  read -r -p "Trust the scanner at ${new:0:12}? [y/N] " answer
  [[ "$answer" == "y" || "$answer" == "Y" ]] || { echo "Not changed."; exit 1; }
fi
git config forge.trustedCommit "$new"
echo "forge.trustedCommit = $new"
