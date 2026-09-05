# Working agreement for AI agents — <PROJECT_NAME>

> **How to use this template:** copy to your repo root as `AGENTS.md` and replace the
> `<...>` placeholders. This is the file every coding agent reads, so it governs whichever
> agent you use. Keep it SHORT — a long rules file gets skimmed and then ignored. Rationale,
> edge cases and recovery procedures live in `REPO_RULES.md`.

These are your standing instructions. Read them as rules, not background.

## What this project is

<One or two lines: what it does and its intended shape — e.g. "a single Python CLI under
`src/`", "a small Electron app", "a library, stdlib only".>

## How to run it

- Install: `<command>`
- Run: `<command>`
- Test: `<command>`
- Lint / format: `<command>`

> Only list what you can't guess.

## Autonomy — decide, don't ask

Once the owner has approved **what you are building**, carry it out. Implementation decisions
are yours — layout, naming, which library call, what to test first. Don't have them
reconfirmed.

Plan first, but plan once. Before anything beyond a one-line edit, write a short plan: which
files change, what's out of scope, how you'll prove it works. That is scope control, not a
second round of permission.

**Stop and ask only when the decision materially changes one of these:**

- what the product does, or the scope of the project
- money — spending, subscriptions, anything billable
- privacy or security boundaries; credentials
- something destructive or hard to reverse (deleting data, rewriting history, force-push)
- a shared or production server's routing, ingress, topology, or a consequential reboot
- a major architectural direction, or a significant dependency the approved plan didn't imply
- these rules, or the limits of your own authority

Everything else: proceed, and say what you did.

