# Enforcement: what the gates guarantee and what they don't

`AGENTS.md` and the skills are **guidance**. Agents usually follow them, but nothing guarantees it. Anything that must always hold is enforced by deterministic tooling that runs the same way whichever client, or no client, wrote the code.

## Rule → gate

| Rule | Guidance (agent) | Enforced by |
|---|---|---|
| No secrets or `.env` in git | `AGENTS.md`, `commit-message` skill | `scripts/check_secrets.sh` in `pre-push` and CI; GitHub secret scanning + push protection |
| Commit emails are not personal | `AGENTS.md` | `check_secrets.sh` (noreply identities only) |
| Lint and tests pass | `AGENTS.md` | `scripts/check.sh` in `pre-push` (clean worktree) and CI |
| No direct pushes to `main` | `AGENTS.md`, `open-pull-request` skill | Branch protection on `main` |
| Human review of every change | `AGENTS.md`, policy | Branch protection: 1+ required approval, dismiss stale approvals |
| Sensitive paths need an owner | `AGENTS.md` "Do not touch" | `CODEOWNERS` + "Require review from Code Owners" |
| Gates are not weakened silently | `AGENTS.md` | `CODEOWNERS` on `.githooks/`, `scripts/`, `.github/workflows/` |

## Set up branch protection on `main`

In the repository settings (Rules → Rulesets, or Branches → Branch protection):

- require a pull request before merging, with at least one approval;
- dismiss stale approvals when new commits are pushed;
- require status checks to pass: `forge-gates / secrets` and `forge-gates / checks`;
- block force pushes and deletions;
- optionally require review from Code Owners, with a `CODEOWNERS` file such as:

```
/.githooks/          @your-org/maintainers
/scripts/            @your-org/maintainers
/.github/workflows/  @your-org/maintainers
```

Also enable secret scanning and push protection (Settings → Code security).

## Limits: what these controls do not guarantee

- **The hook is client-side.** A clone without `core.hooksPath`, or `git push --no-verify`, skips it. CI on every branch compensates in part.
- **CI runs after publishing.** If a push to a branch contains a secret, it is already public (on a public repo) even if CI fails. Push protection only blocks known key formats.
- **Branch protection covers `main` only.** Other branches accept pushes without review.
- **A commit can weaken its own gate.** The hook runs the `check.sh` of the commit being pushed. Code Owners on the gate files and reviewing their diffs compensate.
- **gitleaks matches known patterns.** It does not find arbitrary personal data in file contents or commit messages. Every diff still needs a human read before it is published.
- **If something sensitive leaks:** revoke or rotate it first. Deleting or rewriting history does not remove copies already made (forks, caches, clones).
