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
