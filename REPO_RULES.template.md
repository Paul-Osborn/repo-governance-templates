# Repository Rules — <PROJECT_NAME>

> **How to use this template:** Copy it to your new repo's root as `REPO_RULES.md`.
> Replace every `<PLACEHOLDER>`. Delete sections that don't apply. Anything not in
> angle brackets is a sane default you can keep as-is.

These rules keep the repo clean, reproducible, and safe to share. They apply to every
commit, branch, and pull request. When in doubt, favor the simplest change that keeps
the project working.

---

## 1. Scope & structure

- Describe the intended shape of the project in one or two lines, so drift is obvious:
  <e.g. "a single CLI entry point under `src/`", "a Next.js app", "a Python package">.
- Keep the layout predictable. Sketch the top-level structure:

  ```
  <repo>/
  ├─ <main source location>
  ├─ <dependency manifest>   # e.g. requirements.txt / package.json / go.mod
  ├─ README.md               # what it is + how to run it (for humans)
  ├─ AGENTS.md               # always-on rules — the single source of truth all agents follow
  ├─ CLAUDE.md               # Claude Code entry point (imports AGENTS.md)
  ├─ GEMINI.md               # Antigravity entry point (points at AGENTS.md)
  ├─ .cursor/rules/          # Cursor entry point (points at AGENTS.md)
  ├─ REPO_RULES.md           # this file — the full rationale
  ├─ PRD.md                  # project brief — what we're building and why (project-level)
  ├─ WORKLOG.md              # dated running log of what changed (project memory)
  ├─ SPEC.md                 # current feature's plan (optional, per-feature)
  ├─ lefthook.yml            # pre-commit gates — apply to every agent and to manual commits
  ├─ scripts/hooks/          # the gates themselves (LF-only POSIX sh)
  ├─ .gitleaks.toml          # secret-scanner config
  ├─ .governance-version     # which generation of the governance kit this repo has
  ├─ .claude/                # hooks, settings, and the code-reviewer specialist
  └─ .gitignore
  ```

- Don't restructure the project without updating this section first.

### One rule set, many agents

`AGENTS.md` is the single source of truth. Each agent reads a different filename, so the others
are thin pointers to it — whichever agent picks up the project reads the same rules before
touching code:

| Agent | Reads | In this repo |
|-------|-------|--------------|
| Codex | `AGENTS.md` (native) | reads it directly |
| Cursor | `AGENTS.md` (native) + `.cursor/rules/` | direct, plus an always-apply `.cursor/rules/agents.mdc` pointer |
| Claude Code | `CLAUDE.md` | `CLAUDE.md` imports `AGENTS.md` |
| Antigravity | `GEMINI.md` (+ `AGENTS.md` on v1.20.3+) | `GEMINI.md` points at `AGENTS.md` |

Edit `AGENTS.md` for any rule change; leave the pointers alone unless an agent needs a
tool-specific override.

---

## 2. What MUST NEVER be committed

Generated, machine-local, private, or large files belong in `.gitignore`, never in history:

- **Secrets** — no `.env`, API keys, tokens, or credentials in code, config, or commit
  messages. Commit a `*.example` template instead when a reference is useful.
- **Dependencies / build output** — vendored deps, `node_modules/`, `.venv/`, `build/`, `dist/`.
- **Large binaries / data** — model files, datasets, media dumps, anything re-downloadable.
- **Local state** — log files, caches, user-specific config, scratch files.
- **Editor / OS cruft** — `.vscode/`, `.idea/`, `.DS_Store`, `Thumbs.db`, `desktop.ini`.

If one slips in by accident, see §7.

### Starter `.gitignore`

Use the ready-made `gitignore.template` from this template set (copy it to `.gitignore`),
which covers secrets, dependencies, build output, local state, and editor/OS cruft. Adjust
per project. Commit it **first**, before any code, so ignored files never enter history.

---

## 3. Version control

### Setup
- Initialize once with `git init` and commit `.gitignore` **first**, before any code,
  so ignored files never enter history.
- `main` is the default branch and is always in a working state.

### Branching
- **Never commit directly to `main`.** Branch for every change.
- Branch naming: `<type>/<short-desc>` — `feat/`, `fix/`, `docs/`, `chore/`, `refactor/`.
  - `feat/add-export`, `fix/null-on-empty-input`, `docs/readme-setup`
- Delete branches after they merge.
- *(Optional but recommended)* enforce it with a hook that blocks `git commit`/`git push`
  on `main`. See `git-guard.template.ps1` in this template set.

### Commits
- One logical change per commit. Small and reviewable.
- Imperative, present-tense subject, ≤ 72 chars, no trailing period.
  - ✅ `fix: restore focus after dialog closes`   ❌ `fixed some stuff`
