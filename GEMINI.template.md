# <PROJECT_NAME> — Antigravity entry point

> **How to use this template:** copy to `GEMINI.md` at the repo root. Google Antigravity reads
> this file (highest priority) and, on v1.20.3+, also reads `AGENTS.md`. Keep the real rules in
> `AGENTS.md`; this file is a pointer plus any Antigravity-only overrides.

**Before touching any code, open `AGENTS.md` in the repo root and follow it as your standing
instructions.** It is the single source of truth: autonomy boundaries (decide, don't ask), the
git workflow (branch → commit → push to every remote → review → open PR → merge green PR), one
cohesive deliverable per branch, lean engineering, subagent economy, verification, and the
guardrails.

## Antigravity-specific notes

- <Add Antigravity-only overrides here. Anything here takes priority over `AGENTS.md`.>
- Git is hands-off: run the full workflow yourself without asking, and merge when CI is green.
- The gates in `lefthook.yml` (branch guard, secret scan, large-file limit) apply to you the
  same as to everyone else. The `.claude/` hooks do not — so the rules in `AGENTS.md` are the
  only thing standing between you and the mistakes they prevent. Read them properly.
