# GitHub Copilot

> **Verification status (2026-11-26):** the paths and settings below follow the vendor's documentation and the cross-client conventions; the maintainers have not yet verified them end to end in this client. If something differs in your version, please open an issue with the version you tested. Only the installer's output and the forge's gates are covered by tests.

Applies to Copilot agent mode in VS Code, Visual Studio and JetBrains IDEs, GitHub Copilot CLI, and Copilot cloud agent and code review on GitHub.com. Feature support varies by IDE and version; check GitHub's Copilot feature matrix.

## Rules

Copilot reads `AGENTS.md` at the repository root. You do not need `.github/copilot-instructions.md`; if your project already has one, keep only Copilot-specific notes there and move shared rules to `AGENTS.md`.

## Skills

Copilot loads project skills from `.github/skills/`, `.claude/skills/` or `.agents/skills/`. The forge's `.agents/skills/` is picked up directly. Personal skills go in `~/.copilot/skills/` or `~/.agents/skills/`.

## MCP

### VS Code

`template/.vscode/mcp.json` configures the GitHub MCP server. VS Code asks for your token the first time and stores it securely. Start the server from the MCP view or the `MCP: List Servers` command.

### Copilot cloud agent

The cloud agent has access to the GitHub MCP server by default. Additional servers are configured in the repository settings on GitHub (Copilot, then cloud agent).

## Check that it works

In agent mode, ask:

- "What are the rules for this repository?" It should answer from `AGENTS.md`.
- "Which skills do you have?" It should list `code-review`, `commit-message` and `open-pull-request`.
