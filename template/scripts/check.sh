#!/usr/bin/env bash
# Quality gate: lint + tests. Run by the pre-push hook and by CI (forge-gates.yml).
# TODO: replace the block below with your project's real commands, for example:
#   ruff check . && ruff format --check . && pytest
#   npm ci && npm run lint && npm test
#   go vet ./... && go test ./...
set -euo pipefail
cd "$(dirname "$0")/.."

echo "ERROR: scripts/check.sh is not configured yet." >&2
echo "Edit it with this project's lint and test commands (see AGENTS.md)." >&2
exit 1
