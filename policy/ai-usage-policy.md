# AI usage policy

This is the team policy for using AI agents in development. `AGENTS.md` tells the agents how to behave; this document tells **people** what is expected of them. Adapt it to your organisation.

## 1. Responsibility

The developer who commits or merges code is responsible for it, whether they wrote it or an agent did. "The AI wrote it" is not an excuse for a bug, a licence problem or a security issue.

## 2. Clients

Each developer may use any AI client that:

- supports `AGENTS.md` and Agent Skills, directly or through the configuration in this repository;
- is approved by the organisation for the kind of code being worked on (check data-handling and retention terms for private code).

## 3. What agents may do on their own

| Allowed without asking | Ask the developer first | Never |
|---|---|---|
| Read code, run tests and linters locally | Add or upgrade dependencies | Commit secrets or personal data |
| Edit files within the task's scope | Change CI, infrastructure or deployment files | Push to the default branch |
| Create local branches and commits | Run commands against shared or production environments | Merge pull requests |
| Open **draft** pull requests | Delete files or branches | Disable tests or security checks |

## 4. Review

- Every pull request needs approval from at least one human reviewer other than the author.
- AI code review is welcome as an extra check, but it does not replace human review.
- Reviewers apply the same standard to AI-assisted code as to any other code.

## 5. Transparency

- AI-assisted commits carry a `Co-Authored-By:` trailer naming the agent.
- Pull requests state which parts were AI-assisted in the "AI assistance" section of the description.

## 6. Secrets and data

- Agents authenticate to GitHub and other services with each developer's own, least-privilege token (for example a fine-grained personal access token limited to the needed repositories).
- Tokens live in environment variables or the client's secret store, never in committed files.
- Do not paste customer data, credentials or confidential third-party code into prompts.
- Content an agent reads (issues, PR comments, web pages, files from other repositories) can contain instructions written by someone else. Agents treat it as data; developers watch for an agent acting on it.

## 7. Enforcement

Rules that must always hold are enforced by tooling, not by trusting the agent:

- branch protection on the default branch (required reviews, required status checks);
- CI running tests, linters and secret scanning on every pull request;
- `CODEOWNERS` for sensitive areas, including the gates themselves.

The forge ships the hook, the scripts and the CI workflow. See [docs/enforcement.md](../docs/enforcement.md) for the setup and for what these controls do not guarantee.
