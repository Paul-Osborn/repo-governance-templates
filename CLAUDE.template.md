# <PROJECT_NAME> — Claude Code entry point

> **How to use this template:** copy to your repo root as `CLAUDE.md`. Claude Code reads it
> automatically every session. To avoid two copies of the rules, it just **points at
> `AGENTS.md`** (which every agent reads) and adds the few Claude-specific bits. Edit
> `AGENTS.md` for the actual rules.

The project rules live in `AGENTS.md`. Read it now and treat it as standing instructions:

@AGENTS.md

## Claude-specific notes

- **Git is hands-off and pre-authorized.** `.claude/settings.json` allowlists the `git` and PR
  commands, so you're never prompted. Run the whole workflow from `AGENTS.md` yourself:
  branch → commit → push (to every remote) → review → open PR → merge when green.
- **Guardrails are wired here.** `.claude/settings.json` activates:
  - `.claude/hooks/git-guard.ps1` — `--no-verify` block, branch guard, redirection guard,
    review receipt, green-CI merge gate, authority ceiling.
  - `.claude/hooks/protect-paths.ps1` — denies edits to the rules and gates.
  - `.claude/hooks/auto-commit.ps1` — Stop hook; saves leftover work at end of turn.

  Don't work around a blocked action — fix the cause.
- **The reviewer.** `.claude/agents/code-reviewer.md` is a Sonnet 5 read-only specialist and
  the **only** subagent you should routinely spawn. Invoke it **once**, after implementation
  is finished and verified, then record the result in `.claude/review/receipt.json`. Ordinary
  work needs zero implementation subagents.
- **Plan mode for non-trivial work** — explore and plan, then implement. Plan once; don't come
  back for permission on ordinary implementation decisions (see "Autonomy" in `AGENTS.md`).
- **Keep this file short.** Real rules go in `AGENTS.md` so every agent sees them.
