# Security policy

AI-dev-forge ships security controls (a secrets gate, a `pre-push` hook, CI workflows) that other projects rely on. A bypass in them is a vulnerability even if it needs unusual input.

## Reporting a vulnerability

**Do not open a public issue.** Report it privately through GitHub: [Report a vulnerability](https://github.com/Burnerator/AI-dev-forge/security/advisories/new) (Security tab → Report a vulnerability).

Please include what you found, how to reproduce it (a minimal repository or script is ideal), and the impact you expect. Never include real secrets; use generated test values.

## What to expect

- We acknowledge reports within 7 days and keep you updated while we work on a fix.
- We coordinate disclosure with you. By default we publish an advisory once a fix is released, or after 90 days, whichever comes first.
- We credit you in the advisory unless you prefer otherwise.

## Scope

In scope: `scripts/`, `template/` (hook, gate scripts, CI workflow, configs) and anything in the docs that would lead users to an insecure setup.

Out of scope: vulnerabilities in third-party tools the forge uses (gitleaks, GitHub Actions, AI clients, MCP servers). Report those to their maintainers. The limits listed in [docs/enforcement.md](docs/enforcement.md) are known and documented, not vulnerabilities, unless the documentation is wrong.
