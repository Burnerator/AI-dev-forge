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
- `pre-push` runs the secrets gate only from an explicitly trusted local ref (`forge.trustedRef`), never from the working copy, the pushed commits or the push destination; it fails closed when unset. Bootstrap needs an explicit `FORGE_BOOTSTRAP=1`.
- Secrets gate scans the contents of binary files (`--text`), distinguishes findings from operational errors, and prints only a count and commit IDs, never raw findings.
- Installer refuses targets inside the forge checkout, and verifies (or with `--force` repairs) the `.claude/skills` link.
- The secrets gate checks annotated tags, nested ones included (messages and tagger emails), and ignores inline `gitleaks:allow` comments.
- `install.sh --force` overwrites the forge's skill files and keeps project-only files, and replaces a symlink in place of a skill directory.
- Hook and gate ignore replacement objects (`GIT_NO_REPLACE_OBJECTS=1`); CI scans a pushed annotated tag explicitly.
- Installer refuses to write through symlinked directories and never follows a symlinked destination.
- CI actions pinned to a full commit SHA.