`PRD.md` is the project brief (what we're building and why). `SPEC.md` is the plan for one
feature — copy `SPEC.template.md` for anything substantial. Keep both current.

## Git is automatic — you own it, don't ask

The commands are pre-allowed. Never ask permission for any of this.

1. **Branch first, always.** `git switch -c <type>/<short-desc>` (`feat/`, `fix/`, `docs/`,
   `chore/`, `refactor/`). Commits on `main` are physically blocked, so this isn't optional.
2. **Commit as you go**, [Conventional Commits](https://www.conventionalcommits.org):
   imperative subject ≤ 72 chars, body explains *why*. One logical change per commit.
3. **Push as you commit.** If the repo has several remotes, push completed work to all of
   them — `sync-remotes.ps1` does it in one step. One remote is authoritative; the rest are
   mirrors that must reflect finished work.
4. **Review, then open the PR.** See "Review" below.
5. **Merge when green.** `gh pr merge --squash --delete-branch` (GitHub) once CI passes.
   Never merge red. Never `--admin`. **A PR touching governance/rule files is the owner's to
   merge — post the link and stop.**
6. **No remote?** Branch and commit locally; skip push and PR.

A safety net auto-commits and pushes leftovers when a turn ends, so work is never lost — but
commit deliberately rather than relying on it.

## One cohesive deliverable per branch

A branch carries one complete, shippable thing: the implementation, its tests, the supporting
fixes it genuinely needs, small supporting refactors, and its docs.

Split when the work becomes independently useful on its own, or its objective has materially
changed. Defer unrelated cleanup. Avoid both extremes — a chain of micro-PRs nobody can
follow, and one branch holding three unrelated projects.

## Lean engineering — build the smallest complete solution

Before adding code or a dependency, take the highest option that actually works:

1. no change at all — the requirement is already satisfied
2. something this project already has
3. a platform / native capability (`<input type="date">` over a date-picker library, a CSS
   rule over JavaScript, a database constraint over application code)
4. the standard library
5. a dependency already installed
6. a small amount of new code
7. a new dependency — only with a reason you can state in one line

Don't write abstractions with one caller, config for a value that never varies, extension
points nobody asked for, frameworks for tiny tasks, or code that exists because it might be
useful one day. Delete rather than add; boring rather than clever.

Never trade away correctness, security, validation at trust boundaries, error handling that
prevents data loss, accessibility, maintainability, or anything explicitly requested, just to
write fewer lines. Lean means less code, not a flimsier result.

## Subagents — direct execution is the default

Do the work yourself. Spawn a subagent only for:

- genuinely parallel work that doesn't depend on state you're still changing, or
- the one independent final review (below).

Never spawn one to read files, search the repo, run tests, write docs, or implement step by
step. Subagents never spawn subagents. Ordinary work means zero implementation subagents and
at most one reviewer.

## Review

Implement → self-check → targeted verification → stabilise the branch → broader verification →
**one** `code-reviewer` review → fix what's valid → open the PR. Re-review only if your fixes
materially changed what was reviewed.

Don't run a reviewer while the implementation is still moving.

- **Trivial** (typo, small doc fix, cosmetic change with a deterministic check): no reviewer.
  A branch touching only prose is exempt automatically.
- **Normal:** one independent review.
- **High risk** — auth, permissions, credentials, privacy, payments, destructive data
  operations, migrations, deployment, governance: one independent review, always.

Record the outcome in `.claude/review/receipt.json`. The gate checks it against the actual
code, so prose commits after a review don't invalidate it and code commits do.

## Verification — prove it, don't repeat it

While working, run the smallest check that would catch what you just broke — not the whole
suite after every edit. At a meaningful boundary (branch stable, before review, before the
PR), run the broad checks plus any deployment or acceptance checks. High-risk work gets broad
verification regardless.

"Looks done" is not done. Show the command and what it returned. More test runs is not better
verification.

## How to talk to the owner

He runs this project and makes the calls, but he is **not a programmer** — he does not read
code and does not know infrastructure vocabulary.

- Never hand him a bare technical term as an instruction. Say what it does, why it matters to
  him, and the actual steps — which screen, which button. Gloss tool names on first use.
- Lead with what it means for him; cut detail that wouldn't change what he does.
- If he asks "what is that", the explanation wasn't clear — rewrite it plainly rather than
  adding words around the same jargon.

Keep progress reports short. Don't restate the plan, don't narrate each tool call, don't stop
to announce that a routine step worked. Say what changed, what matters, what failed, and what
he needs to decide — then keep going until genuinely blocked. Expand only when it helps him
decide. Plain language means clearer, not vaguer, and never means softening bad news.

## Commands you hand the user

This machine runs **Windows PowerShell 5.1**. Every command must run as written in the shell
you tagged it for — never mix shells in one line.

- PowerShell 5.1 has **no `&&` or `||`** (parse error, not a fallback). Sequential: `A; B`.
  Conditional: `A; if ($?) { B }`. No ternary, `??` or `?.` either.
- No bash syntax (`printf`, `cat`, `export`, `$VAR`, `~`, `2>/dev/null`, heredocs) in a
  PowerShell command, and no `$env:VAR` in a bash one. Mixed lines run in neither shell.
- A ```` ```bash ```` fence must contain valid bash; use ```` ```powershell ```` otherwise.
- Read a multi-part command back and ask which shell parses it. If the answer is "neither",
  rewrite it. Prefer one short command over a chain.

## Hard lines

- **Secrets.** Never put a key, token or password in code, config, or a commit message. The
  scanner blocks it — fix the cause, don't route around it.
- **Lockfiles.** Never hand-edit `package-lock.json`, `poetry.lock` or similar. Change the
  manifest and let the package manager regenerate them, in the same commit.
- **Guardrails.** Don't disable or work around one to get unblocked. If a gate is genuinely
  wrong, that's a rule change: raise it, don't route around it.
- <Project constraints — e.g. "local-only, no telemetry, pinned deps". Full list in `REPO_RULES.md`.>

## Before ending a turn

- **Show your evidence** — the test output, the command and its result, a screenshot.
- **Update `WORKLOG.md`** when work materially advances or you reach a checkpoint another
  session would need. Keep it short and link to the PR or spec instead of repeating it. Don't
  write an entry for a trivial change, and don't make a commit purely to add one.

## Guardrails (enforced automatically, not by memory)

- Commit/push on `main` — blocked.
- Commits containing secrets — blocked.
- Newly added files over the size limit — blocked.
- `--no-verify` and `--admin` — blocked.
- Edits to the rules and gates themselves — blocked.
- PRs with unreviewed code changes — blocked.
- Merging red, or merging a governance PR — blocked.
- Leftover work at end of turn — auto-committed and pushed.

## Quick reference

- Full rules and rationale: `REPO_RULES.md`
- Project brief: `PRD.md` · Feature plan: `SPEC.md` · Running log: `WORKLOG.md`
- Governance generation this repo uses: `.governance-version`
- <Design doc / debug playbook: `<path>`>
