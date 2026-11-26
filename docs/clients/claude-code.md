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
export GITHUB_PAT=<your fine-grained token>
claude
```

Claude Code asks you to approve project MCP servers the first time. Check them with `/mcp`.

## Check that it works

In the project, start Claude Code and ask:

- "What are the rules for this repository?" It should answer from `AGENTS.md`.
- `/skills` or "Which skills do you have?" It should list `code-review`, `commit-message` and `open-pull-request`.
