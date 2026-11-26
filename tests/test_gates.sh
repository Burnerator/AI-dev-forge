#!/usr/bin/env bash
# Integration tests for the installed gates: scripts/check_secrets.sh and the
# pre-push hook, against throwaway git repositories and a local bare remote.
# Needs git and gitleaks. Secrets are generated at run time, never stored.
set -euo pipefail
# Each case sets bootstrap mode itself; never inherit it (e.g. when this suite
# runs inside a FORGE_BOOTSTRAP=1 push of the forge).
unset FORGE_BOOTSTRAP
forge="$(cd "$(dirname "$0")/.." && pwd -P)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fails=0

pass() { echo "  ok   $1"; }
fail() { echo "  FAIL $1${2:+: $2}" >&2; fails=$((fails + 1)); }

# check <description> <command...>: the command must succeed.
check() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then pass "$desc"; else fail "$desc"; fi
}
# rejects <description> <expected diagnostic (ERE)> <command...>: the command
# must fail AND print the expected diagnostic, so a crash or an unrelated
# failure does not count as a pass.
rejects() {
  local desc="$1" pattern="$2" out status=0; shift 2
  out="$("$@" 2>&1)" || status=$?
  if [[ $status -eq 0 ]]; then fail "$desc" "command succeeded"
  elif ! grep -qE "$pattern" <<<"$out"; then
    fail "$desc" "missing diagnostic /$pattern/"
    tail -n 8 <<<"$out" | sed 's/^/         | /' >&2
  else pass "$desc"; fi
}
no_remote_ref() { ! git -C "$1" rev-parse --verify -q "$2" >/dev/null; }

# Bounded read: git ignores SIGPIPE in hooks, so an unbounded `tr </dev/urandom | head`
# never terminates when this suite runs inside the pre-push hook.
fake_token() { printf 'ghp_%s' "$(od -An -tx1 -N18 /dev/urandom | tr -d ' \n')"; }

# new_project <dir>: forge-installed repo with a passing check.sh, a noreply
# identity, the hook enabled, and a bare remote called origin.
new_project() {
  local p="$1"
  mkdir -p "$p"
  git -C "$p" init -q -b main
  git -C "$p" config user.name test
  git -C "$p" config user.email "1+test@users.noreply.github.com"
  git -C "$p" config commit.gpgsign false
  "$forge/scripts/install.sh" "$p" >/dev/null
  printf '#!/usr/bin/env bash\necho "checks ok"\n' > "$p/scripts/check.sh"
  git -C "$p" config core.hooksPath .githooks
  git -C "$p" add -A
  git -C "$p" commit -qm "chore: install forge"
  # Explicit default branch: runners without init.defaultBranch would point the
  # bare remote's HEAD at a non-existent master.
  git init -q --bare -b main "$p.remote.git"
  git -C "$p" remote add origin "$p.remote.git"
}

secrets() { (cd "$1" && ./scripts/check_secrets.sh "${@:2}"); }
LEAK='gitleaks found [0-9]+ secret'
ENV='\.env file\(s\) present'

echo "check_secrets.sh"
p="$tmp/clean"; new_project "$p"
check "passes on a clean repo" secrets "$p"

p="$tmp/merge"; new_project "$p"
echo a > "$p/f"; git -C "$p" add f; git -C "$p" commit -qm a
git -C "$p" switch -qc side; echo b > "$p/f"; git -C "$p" commit -qam b
git -C "$p" switch -q main; echo c > "$p/f"; git -C "$p" commit -qam c
if git -C "$p" merge -q side >/dev/null 2>&1; then fail "fixture: merge should conflict"; fi
printf 'resolved\ntoken = "%s"\n' "$(fake_token)" > "$p/f"
git -C "$p" add f; git -C "$p" commit -qm "merge side"
check "fixture: HEAD is a merge commit with two parents" test "$(git -C "$p" rev-list --parents -n1 HEAD | wc -w | tr -d ' ')" = 3
check "fixture: the token is not in either parent" test -z "$(git -C "$p" grep -l ghp_ HEAD^1 HEAD^2 -- f)"
rejects "finds a secret that only exists in a merge commit, and names that commit" "^  $(git -C "$p" rev-parse --short=12 HEAD)$" secrets "$p"

