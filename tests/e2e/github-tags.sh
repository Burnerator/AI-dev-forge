#!/usr/bin/env bash
# End-to-end smoke test of the forge-gates tag path on real GitHub Actions.
# Not run in CI: it needs a disposable repository and pushes to it.
#
# Usage: tests/e2e/github-tags.sh <owner/disposable-repo>
#   The repository must exist and be EMPTY (no branches, no tags): the script
#   refuses anything else, and only creates refs of its own (main and tags
#   with a per-run suffix). Use a fresh disposable repository for every run.
#   Needs gh (authenticated), git and network access.
#   Synthetic values only: a random ghp_-shaped token, example.com email.
#
# Expected: lightweight and clean annotated tags pass; a tag with a token in its
# message and a tag with a personal tagger email fail for those reasons; a tag
# moved right after its push fails its first run as "moved".
set -euo pipefail
repo="${1:?usage: $0 <owner/disposable-repo>}"
forge="$(cd "$(dirname "$0")/../.." && pwd -P)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cd "$work"

git init -q -b main
git config user.name "forge e2e"
git config user.email "1+forge-e2e@users.noreply.github.com"
"$forge/scripts/install.sh" . >/dev/null
printf '#!/usr/bin/env bash\necho "checks ok"\n' > scripts/check.sh
git add -A && git commit -qm "chore: forge e2e fixture"
git remote add origin "https://github.com/$repo.git"
if [[ -n "$(git ls-remote origin)" ]]; then
  echo "ERROR: $repo is not empty; this test only runs against a fresh, empty repository." >&2
  exit 1
fi
started="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
run_id="$(date -u +%Y%m%d%H%M%S)-$$"
git push -q origin main

token="ghp_$(od -An -tx1 -N18 /dev/urandom | tr -d ' \n')"
git tag "e2e-light-$run_id"
git tag -a "e2e-annotated-$run_id" -m "clean annotated release"
git tag -a "e2e-secret-$run_id" -m "release notes token $token"
git -c user.email=someone@example.com tag -a "e2e-email-$run_id" -m "personal tagger"
# The first object violates the policy (personal tagger); the replacement is clean.
git -c user.email=someone@example.com tag -a "e2e-moved-$run_id" -m "first object"
for t in "e2e-light-$run_id" "e2e-annotated-$run_id" "e2e-secret-$run_id" "e2e-email-$run_id" "e2e-moved-$run_id"; do git push -q origin "refs/tags/$t"; done
first_moved="$(git rev-parse "e2e-moved-$run_id")"
git tag -f -a "e2e-moved-$run_id" -m "second object" >/dev/null
git push -q --force origin "refs/tags/e2e-moved-$run_id"

echo "waiting for workflow runs..."
expected_runs=6 # 5 tag pushes + the moved tag pushed again
deadline=$(( $(date +%s) + 900 )) # 15 minutes
until [[ "$(gh run list -R "$repo" --limit 50 --json headBranch,createdAt -q "[.[]|select((.headBranch|endswith(\"-$run_id\")) and .createdAt >= \"$started\")]|length")" -ge $expected_runs ]] \
  && [[ "$(gh run list -R "$repo" --json status -q '[.[]|select(.status!="completed")]|length')" == 0 ]]; do
  if [[ $(date +%s) -gt $deadline ]]; then
    echo "ERROR: workflow runs did not complete within 15 minutes." >&2
    exit 1
  fi
  sleep 10
done

fails=0
expect() { # expect <tag> <success|failure> [diagnostic]: at least one run of <tag> matches
  local tag="$1" want="$2" pattern="${3:-}" ids id ok=0
  # Only runs created by this invocation.
  ids="$(gh run list -R "$repo" --limit 50 --json headBranch,databaseId,conclusion,createdAt \
    -q ".[]|select(.headBranch==\"$tag\" and .createdAt >= \"$started\")|\"\(.databaseId) \(.conclusion)\"")"
  while read -r id concl; do
    [[ -z "$id" ]] && continue
    if [[ "$concl" == "$want" ]]; then
      # gh run view can hang while fetching logs: cap it (perl is on macOS and Linux).
      if [[ -z "$pattern" ]] || perl -e 'alarm 90; exec @ARGV' gh run view "$id" -R "$repo" --log-failed 2>/dev/null | grep -qE "$pattern"; then ok=1; fi
    fi
  done <<<"$ids"
  if [[ $ok -eq 1 ]]; then echo "  ok   $tag: $want${pattern:+ ($pattern)}"; else echo "  FAIL $tag: expected $want${pattern:+ ($pattern)}" >&2; fails=$((fails + 1)); fi
}
runs_of() { gh run list -R "$repo" --limit 50 --json headBranch,createdAt -q "[.[]|select(.headBranch==\"$1\" and .createdAt >= \"$started\")]|length"; }
count() { # count <tag> <n>: exactly n runs of this invocation's tag
  if [[ "$(runs_of "$1")" == "$2" ]]; then echo "  ok   $1: $2 run(s)"; else echo "  FAIL $1: expected $2 run(s), got $(runs_of "$1")" >&2; fails=$((fails + 1)); fi
}
for t in "e2e-light-$run_id" "e2e-annotated-$run_id" "e2e-secret-$run_id" "e2e-email-$run_id"; do count "$t" 1; done
count "e2e-moved-$run_id" 2
expect "e2e-light-$run_id" success
expect "e2e-annotated-$run_id" success
expect "e2e-secret-$run_id" failure "annotated tag\\(s\\) contain secrets"
expect "e2e-email-$run_id" failure "non-noreply email"
# Moved tag: whether the first runner fetches before or after the move is not
# under our control, so tell the two runs apart by the object their event
# reported. The run for the first (violating) object must fail, either for the
# personal email or as moved; the run for the clean replacement must pass.
second_moved="$(git rev-parse "e2e-moved-$run_id")"
moved_runs="$(gh run list -R "$repo" --limit 50 --json headBranch,databaseId,conclusion,createdAt \
  -q ".[]|select(.headBranch==\"e2e-moved-$run_id\" and .createdAt >= \"$started\")|\"\(.databaseId) \(.conclusion)\"")"
seen_first=0; seen_second=0
while read -r id concl; do
  [[ -z "$id" ]] && continue
  log="$(perl -e 'alarm 90; exec @ARGV' gh run view "$id" -R "$repo" --log 2>/dev/null || true)"
  if grep -q "PUSHED_OBJECT: $first_moved" <<<"$log"; then
    seen_first=1
    if [[ "$concl" == failure ]] && grep -qE "non-noreply email|now points to .* not ${first_moved:0:12}" <<<"$log"; then
      echo "  ok   e2e-moved-$run_id first object: failure (email or moved)"
    else
      echo "  FAIL e2e-moved-$run_id first object: $concl, expected a failure for the email or the move" >&2
      fails=$((fails + 1))
    fi
  elif grep -q "PUSHED_OBJECT: $second_moved" <<<"$log"; then
    seen_second=1
    if [[ "$concl" == success ]]; then
      echo "  ok   e2e-moved-$run_id replacement: success"
    else
      echo "  FAIL e2e-moved-$run_id replacement: $concl, expected success" >&2
      fails=$((fails + 1))
    fi
  fi
done <<<"$moved_runs"
if [[ $seen_first -eq 0 || $seen_second -eq 0 ]]; then
  echo "  FAIL e2e-moved-$run_id: could not find a run for each object" >&2
  fails=$((fails + 1))
fi

if [[ $fails -ne 0 ]]; then
  echo "$fails e2e check(s) failed" >&2
  exit 1
fi
echo "all GitHub tag e2e checks passed"
