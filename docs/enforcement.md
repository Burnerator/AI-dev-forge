# Enforcement: what the gates guarantee and what they don't

`AGENTS.md` and the skills are **guidance**. Agents usually follow them, but nothing guarantees it. Anything that must always hold is enforced by deterministic tooling that runs the same way whichever client, or no client, wrote the code.

## Rule → gate

| Rule | Guidance (agent) | Enforced by |
|---|---|---|
| No known secret formats or `.env` files in git | `AGENTS.md`, `commit-message` skill | **Before publishing**, `pre-push` runs `scripts/check_secrets.sh`: gitleaks' rules (known key and token formats) over patches, merge diffs, binary contents, commit and tag messages, plus files named `.env`, `.env.<anything>` (except `.env.example`) or `.envrc` at any depth. **After publishing**, CI runs the same check on the pushed commit, and GitHub secret scanning + push protection block known provider formats. Arbitrary sensitive data is not detected (see Limits). |
| Commit emails are not personal | `AGENTS.md` | `check_secrets.sh` (noreply author, committer and tagger emails): before publishing in `pre-push`, after publishing in CI |
| Lint and tests pass | `AGENTS.md` | `scripts/check.sh` at each pushed tip in `pre-push` (clean worktree) and CI |
| No direct pushes to `main` | `AGENTS.md`, `open-pull-request` skill | Branch protection on `main` |
| Human review of every change | `AGENTS.md`, policy | Branch protection: 1+ required approval, dismiss stale approvals |
| Sensitive paths need an owner | `AGENTS.md` "Do not touch" | `CODEOWNERS` + "Require review from Code Owners" |
| Gates are not weakened silently | `AGENTS.md` | `CODEOWNERS` on `.githooks/`, `scripts/`, `.github/`, `.gitleaks.toml`, `.gitleaksignore`, plus **required** Code Owner review |
| CI runs what was reviewed | — | Actions pinned to a full commit SHA; scanner binary checksum-verified |

## Set up branch protection on `main`

In the repository settings (Rules → Rulesets, or Branches → Branch protection):

- require a pull request before merging, with at least one approval;
- dismiss stale approvals when new commits are pushed;
- require status checks to pass: `forge-gates / secrets` and `forge-gates / checks`;
- block force pushes and deletions;
- require review from Code Owners, with a `CODEOWNERS` file that covers the gates, the scanner configuration and the ownership file itself:

```
/.githooks/          @your-org/maintainers
/scripts/            @your-org/maintainers
/.github/            @your-org/maintainers
/.gitleaks.toml      @your-org/maintainers
/.gitleaksignore     @your-org/maintainers
/CODEOWNERS          @your-org/maintainers
```

The gates are code that runs on every push and in CI, and a pull request can change them. Without required Code Owner review, the "gates are not weakened silently" row above is only a convention. A solo maintainer cannot approve their own pull request, so a one-person project relies on reading every diff to those paths instead; say so in your `AGENTS.md`.

Also enable secret scanning and push protection (Settings → Code security).

## Limits: what these controls do not guarantee

