#!/usr/bin/env bash
# Quality gate for AI-dev-forge itself. Run by the pre-push hook and by CI.
set -euo pipefail
cd "$(dirname "$0")/.."

shell_files=(scripts/install.sh template/scripts/check.sh template/scripts/check_secrets.sh template/scripts/trust-scanner.sh
  template/.githooks/pre-push tests/test_install.sh tests/test_gates.sh tests/e2e/github-tags.sh scripts/check.sh)

echo "==> bash -n"
for f in "${shell_files[@]}"; do bash -n "$f"; done

echo "==> shellcheck"
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck "${shell_files[@]}"
else
  echo "ERROR: shellcheck not installed (macOS: brew install shellcheck)." >&2
  exit 1
fi

echo "==> JSON configs parse"
for f in template/.mcp.json template/.vscode/mcp.json; do
  python3 -m json.tool "$f" >/dev/null
done

echo "==> skills frontmatter (name == folder, description present)"
for d in skills/*/; do
  name="$(basename "$d")"
  f="$d/SKILL.md"
  [[ -f "$f" ]] || { echo "ERROR: $f missing" >&2; exit 1; }
  [[ "$(head -1 "$f")" == "---" ]] || { echo "ERROR: $f has no frontmatter" >&2; exit 1; }
  fm="$(awk 'NR==1{next} /^---$/{exit} {print}' "$f")"
  grep -qx "name: $name" <<<"$fm" || { echo "ERROR: $f name does not match folder" >&2; exit 1; }
  grep -q '^description: .\+' <<<"$fm" || { echo "ERROR: $f has no description" >&2; exit 1; }
done

echo "==> installer tests"
bash tests/test_install.sh

echo "==> gate integration tests (needs gitleaks)"
command -v gitleaks >/dev/null 2>&1 || { echo "ERROR: gitleaks not installed." >&2; exit 1; }
bash tests/test_gates.sh

echo "==> OK: all checks passed"
