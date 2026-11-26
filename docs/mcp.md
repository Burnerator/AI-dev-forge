# Shared MCP servers

MCP servers give agents the same tools in every client. Each client stores the configuration in its own file, so the forge ships one config per client with the same servers:

| Client | File | Scope |
|---|---|---|
| Claude Code | `.mcp.json` | Project (committed) |
| VS Code / Copilot | `.vscode/mcp.json` | Project (committed) |
| Codex CLI | `~/.codex/config.toml` | User (see [codex-cli.md](clients/codex-cli.md)) |

## Default server: GitHub

The forge configures GitHub's remote MCP server at `https://api.githubcopilot.com/mcp/`. It lets agents read issues and pull requests, open PRs, read CI results and more.

Authenticate with a **fine-grained personal access token** limited to the repositories and permissions you need. Never commit the token: the configs read it from the `GITHUB_PAT` environment variable (Claude Code, Codex) or ask for it at startup (VS Code).

## Adding a server for the team

1. Add it to **all** the client configs above, with the same name.
2. Keep secrets out of the files: use environment variables or prompted inputs.
3. Document what it is for and which permissions it needs in this file.
4. Open a pull request against AI-dev-forge so every project can pick it up.
