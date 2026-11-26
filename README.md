# AI-dev-forge

A shared, client-agnostic setup for AI-assisted software development.

Every developer keeps their own forge (their machine, their AI client, their workflow), but the whole team shares one set of **rules**, **skills** and **tools**. AI-dev-forge packages those shared pieces using open standards hosted by the [Agentic AI Foundation](https://aaif.io), so they work the same way whichever client each person uses.

| Layer | Standard | What it holds | Where it lives |
|---|---|---|---|
| Rules | [AGENTS.md](https://agents.md) | Project conventions: build, test, style, boundaries | `AGENTS.md` |
| Skills | [Agent Skills](https://agentskills.io) | Repeatable workflows: review, commit, open a PR | `.agents/skills/<name>/SKILL.md` |
| Tools | [MCP](https://modelcontextprotocol.io) | Shared connections: GitHub, issue tracker, docs | `.mcp.json`, `.vscode/mcp.json`, Codex `config.toml` |
| Policy | — (team-defined) | What agents may do on their own, attribution, review | `policy/ai-usage-policy.md` |
| Gates | git hooks + CI + branch protection | What must always hold: no secrets, lint and tests pass, reviewed merges | `.githooks/`, `scripts/`, `.github/` |

Anything that **must** hold is checked by deterministic tooling instead of the model: the `pre-push` hook runs the secrets gate and your lint and tests on each clone before anything is published; CI runs the same gates after every push and on pull requests; branch protection on GitHub makes merging to `main` depend on them and on review. The AI rules help developers meet those requirements; the tooling enforces them, each at its own point in time. The forge ships those gates too. They hold only as far as the repository settings back them (branch protection, required checks and required Code Owner review of the gate files): [docs/enforcement.md](docs/enforcement.md) maps each rule to its gate and says plainly what the gates do not cover.

## Supported clients

| Client | Reads rules from | Reads skills from | Guide |
|---|---|---|---|
| Claude Code | `CLAUDE.md` (which imports `AGENTS.md`) | `.claude/skills/` (symlinked to `.agents/skills/`) | [docs/clients/claude-code.md](docs/clients/claude-code.md) |
| Codex CLI | `AGENTS.md` | `.agents/skills/` | [docs/clients/codex-cli.md](docs/clients/codex-cli.md) |
| GitHub Copilot | `AGENTS.md` | `.agents/skills/` | [docs/clients/github-copilot.md](docs/clients/github-copilot.md) |

`AGENTS.md` and `.agents/skills/` are the single source of truth. Client-specific files only point at them.

## Quick start

Apply the forge to one of your projects:

```bash
git clone https://github.com/Burnerator/AI-dev-forge.git
./AI-dev-forge/scripts/install.sh /path/to/your/project
```

The installer:

1. copies `template/AGENTS.md`, `template/CLAUDE.md`, the MCP configs and the gates (`pre-push` hook, `scripts/check.sh`, `scripts/check_secrets.sh`, CI workflow, PR template) into the project, **without overwriting** files that already exist (use `--force` to overwrite, `--dry-run` to preview);
2. copies every skill from `skills/` into `.agents/skills/`;
3. creates `.claude/skills` as a symlink to `.agents/skills` so Claude Code finds the same skills.

Then, in the project:

1. **Before your next commit**, set a GitHub noreply identity: `git config user.email "<id>+<login>@users.noreply.github.com"` (find yours under GitHub → Settings → Emails). The secrets gate flags any other author or committer email in the history. With the hook enabled, that blocks the push before anything is published; CI flags it too, but only after the push.
2. Run the preflight on the existing history: `./scripts/check_secrets.sh` (needs [gitleaks](https://github.com/gitleaks/gitleaks) and a full, non-shallow clone). In an existing project it may report `.env` files, keys or personal emails from the past. Either clean the history before publishing, or, if your team legitimately commits with corporate addresses in a private repository, adjust the identity pattern in `scripts/check_secrets.sh` through a reviewed pull request.
3. Edit `AGENTS.md`: fill in the build and test commands and anything project-specific.
4. Put your real lint and test commands in `scripts/check.sh`. It fails on purpose until you do.
5. Enable the hook in each clone: `git config core.hooksPath .githooks`.
6. Commit the result so every collaborator gets it. The first push that brings the forge to an existing remote needs `FORGE_BOOTSTRAP=1 git push …`, because the remote has no reviewed scanner yet ([details](docs/enforcement.md)).
7. Protect `main` and require the `forge-gates` checks: see [docs/enforcement.md](docs/enforcement.md).

## Repository layout

```
AGENTS.md                 Rules for working on this repository itself
template/                 Files the installer copies into a project
  AGENTS.md               Base team rules (edit per project)
  CLAUDE.md               One-line import of AGENTS.md for Claude Code
  .mcp.json               MCP servers for Claude Code
  .vscode/mcp.json        MCP servers for VS Code / Copilot
  .githooks/pre-push      Runs the gates on the exact commits being pushed
  scripts/check.sh        Lint + tests (fill in per project)
  scripts/check_secrets.sh  No .env in history, gitleaks, noreply emails
  .github/                CI workflow (forge-gates) and PR template with AI disclosure
skills/                   Shared Agent Skills
  code-review/
  commit-message/
  open-pull-request/
policy/                   Team policy on AI use
docs/                     Per-client guides, MCP notes, enforcement and its limits
scripts/install.sh        Installer
tests/                    Installer and gate integration tests (run in CI)
```

## Contributing

Contributions are welcome, especially new skills and setup guides for more clients. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[Apache License 2.0](LICENSE)
