---
name: commit-message
description: Write a git commit message in Conventional Commits format for the staged changes. Use when committing, or when asked to write or fix a commit message.
---

# Commit message

1. Read the staged changes with `git diff --staged`. If nothing is staged, ask the developer what to stage. Do not run `git add -A` on your own.
2. Check that no secrets, `.env` files, credentials or large generated files are staged. If any are, stop and tell the developer.
3. Write the message:

```
<type>(<optional scope>): <summary in imperative mood, max 72 chars>

<body: what changed and why, wrapped at 72 chars. Skip if the summary says it all.>

<footers: BREAKING CHANGE: ..., Refs: #123, Co-Authored-By: ...>
```

Types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`.

Rules:

- The summary says what the commit does ("add rate limit to login"), not what you did ("added", "updated stuff").
- The body explains why, when it isn't obvious from the code.
- Add `BREAKING CHANGE:` in the footer, and `!` after the type, for incompatible changes.
- Reference the issue if there is one.
- Add a `Co-Authored-By:` trailer for the agent if the client does not add one itself.
- One logical change per commit. If the staged changes mix unrelated work, suggest splitting them.

4. Show the message to the developer and commit with it once they agree, unless they already asked you to commit directly.