- Use [Conventional Commits](https://www.conventionalcommits.org) prefixes:
  `feat`, `fix`, `docs`, `chore`, `refactor`, `test`, `perf`.
- Commit body explains **why**, not just what.
- Never commit broken code to `main`. Never `git push --force` to `main`.
- Don't rewrite published history others may have pulled.

### Pull requests
- All changes reach `main` through a PR, even solo work — it's the review checkpoint.
- Get reviewed, then merge it yourself. Once CI is green,
  `gh pr merge --squash --delete-branch`. Never merge red. Never use `--admin`.
- **Authority ceiling:** a PR touching governance/rule files is the human's to merge, not
  yours. See §3a.
- PR description states: what changed, why, and how it was tested.
- A PR must build / run / pass tests (green CI) before merge.

### One cohesive deliverable per branch

An earlier version of these rules said "a bug fix and a refactor are two PRs". Taken
literally that produced a stream of micro-PRs — a fix, then the test for the fix, then the
rename the fix needed — each with its own review, its own CI run and its own log entry, and
none of them reviewable on their own because the context was in the branch next door.

The rule is now: **a branch carries one complete, shippable thing.** That includes the
implementation, its tests, the supporting fixes it genuinely needs, small supporting
refactors, and the documentation that goes with it.

Split when the work becomes independently useful on its own, or when what you are now doing
has a materially different objective from what you set out to do. Defer unrelated cleanup —
note it, don't smuggle it in. The failure mode on the other side is real too: a branch
containing three unrelated projects cannot be reviewed or reverted.

### Plan before you code — once

- For anything beyond a one-line edit, write a short plan **before** implementing: which
  files change, what's explicitly out of scope, and how the result will be verified.
- For a real feature, copy `SPEC.template.md` to `SPEC.md`. The spec — not the code — is the
  thing to review and agree on first. Keep it updated as decisions change.
- This matters most with AI agents: without an explicit plan and scope, an agent fills the
  gaps with guesses and confidently builds the wrong thing.
- **The plan is for scope control, not for a second round of permission.** Once the owner has
  approved *what* is being built, the agent proceeds through the implementation decisions
  itself and reports what it did. `AGENTS.md` lists the specific things worth interrupting
  for — product behaviour, scope, money, privacy/security, credentials, destructive or
  irreversible acts, shared-server topology, major architecture, and the rules themselves.
  An agent that stops every twenty minutes to ask about a variable name trains the owner to
  rubber-stamp, and then the interruptions that matter get rubber-stamped too.

### Prove it works (verification)

- "Looks done" is not done. Before calling a task complete, produce evidence: test output,
  the exact command run and what it returned, or a screenshot — not just an assertion.
- Prefer a check the tool can run itself (test suite, build, linter) so mistakes are caught
  automatically instead of waiting for a human to notice them.
- **Match the check to the risk, not to the clock.** During implementation, run the smallest
  check that would catch what you just broke. At a meaningful boundary — the branch is
  stable, you're about to review, you're about to open the PR — run the broad checks, plus
  any deployment or acceptance checks. High-risk work gets broad verification regardless of
  how small the diff looks. Re-running the full suite after every one-line edit is not more
  rigorous; it is slower, and it trains everyone to skim the output.

### Lean engineering

The most reliable code is the code that was never written, and the most common way an AI
agent damages a small project is by adding structure it does not need: an interface with one
implementation, a config file for a value that never changes, a framework for a job the
standard library does in three lines. Each of those is something a future session must read,
understand, and preserve.

`AGENTS.md` carries the operating rule (take the highest working option: no change → existing
project capability → platform/native → standard library → existing dependency → a little new
code → a new dependency). The limit on it is equally firm: correctness, security, validation
at trust boundaries, error handling that prevents data loss, accessibility, maintainability
and anything explicitly requested are never traded away for a shorter diff.

### Subagent economy

Direct execution is the default. A subagent starts cold, re-derives context the primary
already has, and cannot see state the primary is still changing — so fanning out for ordinary
sequential work costs more and produces worse results than doing it directly.

Two cases justify one: genuinely parallel work that doesn't depend on evolving shared state,
and the one independent final review. Nothing else — not reading files, not searching the
repo, not running tests, not writing docs. Subagents never spawn subagents.

### Review timing

The workflow is: implement → self-check → targeted verification → stabilise the branch →
broader verification → **one** independent `code-reviewer` review → fix what's valid → open
the PR. Re-review only if those fixes materially changed what was reviewed.

Reviewing while the implementation is still moving wastes the review: the reviewer reads code
that will not exist in an hour, and its findings arrive as noise.

Risk tiers:

| Tier | Examples | Independent review |
|------|----------|--------------------|
| Trivial | typo, small doc fix, cosmetic repair with a deterministic check | not required |
| Normal | ordinary feature or fix | one, at the end |
| High risk | auth, permissions, credentials, privacy, payments, destructive data operations, migrations, deployment, governance | required |

The receipt gate (§3a) enforces the boundary between the first two automatically, so nobody
has to argue about which tier a change is in.

---

## 3a. Automatic git & guardrails (enforcement)

Git is hands-off. Whichever agent picks up the project runs the whole workflow itself — branch,
commit, push, review, open PR, and merge when CI is green (`gh pr merge --squash --delete-branch`
on GitHub, `fj pr merge --squash --delete-branch` on Forgejo). PRs touching governance rules
require human ratification.

Written rules are only advice; an agent (or a tired human) forgets them. The rules that
actually hold are the ones a machine enforces. This kit layers guardrails so that if one is
bypassed, another still catches the problem ("defense in depth").

**Prefer the git level.** A rule enforced in `lefthook.yml` or a script protects Claude,
Codex, Cursor, Antigravity and a human at a terminal, all at once. A rule enforced only in
`.claude/` protects Claude. So anything that can cheaply live at the git level does — and
what remains Claude-specific stays there because moving it would cost more complexity than it
buys, not because nobody noticed.

**Git-level gates (apply to EVERY agent + manual commits — via `lefthook.yml`):**

| Gate | What it refuses |
|------|-----------------|
| `scripts/hooks/no-commit-on-main.sh` | any commit made on `main`/`master` |
| `gitleaks protect --staged` | any commit containing a key, token or password (§6) |
| `scripts/hooks/check-large-files.sh` | a newly added file over the size limit (default 2048 KB; change with `git config governance.maxFileKB <n>`) |
| `scripts/hooks/check-lockfiles.sh` | nothing — it *warns* when a lockfile moved but its manifest didn't (§4) |

Install once with `lefthook install`. Both `lefthook` and `gitleaks` must be present or the
pipeline no-ops or fails.

**Claude Code gates (via `.claude/settings.json` hooks):**

- **`git-guard.ps1`** — one hook, six rules: refuses `--no-verify`, refuses commit/push on
  `main` early, refuses shell redirection aimed at a governance file, requires a review
  receipt before `gh pr create` / `fj pr create` when the branch changes code, gates
  `gh pr merge` on green CI status, and refuses any merge of a PR that edits the rules.
- **`protect-paths.ps1`** — denies Edit/Write to the governance files, the hooks, the CI
  workflows and `.claude/settings.json`. It does **not** block lockfiles (§4).
- **`auto-commit.ps1`** — Stop hook; commits and pushes leftover work so nothing is lost.
  Never touches `main`; the secret scan still gates its commits.
- **`.claude/agents/code-reviewer.md`** — the independent reviewer (Sonnet 5, high effort,
  read-only). Deliberately the one permitted subagent.

Other agents rely on the git-level gates plus the rules they read from `AGENTS.md`.

**The review receipt, and what it can and cannot do.** Before a PR opens, `git-guard`
requires `.claude/review/receipt.json` naming a verdict and a `codeDigest` — a SHA-256 of the
branch diff restricted to the files that can actually change behaviour. Two consequences,
both deliberate:

- A branch touching only prose (docs, plain `*.md`, `WORKLOG`, the receipt itself) needs no
  receipt at all. The earlier version demanded one for a README typo, which taught everyone to
  run a reviewer purely to generate a file.
- Adding a WORKLOG entry after a clean review does not invalidate it; changing a line of code
  does. The earlier version pinned the receipt to a commit SHA, so any commit at all forced a
  re-review that could not find anything new.

Honest limit: this forces a review to *happen* and to be recorded against specific code. It
cannot force the agent to act on what the review said, and an agent determined to write a
fake receipt can. It is a tripwire, not a cage. The gates that genuinely cannot be talked
around are the git-level ones.

**The authority ceiling.** An agent may propose a rule change and argue for it; it may not
ratify one. `git-guard` refuses to merge any PR touching `AGENTS.md`, `CLAUDE.md`,
`GEMINI.md`, `REPO_RULES.md`, `lefthook.yml`, `.gitleaks.toml`, `.governance-version`, or
anything under `.claude/`, `.cursor/`, `.github/workflows/` or `scripts/hooks/`. Without it,
merge power is self-amplifying: an agent could merge the PR that widens its own permissions.
The check reads the branch diff from local git, so it holds on GitHub and Forgejo alike, and
fails closed if it cannot determine what the branch changed.

**Optional:** a CI workflow re-runs tests and the secret scan on every push, catching anything
that slipped past local checks.

Set these up at project start. Do not disable or route around a guardrail to "get unblocked" —
fix the underlying cause (branch first, remove the secret, etc.).

---

## 3b. Remotes: one authoritative, the rest mirrors

A repo may live in more than one place. One remote is **authoritative** — the copy that
decides what is true. Any others are **mirrors**, which must end up reflecting completed work
so the owner and any external tool looking at them see the real state.

<Fill in for this project. A common setup: `origin` → a self-hosted Forgejo server
(authoritative), `github` → a GitHub mirror.>

Rules:

- Push completed work to **every** remote. The owner should never have to push twice.
- The default branches must converge on the same commit.
- **Never force-push to make them equal.** Equality obtained by discarding somebody's commits
  is not synchronisation.
- If the remotes have genuinely diverged — each holding commits the other doesn't — stop and
  report it in plain language. Do not pick a side silently.
- `sync-remotes.ps1` does the checking and the safe fast-forward pushes. Run it with `-DryRun`
  first to see what it would do; it refuses divergence and never creates a commit.

---

## 4. Dependencies

- Pin versions for reproducibility (`==`, lockfiles, etc.).
- Adding a dependency requires a one-line justification in the PR. Take it only after the
  lean-engineering ladder (§3a) has run out of higher options. Remove anything unused.
- State any hard constraints here: <e.g. "no cloud SDKs", "no telemetry", "local-only",
  "stdlib only", "no new outbound network calls">.

### Lockfiles

- **Never hand-edit a generated lockfile** (`package-lock.json`, `pnpm-lock.yaml`,
  `poetry.lock`, `uv.lock`, `Cargo.lock`, `go.sum`, …). Change the manifest and let the
  package manager regenerate it, in the same commit.
- A legitimate dependency change *will* move the lockfile, and that is fine. An earlier
  version of these rules blocked every lockfile edit outright, which also blocked the
  legitimate case — leaving the agent no way forward except routing around a guardrail,
  which is exactly the habit the guardrails exist to break.
- `scripts/hooks/check-lockfiles.sh` warns (does not block) when a lockfile changed but its
  manifest did not. That shape means a hand-edit, a stray `npm install`, or a dependency
  swapped in without a manifest change — worth a second look, not worth stopping the commit.
- If the warning fires and the change is intended, say so in the commit body.

---

## 5. Code hygiene

- Match the existing style and comment density. Don't reformat untouched code in a feature PR.
- No dead code, no commented-out blocks, no debug-print spam left behind.
- Preserve the project's core invariants: <list the load-bearing guarantees your project
  must never break — e.g. "single source of truth for config", "no blocking calls on the UI thread">.

---

## 6. Secrets & privacy (hard line)

- No secret ever enters the repo — not in code, config, history, or a commit message.
- Before pushing, scan the diff for keys, tokens, paths with usernames, and device serials.
- State the network policy: <e.g. "local-only; any PR adding an outbound call is rejected
  unless this rule is changed first", or "external calls allowed to <approved hosts> only">.
- If a secret is ever committed, treat it as compromised: rotate it immediately, then scrub
  history (§7). Scrubbing alone is not enough — the key is burned.

---

## 7. When something bad gets committed

- **Large file** committed by mistake: remove it, add to `.gitignore`, and if already pushed,
  purge it from history with `git filter-repo` (preferred) or BFG, then force-update the
  remote *branch* (never `main`) and have collaborators re-clone.
- **Secret** committed: rotate the secret first (assume it's leaked), then scrub history as above.

---

## 7a. WORKLOG — project memory, not a toll booth

`WORKLOG.md` is what the next session reads to find out what happened. Keep it useful by
keeping it thin:

- Write an entry when work **materially advances** or reaches a checkpoint another session
  would need to know about. Newest at the top, dated.
- Keep entries short and link to the PR, spec or commit rather than reproducing them.
- **Don't** write an entry for a trivial change, and **don't** make a commit purely to add
  one. An earlier version of this kit had a CI job that failed any PR not touching
  `WORKLOG.md`. Predictably, that produced a line of filler prose on every typo fix — noise
  in the file that is supposed to be the signal — and taught everyone to write the entry to
  satisfy the robot rather than to inform the next session. The job now checks only PRs that
  actually change code, and even then it warns rather than failing.

---

## 8. Governance version & updates

`.governance-version` records which generation of the governance kit this repo has. Read it
to answer "what rules generation is this project on?" without asking an AI to guess from the
files.

To take a newer generation of the machine gates into this repo, run the kit's
`update-governance.ps1` with `-DryRun` first. It only replaces **template-owned gate files**
that are still byte-identical to a version the kit knows it shipped. Anything customised is
left alone and reported, and it never touches `PRD.md`, `WORKLOG.md`, your filled-in
`AGENTS.md` / `REPO_RULES.md`, or any project source.

---

## 9. Releases / tags (optional)

- Tag working milestones with semantic versions: `v0.1.0`, `v0.2.0`.
- A tagged commit must satisfy <your definition of "shippable">.

---

*These rules protect three things: a repo small enough to clone fast, a history clean of
secrets and binaries, and a project that still matches its intended shape. Change the rule
before you break it.*