p="$tmp/envroot"; new_project "$p"
echo "X=1" > "$p/.env.local"; git -C "$p" add -f .env.local; git -C "$p" commit -qm env
rejects "finds .env.local at the root" "$ENV" secrets "$p"

p="$tmp/envquoted"; new_project "$p"
mkdir -p "$p/dír con espacio"; echo "X=1" > "$p/dír con espacio/.env"
git -C "$p" add -f "dír con espacio/.env"; git -C "$p" commit -qm env
rejects "finds .env in a path git would quote" "$ENV" secrets "$p"

p="$tmp/example"; new_project "$p"
echo "X=" > "$p/.env.example"; git -C "$p" add .env.example; git -C "$p" commit -qm example
check "allows .env.example" secrets "$p"

p="$tmp/identity"; new_project "$p"
echo x > "$p/x"; git -C "$p" add x
git -C "$p" -c user.email=someone@example.com commit -qm personal
rejects "rejects a personal commit email" "non-noreply email" secrets "$p"

p="$tmp/badrev"; new_project "$p"
rejects "rejects an argument that is not a commit" "not a commit" secrets "$p" not-a-commit

p="$tmp/shallow-src"; new_project "$p"
echo 1 > "$p/a"; git -C "$p" add a; git -C "$p" commit -qm one
echo 2 > "$p/a"; git -C "$p" commit -qam two
git clone -q --depth 1 "file://$p" "$tmp/shallow"
rejects "rejects a shallow clone" "shallow clone" secrets "$tmp/shallow"

p="$tmp/binary"; new_project "$p"
printf 'a\0b\0\ntoken = "%s"\n' "$(fake_token)" > "$p/blob.dat"
git -C "$p" add blob.dat; git -C "$p" commit -qm "add binary"
rejects "finds a secret inside a file git treats as binary" "$LEAK" secrets "$p"

p="$tmp/private"; new_project "$p"
printf 'token = "%s"\n' "$(fake_token)" > "$p/secret path name.txt"
git -C "$p" add -A
git -C "$p" -c user.name="Private Person" -c user.email=private.person@example.com commit -qm "add config"
out="$(secrets "$p" 2>&1 || true)"
check "fixture: the scan did report the finding" grep -qE "$LEAK" <<<"$out"
check "never prints the author's email" test -z "$(grep -i 'private.person@example.com' <<<"$out")"
check "never prints the author's name" test -z "$(grep -i 'Private Person' <<<"$out")"
check "never prints the file path" test -z "$(grep -i 'secret path name' <<<"$out")"

echo "pre-push hook"
p="$tmp/push-ok"; new_project "$p"
rejects "refuses a first push without explicit bootstrap" "no reviewed scanner yet" git -C "$p" push origin main
check "nothing reached the remote" no_remote_ref "$p.remote.git" refs/heads/main
check "allows a clean first push with FORGE_BOOTSTRAP=1" env FORGE_BOOTSTRAP=1 git -C "$p" push -q origin main
check "the push reached the remote" git -C "$p.remote.git" rev-parse --verify -q refs/heads/main

p="$tmp/push-fail"; new_project "$p"
printf '#!/usr/bin/env bash\nexit 1\n' > "$p/scripts/check.sh"
git -C "$p" commit -qam "break checks"
printf '#!/usr/bin/env bash\nexit 0\n' > "$p/scripts/check.sh" # passing, but uncommitted
rejects "blocks when the pushed tree fails check.sh (ignores the working tree)" "checks failed for refs/heads/main" env FORGE_BOOTSTRAP=1 git -C "$p" push origin main
check "nothing reached the remote" no_remote_ref "$p.remote.git" refs/heads/main

p="$tmp/push-secret"; new_project "$p"
printf 'token = "%s"\n' "$(fake_token)" > "$p/config.txt"
git -C "$p" add config.txt; git -C "$p" commit -qm "add config"
rejects "blocks a first push that contains a secret" "secrets gate failed" env FORGE_BOOTSTRAP=1 git -C "$p" push origin main
check "nothing reached the remote" no_remote_ref "$p.remote.git" refs/heads/main

