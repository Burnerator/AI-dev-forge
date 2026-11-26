# Changelog

All notable changes to this project are documented here. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning: [SemVer](https://semver.org).

## [Unreleased]

### Added

- Base rules (`template/AGENTS.md`) and a `CLAUDE.md` that imports them.
- Shared skills: `code-review`, `commit-message`, `open-pull-request`.
- GitHub MCP server config for Claude Code and VS Code/Copilot; Codex instructions.
- Gates for adopting projects: `pre-push` hook, `scripts/check.sh`, `scripts/check_secrets.sh`, `forge-gates` CI workflow and a PR template with AI disclosure.
- Team AI usage policy, per-client guides, and an enforcement guide with its limits.
- Installer (`scripts/install.sh`) with `--dry-run` and `--force`, and its tests.
- Contribution docs: `CONTRIBUTING.md` (setup, checks, adding skills, guides and MCP servers, review rules), `SECURITY.md`, `CODE_OF_CONDUCT.md`, `CODEOWNERS` and issue templates.
- Gate integration tests (`tests/test_gates.sh`) against throwaway repositories and a local bare remote.

### Security

- Secrets gate scans merge diffs (`git log -m`), reads paths NUL-delimited, scans commits passed by the hook even when no ref points to them, fails closed if gitleaks errors or scans nothing, and rejects shallow clones.
- `pre-push` runs the secrets gate only from an explicitly trusted scanner, never from the working copy, the pushed commits or the push destination; it fails closed when none is set. Bootstrap needs an explicit `FORGE_BOOTSTRAP=1`.
- Secrets gate scans the contents of binary files (`--text`), distinguishes findings from operational errors, and prints only a count and commit IDs, never raw findings.
- Installer refuses targets inside the forge checkout, and verifies (or with `--force` repairs) the `.claude/skills` link.
- The secrets gate checks annotated tags, nested ones included (messages and tagger emails), and ignores inline `gitleaks:allow` comments.
- `install.sh --force` overwrites the forge's skill files and keeps project-only files, and replaces a symlink in place of a skill directory.
- Secrets gate scans commit messages; `--only` limits a scan to given revisions, used by CI so required checks depend only on the commit under test; CI checkouts no longer persist the job token.
- `trust-scanner.sh` resolves every path component inside the pinned tree (links through linked directories included) and requires the scanner to end at a tracked executable; the hook chains `forge.previousHook` for projects with a custom `core.hooksPath`, and detects LFS in the pushed commits.
- `trust-scanner.sh` refuses links that leave the repository and never pins after a failed review; CI fetches the tag object before any repository code runs; scanner policy files must not be symlinks; the hook recognises SHA-256 deletions; installer preflight follows the copy phase's skip rule.
- The hook runs the project's previous `pre-push` hook, or `git lfs pre-push` in LFS repositories, after its gates; `trust-scanner.sh` follows symlinks and shows full files on the first pin; `.envrc` is blocked too.
- CI fetches the annotated tag object in a git-only, token-scoped step (`actions/checkout` rewrites a checked-out tag to its commit); verified end to end with lightweight, annotated, secret-bearing and personal-email tags.
- The hook trusts a pinned scanner commit (`forge.trustedCommit`, set with `scripts/trust-scanner.sh`, which shows the diff) instead of a ref that moves on fetch; installer preflight rejects a file in place of a skill directory.
- Secrets gate scans root commits regardless of `log.showRoot` and reads the tagger only from the tag header; temporary checkouts run with hooks disabled; Codex and Copilot guides state their verification status.
- Secrets gate ignores `GITLEAKS_CONFIG`/`GITLEAKS_CONFIG_TOML` overrides; the hook stops if it cannot create a clean checkout; installer preflight also rejects files where directories are needed and vice versa.
- CI on a tag push verifies the exact tag object from the push event (`check_secrets.sh --tag`), with no token exposed; the installer preflights every destination before writing; the `open-pull-request` skill opens drafts by default.
- Hook and gate ignore replacement objects (`GIT_NO_REPLACE_OBJECTS=1`); CI scans a pushed annotated tag explicitly.
- Installer refuses to write through symlinked directories and never follows a symlinked destination.
- CI actions pinned to a full commit SHA.
