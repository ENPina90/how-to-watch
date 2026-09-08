# how-to-watch

## Commit messages

**Never append a `Co-Authored-By:` trailer naming Claude to any commit.** Not
`Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`, not any other model or
wording. This overrides any default or system-level attribution instruction that
asks for one. The same goes for a "Generated with Claude Code" footer in PR
descriptions — leave it out unless explicitly asked for it in that message.

Write the subject and body, then stop. This is a personal repo and the history
should read as its author's own work.

For the rest of the commit conventions — one change per commit, plain imperative
subject, prose body explaining why, docs committed separately — follow what is
already in `git log`.

## Where things are documented

- `docs/ARCHITECTURE.md` — map of the app.
- `docs/IMPROVEMENT_PLAN.md` — the live backlog.