p="$tmp/push-orphan"; new_project "$p"
FORGE_BOOTSTRAP=1 git -C "$p" push -q origin main
git -C "$p" switch -q --detach
echo "X=1" > "$p/.env"; git -C "$p" add -f .env; git -C "$p" commit -qm "env on detached HEAD"
orphan="$(git -C "$p" rev-parse HEAD)"
git -C "$p" switch -q main # no ref points to the commit any more
rejects "blocks pushing by SHA a commit that no ref points to" "secrets gate failed" git -C "$p" push origin "$orphan:refs/heads/sneaky"
check "the unreferenced commit did not reach the remote" no_remote_ref "$p.remote.git" refs/heads/sneaky

p="$tmp/push-wc-scanner"; new_project "$p"
FORGE_BOOTSTRAP=1 git -C "$p" push -q origin main
printf '#!/usr/bin/env bash\nexit 0\n' > "$p/scripts/check_secrets.sh" # weakened, uncommitted
printf 'token = "%s"\n' "$(fake_token)" > "$p/config.txt"
git -C "$p" add config.txt; git -C "$p" commit -qm "add config"
rejects "ignores a weakened scanner in the working copy" "secrets gate failed" git -C "$p" push origin main
check "the secret did not reach the remote" test "$(git -C "$p.remote.git" rev-parse main)" != "$(git -C "$p" rev-parse main)"

p="$tmp/push-committed-scanner"; new_project "$p"
FORGE_BOOTSTRAP=1 git -C "$p" push -q origin main
git -C "$p" switch -qc feat/weaken
printf '#!/usr/bin/env bash\nexit 0\n' > "$p/scripts/check_secrets.sh"
printf 'token = "%s"\n' "$(fake_token)" > "$p/config.txt"
git -C "$p" add -A; git -C "$p" commit -qm "weaken scanner and add config"
rejects "uses the default branch's scanner, not one committed on the branch" "secrets gate failed" git -C "$p" push origin feat/weaken
check "the branch did not reach the remote" no_remote_ref "$p.remote.git" refs/heads/feat/weaken

p="$tmp/push-trunk"; new_project "$p"
git -C "$p" branch -m main trunk
FORGE_BOOTSTRAP=1 git -C "$p" push -q origin trunk
git -C "$p.remote.git" symbolic-ref HEAD refs/heads/trunk
git -C "$p" update-ref -d refs/remotes/origin/HEAD 2>/dev/null || true
check "fixture: no local origin/HEAD and no origin/main" test -z "$(git -C "$p" for-each-ref refs/remotes/origin/HEAD refs/remotes/origin/main)"
git -C "$p" switch -qc feat/x
printf '#!/usr/bin/env bash\nexit 0\n' > "$p/scripts/check_secrets.sh"
printf 'token = "%s"\n' "$(fake_token)" > "$p/config.txt"
git -C "$p" add -A; git -C "$p" commit -qm "weaken scanner and add config"
rejects "asks the remote for a non-standard default branch (trunk)" "scanner from origin trunk" git -C "$p" push origin feat/x
check "the branch did not reach the remote" no_remote_ref "$p.remote.git" refs/heads/feat/x

p="$tmp/push-stale"; new_project "$p"
FORGE_BOOTSTRAP=1 git -C "$p" push -q origin main
good="$(git -C "$p" rev-parse main)"
git -C "$p" switch -qc feat/y
printf '#!/usr/bin/env bash\nexit 0\n' > "$p/scripts/check_secrets.sh"
git -C "$p" commit -qam "weaken scanner"
git -C "$p" update-ref refs/remotes/origin/main HEAD # wrong local tracking ref
printf 'token = "%s"\n' "$(fake_token)" > "$p/config.txt"
git -C "$p" add -A; git -C "$p" commit -qm "add config"
rejects "ignores a wrong local tracking ref, uses what the remote reports" "scanner from origin main @ ${good:0:7}" git -C "$p" push origin feat/y
check "the branch did not reach the remote" no_remote_ref "$p.remote.git" refs/heads/feat/y

if [[ $fails -ne 0 ]]; then
  echo "$fails test(s) failed" >&2
  exit 1
fi
echo "all gate tests passed"
