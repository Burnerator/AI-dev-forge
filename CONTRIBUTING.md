# Contributing to AI-dev-forge

Thanks for helping. The forge is only useful if it reflects how real teams work, so contributions from any team or company are welcome: new skills, guides for more clients, shared MCP servers, fixes and honest bug reports.

By taking part you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md). Security problems go through [SECURITY.md](SECURITY.md), never a public issue.

## What we're looking for

- **Skills:** workflows your team repeats (release notes, dependency upgrades, incident write-ups…).
- **Client guides:** setup for clients not yet covered (Cursor, Gemini CLI, Zed, …).
- **MCP servers:** shared server configs that are broadly useful.
- **Gates:** improvements to the hook, the secrets gate or CI, always with a regression test.
- **Fixes:** anything outdated or wrong. Clients change fast.

Not sure if something fits? Open an issue first. For larger changes, always open an issue first.

## Set up your clone

You need `git`, `bash`, [`shellcheck`](https://www.shellcheck.net) and [`gitleaks`](https://github.com/gitleaks/gitleaks#installing). On macOS: `brew install shellcheck gitleaks`.

```bash
git clone https://github.com/Burnerator/AI-dev-forge.git   # or your fork
cd AI-dev-forge
git config core.hooksPath .githooks                         # enable the pre-push gates
git fetch origin && scripts/trust-scanner.sh refs/remotes/origin/main  # pin the reviewed scanner, after reading it
git config user.email "<id>+<login>@users.noreply.github.com"  # never a personal email
```

The repository is public. Your commit email ends up in the history, so use your GitHub noreply address (GitHub → Settings → Emails). The secrets gate rejects any other address.

## Run the checks

```bash
./scripts/check.sh          # bash -n, shellcheck, JSON, skill frontmatter, all tests
./scripts/check_secrets.sh  # no .env in history, no leaked keys, noreply identities
```

`check.sh` runs `tests/test_install.sh` (installer) and `tests/test_gates.sh` (the hook and the secrets gate against throwaway repositories and a local bare remote). Changes to the CI tag path should also be checked on GitHub with `tests/e2e/github-tags.sh <owner/disposable-repo>`. Both must pass before you push; the `pre-push` hook runs them for you, and CI runs them again on Ubuntu and macOS.

Never use `git push --no-verify`. If a gate blocks you and you think it is wrong, open an issue.

## Make a change

1. Branch from `main`: `feat/…`, `fix/…`, `docs/…`, `test/…`, `chore/…`.
2. Make the change, with a test when behaviour changes. Changes to the gates (`template/.githooks/`, `template/scripts/`, `scripts/`, `.github/workflows/`) need a regression test that fails without your fix.
3. Update `CHANGELOG.md` under `[Unreleased]`, and the docs your change affects (client guides, `README.md` tables, `docs/enforcement.md`).
4. Commit with [Conventional Commits](https://www.conventionalcommits.org): `feat: add release-notes skill`.
5. Open a pull request using the template, including the **AI assistance** section.

### Adding a skill

- One folder per skill under `skills/<name>/` with a `SKILL.md` that follows the [Agent Skills specification](https://agentskills.io/specification): YAML frontmatter with `name` (equal to the folder name) and `description`. `check.sh` verifies both.
- Write the `description` so an agent can tell when to use the skill and when not to.
- Keep skills client-neutral. If a step only works in one client, say so.
- Skills must respect `template/AGENTS.md`: ask before pushing, posting or deleting, and never bypass the gates.

### Adding a client guide

Add `docs/clients/<client>.md` with the same sections as the existing guides (Rules, Skills, MCP, Check that it works) and a row in the README's client table. Only document behaviour you have verified in that client, with the version you tested.

### Adding an MCP server

Add it to every client config (`template/.mcp.json`, `template/.vscode/mcp.json` and the Codex guide) under the same name, keep secrets in environment variables or prompted inputs, and document its purpose and minimum permissions in `docs/mcp.md`.

## AI-assisted contributions

AI assistance is welcome; this project is about it. The rules are those of [policy/ai-usage-policy.md](policy/ai-usage-policy.md):

- you are responsible for every line you submit, whoever or whatever wrote it;
- mark AI-assisted commits with a trailer such as `Co-Authored-By:` or `Assisted-by:` naming the tool;
- say in the pull request which parts were AI-assisted and what you checked by hand.

## Review and merge

- `main` is protected (maintainers configured these settings and verified them through the GitHub API on 2026-11-26; if you see otherwise, open an issue): changes land only through pull requests, with CI green (`secrets`, `checks (ubuntu-latest)`, `checks (macos-latest)`), conversations resolved, and **one approving review from a maintainer other than the last person who pushed**. Code Owners (see [.github/CODEOWNERS](.github/CODEOWNERS)) must approve changes to the gates. Nobody, admins included, can bypass this.
- Maintainers may also run an independent AI review on a pull request and post its summary there. It complements human review; it never replaces it.
- Pull requests are squash-merged with a Conventional Commit title.

## Maintainers

The current maintainers are listed in [.github/CODEOWNERS](.github/CODEOWNERS). Decisions are made in the open, in issues and pull requests; when maintainers disagree, the change waits until they agree.

## License

Contributions are licensed under the [Apache License 2.0](LICENSE), the project's license (inbound = outbound, as in section 5 of the license). There is no CLA.
