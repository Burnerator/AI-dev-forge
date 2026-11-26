# AGENTS.md

Instructions for AI agents working on the AI-dev-forge repository itself.
(The rules that the forge installs into other projects are in `template/AGENTS.md`.)

## What this repository is

A template, not an application: Markdown, JSON and a few shell scripts. There is nothing to build.

## Checks before finishing

Run `./scripts/check.sh`. It runs `bash -n` and `shellcheck` on every shell script, parses the JSON configs, checks each skill's frontmatter (`name` equal to the folder, `description` present) and runs the installer tests in `tests/test_install.sh`. The `pre-push` hook and CI run the same script, plus `./scripts/check_secrets.sh`.

## Rules

- Follow `CONTRIBUTING.md`.
- Keep `template/AGENTS.md` generic: nothing specific to one project or company.
- When you change how a client is configured, update its guide in `docs/clients/` and the table in `README.md`.
- Gate files (`template/.githooks/`, `template/scripts/`, `scripts/check.sh`, `.github/workflows/`) change only when the task is about them, and the PR explains why.
- Use Conventional Commits. Never push to `main`; open a pull request.
