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
- Gate integration tests (`tests/test_gates.sh`) against throwaway repositories and a local bare remote.

### Security

- Secrets gate scans merge diffs (`git log -m`), reads paths NUL-delimited, scans commits passed by the hook even when no ref points to them, fails closed if gitleaks errors or scans nothing, and rejects shallow clones.
- `pre-push` never uses the working copy's scanner: it runs the secrets gate committed on the remote's default branch (or, on a first push, each pushed commit's own).
- Installer refuses to write through symlinked directories and never follows a symlinked destination.
- CI actions pinned to a full commit SHA.
