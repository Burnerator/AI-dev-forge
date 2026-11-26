#!/usr/bin/env bash
# End-to-end smoke test of the forge-gates tag path on real GitHub Actions.
# Not run in CI: it needs a disposable repository and pushes to it.
#
# Usage: tests/e2e/github-tags.sh <owner/disposable-repo>
#   The repository must be disposable: its main branch is force-replaced and
#   test tags are created. Needs gh (authenticated), git and network access.
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
started="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
git push -q --force origin main
for t in $(git ls-remote --tags origin | awk '{print $2}' | grep -v '\^{}$'); do git push -q origin ":$t"; done

token="ghp_$(od -An -tx1 -N18 /dev/urandom | tr -d ' \n')"
git tag e2e-light
git tag -a e2e-annotated -m "clean annotated release"
git tag -a e2e-secret -m "release notes token $token"
git -c user.email=someone@example.com tag -a e2e-email -m "personal tagger"
git tag -a e2e-moved -m "first object"
for t in e2e-light e2e-annotated e2e-secret e2e-email e2e-moved; do git push -q origin "refs/tags/$t"; done
first_moved="$(git rev-parse e2e-moved)"
git tag -f -a e2e-moved -m "second object" >/dev/null
git push -q --force origin refs/tags/e2e-moved

echo "waiting for workflow runs..."
expected_runs=6 # 5 tag pushes + the moved tag pushed again
until [[ "$(gh run list -R "$repo" --limit 50 --json headBranch,createdAt -q "[.[]|select((.headBranch|startswith(\"e2e-\")) and .createdAt >= \"$started\")]|length")" -ge $expected_runs ]] \
  && [[ "$(gh run list -R "$repo" --json status -q '[.[]|select(.status!="completed")]|length')" == 0 ]]; do
  sleep 10
done

fails=0
expect() { # expect <tag> <success|failure> [diagnostic]
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
expect e2e-light success
expect e2e-annotated success
expect e2e-secret failure "annotated tag\\(s\\) contain secrets"
expect e2e-email failure "non-noreply email"
expect e2e-moved failure "now points to .* not ${first_moved:0:12}"
expect e2e-moved success

if [[ $fails -ne 0 ]]; then
  echo "$fails e2e check(s) failed" >&2
  exit 1
fi
echo "all GitHub tag e2e checks passed"
