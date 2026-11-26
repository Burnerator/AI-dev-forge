#!/usr/bin/env bash
# Integration tests for the installed gates: scripts/check_secrets.sh and the
# pre-push hook, against throwaway git repositories and a local bare remote.
# Needs git and gitleaks. Secrets are generated at run time, never stored.
set -euo pipefail
# Each case sets bootstrap mode itself; never inherit it (e.g. when this suite
# runs inside a FORGE_BOOTSTRAP=1 push of the forge).
unset FORGE_BOOTSTRAP
# The hook exports this; the replacement fixture needs git's default behaviour.
unset GIT_NO_REPLACE_OBJECTS
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
# rejects_all <description> <pattern1> <pattern2> <command...>: like rejects, but
# both diagnostics must appear.
rejects_all() {
  local desc="$1" p1="$2" p2="$3" out status=0; shift 3
  out="$("$@" 2>&1)" || status=$?
  if [[ $status -eq 0 ]]; then fail "$desc" "command succeeded"
  elif ! grep -qE "$p1" <<<"$out" || ! grep -qE "$p2" <<<"$out"; then
    fail "$desc" "missing diagnostic /$p1/ and /$p2/"
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

# bootstrap_push <dir> <branch>: first push of the forge, then pin its scanner,
# as a developer would after reading it.
bootstrap_push() {
  FORGE_BOOTSTRAP=1 git -C "$1" push -q origin "$2"
  git -C "$1" config forge.trustedCommit "$(git -C "$1" rev-parse "$2")"
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

p="$tmp/envrc"; new_project "$p"
echo "export X=1" > "$p/.envrc"; git -C "$p" add -f .envrc; git -C "$p" commit -qm envrc
rejects "finds .envrc at the root" "$ENV" secrets "$p"
p="$tmp/envnested"; new_project "$p"
mkdir -p "$p/config/deep"; echo "X=1" > "$p/config/deep/.env.production"; echo "export X=1" > "$p/config/.envrc"
git -C "$p" add -f config; git -C "$p" commit -qm nested
rejects "finds nested .env.production and .envrc" "2 occurrence" secrets "$p"

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
token="$(fake_token)"
printf 'token = "%s"\n' "$token" > "$p/secret path name.txt"
git -C "$p" add -A
git -C "$p" -c user.name="Private Person" -c user.email=private.person@example.com commit -qm "add config"
status=0; out="$(secrets "$p" 2>&1)" || status=$?
check "the gate rejects the commit" test "$status" -ne 0
check "fixture: the scan did report the finding" grep -qE "$LEAK" <<<"$out"
check "never prints the token" test -z "$(grep -F "${token:4}" <<<"$out")"
check "never prints the author's email" test -z "$(grep -i 'private.person@example.com' <<<"$out")"
check "never prints the author's name" test -z "$(grep -i 'Private Person' <<<"$out")"
check "never prints the file path" test -z "$(grep -i 'secret path name' <<<"$out")"

p="$tmp/allow-comment"; new_project "$p"
printf 'token = "%s" # gitleaks:allow\n' "$(fake_token)" > "$p/config.txt"
git -C "$p" add config.txt; git -C "$p" commit -qm "allow comment"
rejects "an inline gitleaks:allow comment does not suppress a finding" "$LEAK" secrets "$p"

p="$tmp/tag-identity"; new_project "$p"
git -C "$p" -c user.email=someone@example.com tag -a v1 -m "release"
rejects "rejects an annotated tag with a personal tagger email" "non-noreply email" secrets "$p"

p="$tmp/tag-secret"; new_project "$p"
git -C "$p" tag -a v1 -m "release notes: token $(fake_token)"
rejects "finds a secret in an annotated tag message" "annotated tag\(s\) contain secrets" secrets "$p"

p="$tmp/tag-nested"; new_project "$p"
git -C "$p" -c user.email=someone@example.com tag -a inner -m "inner"
git -C "$p" tag -a outer -m "outer" inner
git -C "$p" update-ref -d refs/tags/inner # only the outer tag has a ref
check "fixture: outer tag points to a tag object" test "$(git -C "$p" cat-file -t "$(git -C "$p" cat-file tag outer | sed -n 's/^object //p')")" = tag
rejects "follows a tag that points to a tag" "non-noreply email" secrets "$p"

p="$tmp/replace"; new_project "$p"
printf 'token = "%s"\n' "$(fake_token)" > "$p/config.txt"
git -C "$p" add config.txt; git -C "$p" commit -qm "add config"
leaky="$(git -C "$p" rev-parse HEAD)"
git -C "$p" rm -q config.txt; git -C "$p" commit -qm "clean"
clean_tree="$(git -C "$p" rev-parse 'HEAD^{tree}')"
fake="$(git -C "$p" commit-tree "$clean_tree" -p "$leaky^" -m "add config")"
git -C "$p" replace "$leaky" "$fake" # local history now shows no secret
check "fixture: with replacements, git log no longer shows the secret" test -z "$(git -C "$p" log -p --all | grep ghp_)"
rejects "ignores replacement objects and scans the real history" "$LEAK" secrets "$p"

p="$tmp/tag-explicit"; new_project "$p"
git -C "$p" -c user.email=someone@example.com tag -a v9 -m "release"
tagobj="$(git -C "$p" rev-parse v9)"
git -C "$p" update-ref -d refs/tags/v9 # as in a CI checkout: only what is passed explicitly
rejects "rejects a tag passed explicitly (CI tag push) with a personal tagger" "non-noreply email" secrets "$p" "$tagobj"

p="$tmp/msg-secret"; new_project "$p"
echo x > "$p/x"; git -C "$p" add x
git -C "$p" commit -qm "deploy with token $(fake_token)"
rejects "finds a secret that only exists in a commit message" "commit messages contain [0-9]+ secret" secrets "$p"

p="$tmp/scope"; new_project "$p"
git -C "$p" switch -qc unrelated
echo "X=1" > "$p/.env"; git -C "$p" add -f .env; git -C "$p" commit -qm "env elsewhere"
git -C "$p" switch -q main
rejects "default scope sees every local branch" "$ENV" secrets "$p"
check "--only ignores unrelated branches (CI on a clean commit)" secrets "$p" --only main
rejects "--only still scans the given history" "$ENV" secrets "$p" --only unrelated
rejects "--only without revisions is refused" "needs at least one revision" secrets "$p" --only

# A fake gitleaks first in PATH, to prove the gate fails closed.
fakebin="$tmp/fakebin"; mkdir -p "$fakebin"
with_fake_scanner() { (cd "$1" && PATH="$fakebin:$PATH" ./scripts/check_secrets.sh); }
p="$tmp/fake-scanner"; new_project "$p"
printf '#!/usr/bin/env bash\necho "something broke" >&2\nexit 2\n' > "$fakebin/gitleaks"; chmod +x "$fakebin/gitleaks"
rejects "fails closed when gitleaks exits with an error" "gitleaks failed to run" with_fake_scanner "$p"
printf '#!/usr/bin/env bash\necho "0 commits scanned."\nexit 0\n' > "$fakebin/gitleaks"
rejects "fails closed when gitleaks scans zero commits" "scanned no commits" with_fake_scanner "$p"
printf '#!/usr/bin/env bash\nexit 0\n' > "$fakebin/gitleaks"
rejects "fails closed when gitleaks reports nothing at all" "scanned no commits" with_fake_scanner "$p"

p="$tmp/tag-ci"; new_project "$p"
git -C "$p" tag -a v1 -m "release"
pushed="$(git -C "$p" rev-parse v1)"
check "--tag passes when the tag is the object from the push event" secrets "$p" --tag refs/tags/v1 "$pushed"
git -C "$p" -c user.email=someone@example.com tag -f -a v1 -m "moved" >/dev/null # tag moved after the push
rejects "--tag fails when the tag has moved since the push event" "now points to .* not ${pushed:0:12}" secrets "$p" --tag refs/tags/v1 "$pushed"
rejects "--tag fails when the tag is missing" "not available in this checkout" secrets "$p" --tag refs/tags/nope "$pushed"
rejects "--tag needs both arguments" "needs <tag-ref> <expected-object-id>" secrets "$p" --tag refs/tags/v1

p="$tmp/env-config"; new_project "$p"
printf 'title = "permissive"\n' > "$tmp/permissive.toml" # a policy with no rules
printf 'token = "%s"\n' "$(fake_token)" > "$p/config.txt"
git -C "$p" add config.txt; git -C "$p" commit -qm "add config"
rejects "ignores GITLEAKS_CONFIG from the environment" "$LEAK" env GITLEAKS_CONFIG="$tmp/permissive.toml" bash "$p/scripts/check_secrets.sh"
rejects "ignores GITLEAKS_CONFIG_TOML from the environment" "$LEAK" env GITLEAKS_CONFIG_TOML="$(cat "$tmp/permissive.toml")" bash "$p/scripts/check_secrets.sh"

# Root commit: the very first commit of a repository, with log.showRoot=false.
p="$tmp/root-env"; mkdir -p "$p"; git -C "$p" init -q -b main
git -C "$p" config user.name test; git -C "$p" config user.email "1+test@users.noreply.github.com"
git -C "$p" config log.showRoot false
"$forge/scripts/install.sh" "$p" >/dev/null
echo "X=1" > "$p/.env"; git -C "$p" add -A; git -C "$p" add -f .env; git -C "$p" commit -qm root
check "fixture: HEAD is a root commit" test "$(git -C "$p" rev-list --count HEAD)" = 1
rejects "finds a .env added in the root commit with log.showRoot=false" "$ENV" secrets "$p"
p="$tmp/root-token"; mkdir -p "$p"; git -C "$p" init -q -b main
git -C "$p" config user.name test; git -C "$p" config user.email "1+test@users.noreply.github.com"
git -C "$p" config log.showRoot false
"$forge/scripts/install.sh" "$p" >/dev/null
printf 'token = "%s"\n' "$(fake_token)" > "$p/config.txt"; git -C "$p" add -A; git -C "$p" commit -qm root
rejects "finds a token added in the root commit with log.showRoot=false" "$LEAK" secrets "$p"

p="$tmp/tag-headerlike"; new_project "$p"
git -C "$p" tag -a v2 -m "release notes" -m "tagger Someone <someone@example.com> 0 +0000"
check "a header-like line in a tag message is not taken as the tagger" secrets "$p"

echo "pre-push hook"
p="$tmp/push-ok"; new_project "$p"
rejects "refuses a first push without explicit bootstrap" "no trusted scanner pinned" git -C "$p" push origin main
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
bootstrap_push "$p" main
git -C "$p" switch -q --detach
echo "X=1" > "$p/.env"; git -C "$p" add -f .env; git -C "$p" commit -qm "env on detached HEAD"
orphan="$(git -C "$p" rev-parse HEAD)"
git -C "$p" switch -q main # no ref points to the commit any more
rejects "blocks pushing by SHA a commit that no ref points to" "secrets gate failed" git -C "$p" push origin "$orphan:refs/heads/sneaky"
check "the unreferenced commit did not reach the remote" no_remote_ref "$p.remote.git" refs/heads/sneaky

p="$tmp/push-wc-scanner"; new_project "$p"
bootstrap_push "$p" main
printf '#!/usr/bin/env bash\nexit 0\n' > "$p/scripts/check_secrets.sh" # weakened, uncommitted
printf 'token = "%s"\n' "$(fake_token)" > "$p/config.txt"
git -C "$p" add config.txt; git -C "$p" commit -qm "add config"
rejects "ignores a weakened scanner in the working copy" "secrets gate failed" git -C "$p" push origin main
check "the secret did not reach the remote" test "$(git -C "$p.remote.git" rev-parse main)" != "$(git -C "$p" rev-parse main)"

p="$tmp/push-committed-scanner"; new_project "$p"
bootstrap_push "$p" main
git -C "$p" switch -qc feat/weaken
printf '#!/usr/bin/env bash\nexit 0\n' > "$p/scripts/check_secrets.sh"
printf 'token = "%s"\n' "$(fake_token)" > "$p/config.txt"
git -C "$p" add -A; git -C "$p" commit -qm "weaken scanner and add config"
rejects "uses the default branch's scanner, not one committed on the branch" "secrets gate failed" git -C "$p" push origin feat/weaken
check "the branch did not reach the remote" no_remote_ref "$p.remote.git" refs/heads/feat/weaken

p="$tmp/push-unset"; new_project "$p"
git -C "$p" config forge.trustedCommit refs/remotes/origin/main
rejects "refuses a pin that is a ref name, not a commit ID" "must be a full commit ID" env FORGE_BOOTSTRAP=1 git -C "$p" push origin main
check "nothing reached the remote" no_remote_ref "$p.remote.git" refs/heads/main

p="$tmp/push-trunk"; new_project "$p"
git -C "$p" branch -m main trunk
bootstrap_push "$p" trunk
git -C "$p" switch -qc feat/x
printf '#!/usr/bin/env bash\nexit 0\n' > "$p/scripts/check_secrets.sh"
printf 'token = "%s"\n' "$(fake_token)" > "$p/config.txt"
git -C "$p" add -A; git -C "$p" commit -qm "weaken scanner and add config"
rejects_all "uses the pinned scanner (trunk), and it finds the secret" "scanner from pinned commit $(git -C "$p" rev-parse --short=12 trunk)" "$LEAK" git -C "$p" push origin feat/x
check "the branch did not reach the remote" no_remote_ref "$p.remote.git" refs/heads/feat/x

p="$tmp/push-ignorefile"; new_project "$p"
bootstrap_push "$p" main
git -C "$p" switch -qc feat/ignore
printf 'token = "%s"\n' "$(fake_token)" > "$p/config.txt"
git -C "$p" add config.txt; git -C "$p" commit -qm "add config"
echo "$(git -C "$p" rev-parse HEAD):config.txt:github-pat:1" > "$p/.gitleaksignore"
git -C "$p" add .gitleaksignore; git -C "$p" commit -qm "ignore it"
check "fixture: the branch's ignore file would silence the finding" secrets "$p"
rejects_all "a .gitleaksignore committed on the branch does not silence the trusted scan" "scanner from pinned commit" "$LEAK" git -C "$p" push origin feat/ignore
check "the branch did not reach the remote" no_remote_ref "$p.remote.git" refs/heads/feat/ignore

p="$tmp/push-dest"; new_project "$p"
bootstrap_push "$p" main
# A second, non-empty destination whose default branch carries a hostile scanner.
evil="$tmp/push-dest.evil"; marker="$tmp/push-dest.ran"
git clone -q "$p.remote.git" "$evil"
git -C "$evil" config user.email "1+e@users.noreply.github.com"; git -C "$evil" config user.name e
printf '#!/usr/bin/env bash\ntouch "%s"\nexit 0\n' "$marker" > "$evil/scripts/check_secrets.sh"
git -C "$evil" commit -qam "hostile scanner"
git init -q --bare -b main "$evil.git"; git -C "$evil" push -q --no-verify "$evil.git" main
git -C "$p" config remote.origin.pushurl "$evil.git"
# Build on the destination's history so the push is a fast-forward and the hook
# really runs; the hostile scanner is then even part of the pushed commits.
git -C "$p" fetch -q "$evil.git" main
git -C "$p" reset -q --hard FETCH_HEAD
printf 'token = "%s"\n' "$(fake_token)" > "$p/config.txt"
git -C "$p" add config.txt; git -C "$p" commit -qm "add config"
rejects_all "never runs code from the push destination" "scanner from pinned commit" "$LEAK" git -C "$p" push origin main
check "the destination's scanner never ran" test ! -e "$marker"

p="$tmp/push-nocheckout"; new_project "$p"
bootstrap_push "$p" main
echo z > "$p/z"; git -C "$p" add z; git -C "$p" commit -qm "more"
status=0; out="$(TMPDIR="$tmp/does-not-exist" git -C "$p" push origin main 2>&1)" || status=$?
check "stops when it cannot create a clean checkout" test "$status" -ne 0
check "says so" grep -q "cannot create a clean checkout" <<<"$out"
check "no gate ran on an incomplete checkout" test -z "$(grep -E 'checks ok|==> ' <<<"$out")"

p="$tmp/push-postcheckout"; new_project "$p"
marker="$tmp/post-checkout.ran"
printf '#!/usr/bin/env bash\ntouch "%s"\n' "$marker" > "$p/.githooks/post-checkout"; chmod +x "$p/.githooks/post-checkout"
git -C "$p" add .githooks/post-checkout; git -C "$p" commit -qm "add post-checkout hook"
rm -f "$marker"
check "push with a post-checkout hook in the project" env FORGE_BOOTSTRAP=1 git -C "$p" push -q origin main
check "the project's post-checkout hook never ran during the gates" test ! -e "$marker"

p="$tmp/push-legacy"; new_project "$p"
marker="$tmp/legacy.ran"
printf '#!/usr/bin/env bash\ncat > "%s"\n' "$marker" > "$p/.git/hooks/pre-push"; chmod +x "$p/.git/hooks/pre-push"
check "push with a previous pre-push hook in .git/hooks" env FORGE_BOOTSTRAP=1 git -C "$p" push -q origin main
check "the previous hook ran after the gates" test -f "$marker"
check "it received the same refs on stdin" grep -q "refs/heads/main $(git -C "$p" rev-parse main)" "$marker"
p="$tmp/push-legacy-fail"; new_project "$p"
printf '#!/usr/bin/env bash\nexit 1\n' > "$p/.git/hooks/pre-push"; chmod +x "$p/.git/hooks/pre-push"
rejects "a failing previous hook still blocks the push" "previous pre-push hook failed" env FORGE_BOOTSTRAP=1 git -C "$p" push origin main
check "nothing reached the remote" no_remote_ref "$p.remote.git" refs/heads/main

lfsbin="$tmp/lfsbin"; mkdir -p "$lfsbin"; lfsmark="$tmp/lfs.ran"
printf '#!/usr/bin/env bash\necho "$*" > "%s"; cat >> "%s"\n' "$lfsmark" "$lfsmark" > "$lfsbin/git-lfs"; chmod +x "$lfsbin/git-lfs"
p="$tmp/push-lfs"; new_project "$p"
echo '*.bin filter=lfs diff=lfs merge=lfs -text' > "$p/.gitattributes"; git -C "$p" add .gitattributes; git -C "$p" commit -qm "use lfs"
check "push in an LFS repository" env PATH="$lfsbin:$PATH" FORGE_BOOTSTRAP=1 git -C "$p" push -q origin main
check "git lfs pre-push ran with the remote and the refs" grep -q "^pre-push origin" "$lfsmark"
check "git lfs pre-push received the pushed refs" grep -q "refs/heads/main $(git -C "$p" rev-parse main)" "$lfsmark"
p="$tmp/push-lfs-missing"; new_project "$p"
echo '*.bin filter=lfs diff=lfs merge=lfs -text' > "$p/.gitattributes"; git -C "$p" add .gitattributes; git -C "$p" commit -qm "use lfs"
nolfs="$tmp/nolfs"; mkdir -p "$nolfs"; for t in git bash env sh mktemp rm cat sed awk grep od tr head sort cut wc dirname basename find gitleaks printf; do w="$(command -v "$t" || true)"; [[ -n "$w" && "$w" == /* ]] && ln -sf "$w" "$nolfs/$t"; done
rejects "refuses an LFS push when git-lfs is missing" "git-lfs is not installed" env PATH="$nolfs" FORGE_BOOTSTRAP=1 git -C "$p" push origin main

p="$tmp/push-msg"; new_project "$p"
bootstrap_push "$p" main
echo y > "$p/y"; git -C "$p" add y; git -C "$p" commit -qm "token $(fake_token)"
rejects "blocks a push whose only secret is in a commit message" "commit messages contain" git -C "$p" push origin main
check "the commit did not reach the remote" test "$(git -C "$p.remote.git" rev-parse main)" != "$(git -C "$p" rev-parse main)"

p="$tmp/push-tag"; new_project "$p"
bootstrap_push "$p" main
git -C "$p" -c user.email=someone@example.com tag -a v1 -m "release"
rejects "blocks pushing an annotated tag with a personal tagger email" "non-noreply email" git -C "$p" push origin v1
check "the tag did not reach the remote" no_remote_ref "$p.remote.git" refs/tags/v1

p="$tmp/push-pin"; new_project "$p"
bootstrap_push "$p" main
pinned="$(git -C "$p" rev-parse main)"
other="$tmp/push-pin.other"; git clone -q "$p.remote.git" "$other"
git -C "$other" config user.email "1+o@users.noreply.github.com"; git -C "$other" config user.name o
printf '#!/usr/bin/env bash\nexit 0\n' > "$other/scripts/check_secrets.sh"
git -C "$other" commit -qam "unreviewed scanner on main"
git -C "$other" push -q --no-verify origin main
git -C "$p" fetch -q origin # origin/main now carries the unreviewed scanner
check "fixture: origin/main moved past the pin" test "$(git -C "$p" rev-parse origin/main)" != "$pinned"
git -C "$p" switch -qc feat/z
printf 'token = "%s"\n' "$(fake_token)" > "$p/config.txt"
git -C "$p" add config.txt; git -C "$p" commit -qm "add config"
rejects_all "a fetch does not move the trusted scanner: the pin still runs" "scanner from pinned commit ${pinned:0:12}" "$LEAK" git -C "$p" push origin feat/z
check "the branch did not reach the remote" no_remote_ref "$p.remote.git" refs/heads/feat/z

echo "trust-scanner.sh"
p="$tmp/trust"; new_project "$p"
first="$(git -C "$p" rev-parse HEAD)"
trust() { (cd "$1" && ./scripts/trust-scanner.sh "${@:2}"); }
trust_no() { (cd "$1" && echo n | ./scripts/trust-scanner.sh "${@:2}"); }
rejects "refuses something that is not a commit" "not a commit" trust "$p" --yes nope
git -C "$p" commit -q --allow-empty -m "second"
printf 'x\n' > "$p/README"; git -C "$p" add README; git -C "$p" commit -qm third
check "pins a commit with --yes" trust "$p" --yes "$first"
check "stores the full commit ID" test "$(git -C "$p" config forge.trustedCommit)" = "$first"
printf '\n# reviewed change\n' >> "$p/scripts/check_secrets.sh"; git -C "$p" commit -qam "scanner change"
out="$(trust "$p" --yes HEAD)"
check "shows the scanner diff before re-pinning" grep -q '+# reviewed change' <<<"$out"
check "re-pins to the new commit" test "$(git -C "$p" config forge.trustedCommit)" = "$(git -C "$p" rev-parse HEAD)"
rejects "asks before re-pinning and keeps the pin on no" "Not changed" trust_no "$p" "$first"
check "pin unchanged after answering no" test "$(git -C "$p" config forge.trustedCommit)" = "$(git -C "$p" rev-parse HEAD)"
p="$tmp/trust-link"; new_project "$p"
mkdir -p "$p/vendor"; git -C "$p" mv scripts/check_secrets.sh vendor/check_secrets.sh
ln -s ../vendor/check_secrets.sh "$p/scripts/check_secrets.sh"; git -C "$p" add -A; git -C "$p" commit -qm "scanner behind a link"
trust "$p" --yes HEAD >/dev/null
printf '\n# change only in the link target\n' >> "$p/vendor/check_secrets.sh"; git -C "$p" commit -qam "edit target"
out="$(trust "$p" --yes HEAD)"
check "a change confined to a symlink target shows in the pin diff" grep -q '+# change only in the link target' <<<"$out"
git -C "$p" config --unset forge.trustedCommit
out="$(trust "$p" --yes HEAD)"
check "the first pin prints the full scanner, following links" grep -q '# change only in the link target' <<<"$out"

q="$tmp/trust-noscanner"; mkdir -p "$q"; git -C "$q" init -q -b main
git -C "$q" config user.name t; git -C "$q" config user.email "1+t@users.noreply.github.com"
git -C "$q" commit -q --allow-empty -m empty
"$forge/scripts/install.sh" "$q" >/dev/null
rejects "refuses a commit without a scanner" "has no scripts/check_secrets.sh" trust "$q" --yes HEAD

if [[ $fails -ne 0 ]]; then
  echo "$fails test(s) failed" >&2
  exit 1
fi
echo "all gate tests passed"
