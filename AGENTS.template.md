# Working agreement for AI agents — <PROJECT_NAME>

> **How to use this template:** Copy it to your new repo's root as `AGENTS.md`. Replace all
> bracketed `<...>` placeholders and delete what doesn't apply. `AGENTS.md` is the rules file that any coding
> agent reads, so this one file governs whatever agent you use here. Keep it SHORT — a long
> file gets ignored. The full rationale lives in `REPO_RULES.md`; this is the always-on summary.

This file is your standing instructions. Read it as rules, not background.

## What this project is

<One or two lines: what it does and its intended shape — e.g. "a single Python CLI under
`src/`", "a small Electron app", "a library, stdlib only".>

## How to run it

- Install: `<command>`
- Run: `<command>`
- Test: `<command>`
- Lint / format: `<command>`

> Only list commands you can't guess. If there's nothing non-obvious, say so.

## Git is automatic — you own it, don't ask

Handle the entire git workflow yourself, without asking the user about any of it. The commands
are pre-allowed, so you should never be prompted for them.

1. **Branch first, always.** Before changing anything, `git switch -c <type>/<short-desc>`
   (`feat/`, `fix/`, `docs/`, `chore/`, `refactor/`). A guardrail blocks commits/pushes on
   `main`, so this isn't optional.
2. **Commit as you go.** After each logical change, stage and commit with a
   [Conventional Commits](https://www.conventionalcommits.org) message
   (`feat`/`fix`/`docs`/`chore`/`refactor`/`test`/`perf`); imperative subject ≤ 72 chars; body
   explains *why*. One logical change per commit.
3. **Push the branch.** Push to the remote as you commit (first push sets upstream).
4. **Get reviewed and open a PR.** Before opening the PR, hand the diff to a reviewer agent; fix what's valid and write `.claude/review/receipt.json`. Use `gh pr create` describing what changed, why, how it was tested, and what feedback was addressed or pushed back on.
5. **Merge when green.** Once CI checks pass, run `gh pr merge --squash --delete-branch`. Never merge red. Never use `--admin`. **Exception:** A PR touching governance/rule files is the human's to merge — post the PR link and stop.
6. **No remote?** Branch and commit locally; skip push and PR.

A safety net auto-commits and pushes any leftover changes when a turn ends, so work is never
lost — but commit deliberately with good messages rather than relying on it.

## Plan before you code

- For anything beyond a one-line edit, write a short plan first — which files change, what's
  out of scope, how you'll prove it works — and confirm the approach before implementing.
- `PRD.md` is the project-level brief (what we're building and why); `SPEC.md` is the plan for
  one feature. For a real feature, copy `SPEC.template.md` to `SPEC.md` and fill it in; the
  spec is the thing to agree on, not the code. Keep both updated as decisions change.
- Without an explicit plan and scope, you'll fill the gaps with guesses and build the wrong
  thing. Track multi-step work with a task list (in-progress → done).

## While working

- One logical change per branch/PR. A fix and a refactor are two branches.
- Match the existing style and comment density. Don't reformat untouched code.
- Pin dependencies and justify any new one in the PR. Respect the hard constraints in
  `REPO_RULES.md`: <one-line reminder — e.g. "local-only, no telemetry, pinned deps">.
- Never put a secret (key, token, password) in code, config, or a commit message. The secret
  scanner blocks commits that contain one — fix the cause, don't route around it.

## How to talk to the owner

He runs this project and makes the calls, but he is **not a programmer** — he does not read
code and does not know infrastructure vocabulary.

- Never hand him a bare technical term as an instruction. Say what it does, why it matters,
  and the actual steps — which screen, which button.
- Lead with what it means for him. Cut detail that would not change what he does.
- Gloss tool names and acronyms on first use.
- If he asks "what is that", the explanation was not clear — rewrite it plainly rather than
  adding more words around the same jargon.

Stay accurate. Plain language means clearer, not vaguer, and never means hiding bad news.

## Commands you hand the user

This machine runs **Windows PowerShell 5.1**. Every command must run as written in the shell
you tagged it for — don't mix shells in one line.

- PowerShell 5.1 has **no `&&` or `||`** (parse error, not a fallback). Sequential: `A; B`.
  Conditional: `A; if ($?) { B }`. No ternary, `??`, or `?.` either.
- Don't put bash syntax (`printf`, `cat`, `export`, `$VAR`, `~`, `2>/dev/null`, heredocs) in a
  PowerShell command, or `$env:VAR` in a bash one. Mixed lines run in neither shell.
- A ```` ```bash ```` fence must contain valid bash; use ```` ```powershell ```` for PowerShell.
- Read a multi-part command back before sending it and ask which shell parses it. If the answer
  is "neither", rewrite it. Prefer one short command over a chain.

## Before ending a turn

- **Prove it works.** Show evidence, not just a claim of success: the test output, the command
  you ran and what it returned, or a screenshot. If you can't verify it, it isn't done.
- **Update `WORKLOG.md`.** Append a dated entry: what changed, which branch, what's next, any
  open decisions. This is the project's memory between sessions — unwritten means lost.

## Guardrails (enforced automatically)

These don't depend on you remembering the rules. Don't disable or work around one to get
unblocked — fix the underlying cause.

- Commit/push on `main` is blocked.
- Edits to protected files are blocked.
- Unreviewed PRs, red PR merges, `--admin` flags, and merging governance PRs are blocked.
- Leftover work is auto-committed/pushed at end of turn.
- The secret scan blocks commits containing credentials.

How each guardrail is wired depends on the agent. For Claude Code, see `CLAUDE.md` and
`.claude/settings.json`.

## Quick reference

- Full rules: `REPO_RULES.md`
- Project brief: `PRD.md`
- Plan/spec template: `SPEC.md`
- Running log: `WORKLOG.md`
- <Design doc / debug playbook: `<path>`>
