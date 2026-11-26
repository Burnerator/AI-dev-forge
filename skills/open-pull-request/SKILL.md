---
name: open-pull-request
description: Prepare and open a GitHub pull request for the current branch. Use when asked to open, create or draft a PR, or to push work for review.
---

# Open a pull request

## 1. Check the branch

- Confirm you are not on the default branch. If you are, create a branch named `<type>/<short-description>` and move the work there.
- Make sure the working tree is clean, or ask the developer what to do with uncommitted changes.
- Run the tests and the linter from `AGENTS.md`. If they fail, report it and ask before opening the PR.

## 2. Review your own diff

Read `git diff <default-branch>...HEAD`. Remove debug output, commented-out code and unrelated changes. Check that no secrets are included.

## 3. Write the description

```markdown
## What

<one or two sentences on what this PR changes>

## Why

<the problem or the issue it solves; link it: Closes #123>

## How

<key implementation decisions, anything a reviewer should look at closely>

## Testing

<what was run, what was added, how to verify manually>

## AI assistance

<which parts were AI-generated or AI-assisted, and what the author checked>
```

Keep it short. A reviewer should understand the PR in under a minute.

## 4. Open it

- Push the branch: `git push -u origin <branch>`.
- Open the PR with the GitHub MCP server or `gh pr create --title "<conventional-commit-style title>" --body-file <file>`.
- Open it as a **draft** unless the developer says it is ready for review.
- Do not request reviewers, add labels or merge unless asked.

Report the PR URL to the developer when done.
