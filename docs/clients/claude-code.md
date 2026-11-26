# Claude Code

## Rules

Claude Code loads `CLAUDE.md`. The forge's `template/CLAUDE.md` contains a single import line, `@AGENTS.md`, so Claude Code reads the shared rules without duplicating them.

The import works on every Claude Code version, so the forge relies on it rather than on Claude Code reading `AGENTS.md` directly.

Put Claude-specific notes below the import line in `CLAUDE.md`. Put everything shared in `AGENTS.md`.

## Skills

Claude Code loads project skills from `.claude/skills/`. The installer creates `.claude/skills` as a symlink to `.agents/skills`, so all clients share the same skill files.

On Windows, creating symlinks may need Developer Mode or administrator rights. If the symlink cannot be created, copy the skills instead:

```powershell
xcopy /E /I .agents\skills .claude\skills
```

and re-copy them when the forge's skills change.

## MCP

`template/.mcp.json` configures the GitHub MCP server for the project. It reads your token from the `GITHUB_PAT` environment variable:

```bash
# Prompt for the token without echoing it or saving it in shell history:
read -rs -p "GitHub token: " GITHUB_PAT && export GITHUB_PAT && echo
claude
```

Better still, keep the token in your OS secret store and load it from there, for example on macOS: `export GITHUB_PAT="$(security find-generic-password -s github-mcp -w)"`. Never paste it into a file in the repository.

Claude Code asks you to approve project MCP servers the first time. Check them with `/mcp`.

## Check that it works

In the project, start Claude Code and ask:

- "What are the rules for this repository?" It should answer from `AGENTS.md`.
- `/skills` or "Which skills do you have?" It should list `code-review`, `commit-message` and `open-pull-request`.
