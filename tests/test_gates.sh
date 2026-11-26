#!/usr/bin/env bash
# Integration tests for the installed gates: scripts/check_secrets.sh and the
# pre-push hook, against throwaway git repositories and a local bare remote.
# Needs git and gitleaks. Secrets are generated at run time, never stored.
set -euo pipefail
forge="$(cd "$(dirname "$0")/.." && pwd -P)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fails=0

check() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then echo "  ok   $desc"; else echo "  FAIL $desc" >&2; fails=$((fails + 1)); fi
}
refuses() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then echo "  FAIL $desc" >&2; fails=$((fails + 1)); else echo "  ok   $desc"; fi
}

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
  git init -q --bare "$p.remote.git"
  git -C "$p" remote add origin "$p.remote.git"
}

secrets() { (cd "$1" && ./scripts/check_secrets.sh "${@:2}"); }

echo "check_secrets.sh"
p="$tmp/clean"; new_project "$p"
check "passes on a clean repo" secrets "$p"

p="$tmp/merge"; new_project "$p"
echo a > "$p/f"; git -C "$p" add f; git -C "$p" commit -qm a
git -C "$p" switch -qc side; echo b > "$p/f"; git -C "$p" commit -qam b
git -C "$p" switch -q main; echo c > "$p/f"; git -C "$p" commit -qam c
git -C "$p" merge -q side >/dev/null 2>&1 || true
printf 'resolved\ntoken = "%s"\n' "$(fake_token)" > "$p/f"
git -C "$p" add f; git -C "$p" commit -qm "merge side"
refuses "finds a secret that only exists in a merge commit" secrets "$p"

p="$tmp/envroot"; new_project "$p"
echo "X=1" > "$p/.env.local"; git -C "$p" add -f .env.local; git -C "$p" commit -qm env
refuses "finds .env.local at the root" secrets "$p"

p="$tmp/envquoted"; new_project "$p"
mkdir -p "$p/dír con espacio"; echo "X=1" > "$p/dír con espacio/.env"
git -C "$p" add -f "dír con espacio/.env"; git -C "$p" commit -qm env
refuses "finds .env in a path git would quote" secrets "$p"

p="$tmp/example"; new_project "$p"
echo "X=" > "$p/.env.example"; git -C "$p" add .env.example; git -C "$p" commit -qm example
check "allows .env.example" secrets "$p"

p="$tmp/identity"; new_project "$p"
echo x > "$p/x"; git -C "$p" add x
git -C "$p" -c user.email=someone@example.com commit -qm personal
refuses "rejects a personal commit email" secrets "$p"

p="$tmp/badrev"; new_project "$p"
refuses "rejects an argument that is not a commit" secrets "$p" not-a-commit

echo "pre-push hook"
p="$tmp/push-ok"; new_project "$p"
check "allows a clean push" git -C "$p" push -q origin main

p="$tmp/push-fail"; new_project "$p"
printf '#!/usr/bin/env bash\nexit 1\n' > "$p/scripts/check.sh"
git -C "$p" commit -qam "break checks"
printf '#!/usr/bin/env bash\nexit 0\n' > "$p/scripts/check.sh" # passing, but uncommitted
refuses "blocks when the pushed tree fails check.sh (ignores the working tree)" git -C "$p" push -q origin main
refuses "nothing reached the remote" git -C "$p.remote.git" rev-parse --verify -q refs/heads/main

p="$tmp/push-secret"; new_project "$p"
printf 'token = "%s"\n' "$(fake_token)" > "$p/config.txt"
git -C "$p" add config.txt; git -C "$p" commit -qm "add config"
refuses "blocks a push that contains a secret" git -C "$p" push -q origin main

p="$tmp/push-orphan"; new_project "$p"
git -C "$p" push -q origin main
git -C "$p" switch -q --detach
echo "X=1" > "$p/.env"; git -C "$p" add -f .env; git -C "$p" commit -qm "env on detached HEAD"
orphan="$(git -C "$p" rev-parse HEAD)"
git -C "$p" switch -q main # no ref points to the commit any more
refuses "blocks pushing by SHA a commit that no ref points to" git -C "$p" push -q origin "$orphan:refs/heads/sneaky"
refuses "the unreferenced commit did not reach the remote" git -C "$p.remote.git" rev-parse --verify -q refs/heads/sneaky

if [[ $fails -ne 0 ]]; then
  echo "$fails test(s) failed" >&2
  exit 1
fi
echo "all gate tests passed"