- **The hook is client-side.** A clone without `core.hooksPath`, or `git push --no-verify`, skips it. CI on every branch compensates in part.
- **CI runs after publishing.** If a push to a branch contains a secret, it is already public (on a public repo) even if CI fails. Push protection only blocks known key formats.
- **Branch protection covers `main` only.** Other branches accept pushes without review.
- **Which scanner runs.** In normal mode the hook takes the secrets scanner from a commit you pinned, never from the working copy, the pushed commits or the push destination. `scripts/trust-scanner.sh <commit-or-ref>` shows the scanner diff and stores the commit ID in `forge.trustedCommit`; a pin does not move when you fetch, so a new scanner only runs after you re-pin it. Two exceptions run pushed code: the quality gate always runs the pushed tip's `check.sh`, and bootstrap (below) runs the pushed tip's scanner.
- **The scanner's configuration follows the scanner.** gitleaks reads `.gitleaks.toml` and `.gitleaksignore` from the checkout it scans: in the hook that is the trusted revision, so a branch cannot silence its own finding; in CI it is the pull request, so both files need required Code Owner review. Inline `gitleaks:allow` comments never suppress a finding (`--ignore-gitleaks-allow`).
- **Annotated tags.** Tag messages are scanned for secrets and tagger emails must be noreply, for every local tag and every pushed one, following tags that point to other tags. Lightweight tags carry no metadata of their own.
- **Bootstrap is explicit.** When the trusted ref does not exist yet or predates the forge, there is no reviewed scanner. The hook refuses the push unless you run it as `FORGE_BOOTSTRAP=1 git push …`; each pushed tip is then scanned with its own committed scanner. Use it once, for the pull request that introduces the forge.
- **Quality checks run at ref tips.** The hook runs `check.sh` once per pushed ref, at its tip, from that commit; intermediate commits of the same push are not run individually. The secrets gate, by contrast, covers every commit in the pushed history. In CI both scripts run from the commit under test.
- **A commit can weaken its own gate in CI and in `check.sh`.** CI runs the scripts of the commit under test. Only required Code Owner review of those paths closes this; without it, it is a reviewer's job to catch.
- **The hook runs the pushed code.** `check.sh` comes from the pushed tip and runs with your privileges and environment, with no sandbox, exactly like running the project's tests yourself. Only push commits whose code you have read; to test code you have not reviewed, use a disposable environment without your credentials.
- **Existing hooks and Git LFS.** `core.hooksPath` replaces the hooks directory, so the forge's hook, after its own gates pass, runs the project's previous `pre-push` hook from `$GIT_COMMON_DIR/hooks/` or, if there is none and the repository uses LFS, `git lfs pre-push` (and refuses the push if git-lfs is missing). Without that, LFS objects would not be uploaded.
- **Root commits and checkout hooks.** History scans pass `--root`, so `log.showRoot=false` cannot hide what the first commit adds. Temporary checkouts run with hooks disabled, so a project's `post-checkout` hook cannot run pushed code before the gates.
- **Replacement objects are ignored.** Both the hook and the gate set `GIT_NO_REPLACE_OBJECTS=1`, so `git replace` cannot make them scan different content from what is pushed.
- **Scope in CI.** CI checks only the history of the commit under test (`check_secrets.sh --only HEAD`), so a required check never depends on unrelated branches or tags. On a tag push it fetches the tag object in a step that runs only git (the token lives in that step alone), then checks exactly the object the push event reported, and fails if the tag has moved since. Repository scripts never see the job token: checkouts do not persist it. Verified end to end on 2026-11-26 in a disposable repository with lightweight, clean annotated, secret-bearing and personal-email tags. For a repository-wide audit, run `./scripts/check_secrets.sh` without arguments in a full clone.
- **Commit messages are scanned** separately, since gitleaks only reads patches.
- **The scanner policy is pinned.** `GITLEAKS_CONFIG` and `GITLEAKS_CONFIG_TOML` from your environment are ignored; the gate uses the `.gitleaks.toml` of the checkout it runs in (the trusted revision, in the hook) or gitleaks' built-in rules.
- **Tool versions.** The Linux CI job pins gitleaks by version and checksum. The macOS job deliberately installs the current Homebrew gitleaks and ShellCheck, to catch drift in newer releases; a macOS-only failure after a formula update is a signal to review, not a repository change.
- **The hook guards against mistakes, not against the person pushing.** `git push --no-verify`, or a clone without `core.hooksPath`, skips it entirely. CI and branch protection are the controls that do not depend on the client.
- **What is scanned.** Every local ref (`git log --all`, which includes `refs/stash`) plus each commit being pushed, merge diffs included. A secret in a stash therefore blocks pushes until the stash is dropped. Reflogs and unreachable objects that are not pushed are out of scope.
- **Shallow clones are rejected.** History beyond the shallow boundary could not be checked; run `git fetch --unshallow` (in CI, `fetch-depth: 0`).
- **gitleaks matches known patterns.** It does not find arbitrary personal data in file contents or commit messages. Every diff still needs a human read before it is published.
- **Coverage of the scan.** gitleaks reads git patches. The gate adds `-m` (changes that only exist in merge commits) and `--text` (contents of files git classifies as binary). Files whose content never appears in a patch, such as Git LFS objects (only the pointer is in git) or submodule contents, are not scanned.
- **What the gate prints.** Only the number of findings and the IDs of the commits involved. gitleaks' raw findings include author names, emails and paths, and CI logs of public repositories are public, so they are never printed; inspect them locally.
- **If something sensitive leaks:** revoke or rotate it first. Deleting or rewriting history does not remove copies already made (forks, caches, clones).
