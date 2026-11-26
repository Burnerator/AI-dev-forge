# Contributing to AI-dev-forge

Thanks for helping. The forge is only useful if it reflects how real teams work, so contributions from any team or company are welcome.

## What we're looking for

- **Skills:** workflows your team repeats (release notes, dependency upgrades, incident write-ups…).
- **Client guides:** setup instructions for clients not yet covered (Cursor, Gemini CLI, Zed, …).
- **MCP servers:** shared server configs that are broadly useful.
- **Fixes:** anything outdated or wrong, since clients change fast.

## Guidelines

- Skills follow the [Agent Skills specification](https://agentskills.io/specification): one folder per skill under `skills/`, a `SKILL.md` with `name` and `description` in the frontmatter, and the folder name matching `name`.
- Write the skill `description` so an agent can tell when to use it and when not to.
- Keep skills client-neutral. If a step only works in one client, say so.
- Don't add anything to `template/AGENTS.md` that is specific to one project or one company.
- Use [Conventional Commits](https://www.conventionalcommits.org) for commit messages.
- Mark AI-assisted contributions as described in [policy/ai-usage-policy.md](policy/ai-usage-policy.md).

## Process

1. Open an issue to discuss larger changes first.
2. Fork, branch, make the change, and open a pull request.
3. A maintainer reviews it. Every pull request needs one approving human review.

By contributing, you agree that your contributions are licensed under the [Apache License 2.0](LICENSE).
