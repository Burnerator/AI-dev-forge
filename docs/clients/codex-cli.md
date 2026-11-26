# Codex CLI

## Rules

Codex CLI reads `AGENTS.md` natively, from the repository root and from nested folders. Nothing else is needed.

## Skills

Codex scans `.agents/skills/` in every folder from the current working directory up to the repository root, which is exactly where the installer puts the forge's skills. Personal skills go in `~/.agents/skills/`.

## MCP

Codex keeps MCP servers in `~/.codex/config.toml` (user level). Add the GitHub MCP server:

```toml
[mcp_servers.github]
url = "https://api.githubcopilot.com/mcp/"
bearer_token_env_var = "GITHUB_PAT"
```

Then export your token before starting Codex:

```bash
export GITHUB_PAT=<your fine-grained token>
codex
```

See the Codex documentation for the current list of configuration options, including project-level configuration.

## Check that it works

In the project, start Codex and ask:

- "What are the rules for this repository?" It should answer from `AGENTS.md`.
- "Which skills do you have?" It should list `code-review`, `commit-message` and `open-pull-request`.
