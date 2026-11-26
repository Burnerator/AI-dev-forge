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
# Prompt for the token without echoing it or saving it in shell history:
read -rs -p "GitHub token: " GITHUB_PAT && export GITHUB_PAT && echo
codex
```

Better still, keep the token in your OS secret store and load it from there, for example on macOS: `export GITHUB_PAT="$(security find-generic-password -s github-mcp -w)"`. Never paste it into a file in the repository.

See the Codex documentation for the current list of configuration options, including project-level configuration.

## Check that it works

In the project, start Codex and ask:

- "What are the rules for this repository?" It should answer from `AGENTS.md`.
- "Which skills do you have?" It should list `code-review`, `commit-message` and `open-pull-request`.
