---
name: code-review
description: Review code changes for bugs, security issues and maintainability. Use when asked to review local changes, a diff, a branch or a GitHub pull request. Not for writing new features.
---

# Code review

## 1. Find what to review

- **Local changes:** `git diff` for unstaged work, `git diff --staged` for staged work, or `git diff <base>...HEAD` for a branch (default base: the repository's default branch).
- **Pull request:** use the GitHub MCP server or `gh pr diff <number>` and `gh pr view <number>` to read the diff, description and linked issue.

Read the description or task first, so you review against what the change is meant to do.

## 2. Understand the context

For each changed file, read enough of the surrounding code to understand how the change is used: callers, tests and related modules. Do not review a diff hunk in isolation.

## 3. Check, in this order

1. **Correctness:** logic errors, off-by-one errors, null or empty handling, error paths, concurrency, behaviour changes that the description does not mention.
2. **Security:** injection, missing authorization checks, secrets in code, unsafe deserialization, unvalidated input reaching files, the shell or SQL.
3. **Tests:** is the new behaviour tested? Would the tests fail if the change were wrong? Were existing tests weakened or deleted?
4. **Maintainability:** unclear names, duplicated logic, dead code, missing docs for public APIs.
5. **Project rules:** anything in `AGENTS.md` that the change breaks.

Run the tests and the linter when you can, and include the results.

## 4. Report

Group findings by severity:

- **Blocking:** bugs, security issues, broken tests. Each one gets file and line, what goes wrong, and a concrete scenario that triggers it.
- **Should fix:** real problems that are not urgent.
- **Suggestions:** style and optional improvements. Keep these short.

Only report what you have verified by reading the code. If you are unsure, say so instead of presenting a guess as a finding. End with a one-line verdict: approve, approve with comments, or request changes.

Do not post comments on a pull request or approve it on GitHub unless the developer asks you to.
