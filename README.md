# Reusable Repo Governance Templates

My personal drop-in kit that gives any new project clean governance from day one. The rules
live in an **`AGENTS.md`** that any coding agent reads; the hooks and wiring are set up for
**Claude Code on Windows**. It provides: one always-on rule set, a branch-first /
Conventional-Commits / PR workflow, spec-before-code and prove-it-works habits, **fully
automatic git** (the agent branches, commits, pushes, and opens the PR on its own — no
prompting), and **automatic guardrails** that physically block the common mistakes.

Guiding principle: **written rules are only advice — an agent forgets them. The rules that
actually hold are the ones a machine enforces.** So this kit pairs short rules with hooks and
checks that do the right thing for you.

## What version 2 changed (start here)

Version 2 keeps every safety gate that was already stopping real mistakes, and removes the
busywork that had grown up around them. In plain terms:

**The agent interrupts you less.** Once you have approved *what* it is building, it gets on
with it. It still stops for the things that genuinely need you: a change to what the product
does, money, anything touching passwords or privacy, anything destructive, changes to the
shared server, a big architectural decision, or a change to its own rules.

**It reports less and does more.** No restating the plan, no narrating every step, no stopping
to tell you that a routine thing worked.

**Fewer, bigger, more sensible chunks of work.** The old rule — "a fix and a refactor are two
separate branches" — produced a stream of tiny changes, each needing its own review and its
own sign-off. Now one branch carries one complete, finished thing.

**Reviews happen once, at the end.** A separate reviewer checks the finished work, instead of
being run over and over while the work is still changing. Genuinely trivial changes — a typo,
a corrected sentence in a document — need no review at all. And once a review has happened,
adding a note to the log does not cancel it; changing actual code does.

**It stops the agent over-building.** New rules push it toward the smallest thing that really
works, and away from adding structure and extra software the project does not need.

**It only uses helper agents when they earn their keep.** One reviewer at the end, not a crowd.

### The safety gates — all still here

Nothing below was relaxed. Two of them were quietly broken, and now work.

| What it stops | |
|---|---|
| Committing straight to `main` | **Was broken:** it missed the very first commit in a brand-new project |
| Committing a password, key or token | |
| Committing a huge file | **Was broken:** the old check listed files but never actually rejected one |
| Skipping the checks with `--no-verify` | |
| Merging while checks are failing, or forcing a merge through with `--admin` | |
| The agent editing the rules that govern it | |
| Opening a merge request for code nobody reviewed | |
| **The agent approving its own rule changes** | Still yours, and only yours |
| Losing unfinished work | It is committed and pushed for you at the end of every turn |

One thing was genuinely relaxed, on purpose. The agent used to be blocked from touching
dependency lock files at all — which also blocked it from doing perfectly legitimate
dependency work, leaving it no way forward except going around the guardrail. Now it may not
hand-edit them, but the package manager may regenerate them normally, and you get a note if
one changes on its own.

### Starting a new project

Unchanged. From inside the new empty folder:

```powershell
& "$env:REPO_GOVERNANCE_HOME\new-governed-repo.ps1" -Name "My New App"
```

### Updating a project you already have

This is new. You update this kit, then push the improved safety gates into a project you built
earlier. **Always look first:**

```powershell
& "$env:REPO_GOVERNANCE_HOME\update-governance.ps1" -Target "C:\path\to\your\project" -DryRun
```

That changes nothing at all. It prints a list: what it would add, what it would upgrade, and
what it would leave alone. When you are happy with the list, run the same thing without
`-DryRun`:

```powershell
& "$env:REPO_GOVERNANCE_HOME\update-governance.ps1" -Target "C:\path\to\your\project"
```

It keeps a copy of everything it replaces in a `.governance-backup` folder inside the project,
so anything can be put back.

**What it will never overwrite:**

- `PRD.md` — your project brief
- `WORKLOG.md` — your project's history
- the parts of `AGENTS.md` and `REPO_RULES.md` filled in for that specific project
- your secret-scanner settings and your agent permissions
- any of your actual program

It also leaves alone any safety file you deliberately customised. It cannot tell *why* you
changed it, so it refuses to guess: it keeps yours, tells you, and lets you decide.

Running it a second time does nothing. That is deliberate — it is safe to run whenever you are
unsure.

To find out which generation of the rules a project is on, open the file called
`.governance-version` inside it. It contains a version number and nothing else.

### Refreshing the rules your agents load everywhere

The instructions that make *any* agent govern a *new* folder automatically live inside each
agent's own settings file. To refresh them without disturbing anything else you keep there:

```powershell
& "$env:REPO_GOVERNANCE_HOME\update-global-rules.ps1" -DryRun
```

then the same command without `-DryRun`. It only replaces the block between two markers —
everything you wrote yourself stays exactly where it is, and it backs the file up first.
Cursor keeps its copy inside the app rather than in a file, so it tells you to paste that one
in by hand.

### Your two copies: the home server and GitHub

Your projects live in two places. **Your own server at home is the real one.** GitHub is a
copy, so that you and outside tools can look at the work.

The agent now pushes finished work to both, so you never have to push twice. To check they
agree:

```powershell
& "$env:REPO_GOVERNANCE_HOME\sync-remotes.ps1" -Repo "C:\path\to\your\project" -DryRun
```

It prints where each copy stands. Without `-DryRun`, it brings a copy that has simply fallen
behind back up to date.

If the two copies have genuinely gone in different directions — each holding work the other
does not — **it stops and tells you** instead of picking one. Making them match would mean
throwing somebody's work away, so that decision stays yours. It never forces anything, and it
never invents a commit just to make things line up.

### Rule changes are still yours to approve

The agent can propose a change to its own rules, argue for it, and open a request. It cannot
approve one. That is the point: an agent that could approve changes to its own rules could
give itself permission to do anything. When it hands you a link and stops, that is the system
working, not the agent giving up.

---


## What's in here

### Core (use in every project)

| File | Goes where (in the new repo) | Purpose |
|------|------------------------------|---------|
| `AGENTS.template.md` | `AGENTS.md` (repo root) | The always-on rules — **the single source of truth all agents follow** (including the automatic-git workflow). |
| `CLAUDE.template.md` | `CLAUDE.md` (repo root) | Claude Code's entry point. Imports `AGENTS.md`; adds the Claude-specific wiring. |
| `GEMINI.template.md` | `GEMINI.md` (repo root) | Antigravity's entry point. Points at `AGENTS.md`. |
| `cursor-rules.template.mdc` | `.cursor/rules/agents.mdc` | Cursor's always-apply pointer to `AGENTS.md`. |
| `REPO_RULES.template.md` | `REPO_RULES.md` (repo root) | The full rationale: structure, secrets, branching, commits, PRs, guardrails, recovery. |
| `PRD.template.md` | `PRD.md` (repo root) | Project brief — what we're building and why. Filled once at the start (the agent interviews you). |
| `SPEC.template.md` | `SPEC.md` (per feature) | A short plan to agree on **before** coding — outcome, scope, constraints, how it'll be verified. |
| `WORKLOG.template.md` | `WORKLOG.md` (repo root) | Dated running log — the project's memory between sessions. |
| `gitignore.template` | `.gitignore` (repo root) | Sensible defaults: secrets, deps, build output, local/editor files. Commit it **first**. |

### Automatic git + guardrails (enforcement)

| File | Goes where | Purpose |
|------|-----------|---------|
| `claude-settings.snippet.json` | merge into `.claude/settings.json` | Pre-allows the git/PR commands (so Claude is never prompted) and wires up all the hooks below. |
| `git-guard.template.ps1` | `.claude/hooks/git-guard.ps1` | Hook: enforces branch guard, secret scan protection, review receipts, green CI merge gate, and authority ceiling. |
| `auto-commit.template.ps1` | `.claude/hooks/auto-commit.ps1` | Stop hook: auto-commits and pushes any leftover work on the branch when a turn ends, so nothing is lost. |
| `protect-paths.template.ps1` | `.claude/hooks/protect-paths.ps1` | Hook: blocks edits to protected files (lockfiles, CI, the hooks themselves). |
| `code-reviewer.template.md` | `.claude/agents/code-reviewer.md` | The independent final reviewer (Sonnet 5, high effort, read-only). The one subagent worth spawning. |
| `lefthook.template.yml` | `lefthook.yml` (repo root) | Runs checks before every commit — branch guard + secret scanner. |
| `no-commit-on-main.template.sh` | `scripts/hooks/no-commit-on-main.sh` | The branch guard, as an LF-only POSIX sh script (lefthook runs `run:` via Git's bundled `sh`, not PowerShell). |
| `check-large-files.template.sh` | `scripts/hooks/check-large-files.sh` | The large-file gate. Rejects a newly added file over the limit (default 2048 KB). |
| `check-lockfiles.template.sh` | `scripts/hooks/check-lockfiles.sh` | Warns (does not block) when a dependency lockfile moved but its manifest didn't. |
| `gitattributes.template` | `.gitattributes` (repo root) | Keeps `*.sh` LF-only so the hook script runs on Windows (defeats `core.autocrlf`). |
| `gitleaks.template.toml` | `.gitleaks.toml` (repo root) | Config for the secret scanner (blocks commits containing keys/tokens/passwords). |

**How automatic git works:** Claude branches, commits (Conventional Commits), pushes, and
opens a PR with `gh pr create` after getting a reviewer agent's receipt. Once CI turns green,
it self-merges with `gh pr merge --squash --delete-branch`. Direct commits to `main` are blocked,
and PRs editing governance rules require human ratification.

### Tools (run from this kit, not copied into projects)

| File | What it does |
|------|--------------|
| `new-governed-repo.ps1` | Sets a **new** project up with all of the above. |
| `update-governance.ps1` | Carries newer safety gates into a project built from an older version of this kit. `-DryRun` first. |
| `sync-remotes.ps1` | Checks the copies of a project agree, and fast-forwards one that has fallen behind. Refuses to resolve a real divergence. |
| `update-global-rules.ps1` | Refreshes the governance block inside each agent's own global settings file, leaving your other notes alone. |
| `governance-manifest.json` | The list of files this kit owns, with content hashes. What makes a safe update possible. |
| `tests/acceptance.ps1` | Proves the gates actually fire. Runs entirely in disposable repos. |

### Optional (add when a project needs it)

See [`optional/README.md`](optional/README.md) — license guidance, `SECURITY.md`,
`CONTRIBUTING.md`, `CODEOWNERS`, `.editorconfig`, issue/PR templates, and a GitHub CI workflow.

## Set up a new project (the easy way)

One command copies every template into the new folder under its real name and location,
inits git, and turns on the commit checks — no manual renaming:

```powershell
# set REPO_GOVERNANCE_HOME once if not set (User scope):
[Environment]::SetEnvironmentVariable('REPO_GOVERNANCE_HOME', '<path to repo-governance-templates>', 'User')

# from inside a new empty folder:
& "$env:REPO_GOVERNANCE_HOME\new-governed-repo.ps1" -Name "My New App"

# or point it at a folder (created if missing):
& "$env:REPO_GOVERNANCE_HOME\new-governed-repo.ps1" -Target C:\pauls_apps\my-new-app -Name "My New App"
```

Then open the folder in any agent (Claude Code, Codex, Cursor, Antigravity) and say:

> "Read AGENTS.md, then fill in the placeholders for &lt;what you're building&gt; and make the
> first commit."

The agent reads the rules, branches first, fills the remaining `<PLACEHOLDER>`s, and commits.

### Fully automatic (zero steps — recommended)

Install the global bootstrap once (see [`global/README.md`](global/README.md)) and you skip the
command entirely: open an empty folder in any agent, state your task, and the agent scaffolds
governance, interviews you to write `PRD.md`, fills the placeholders, and makes the first
commit — all before touching code. **Order:** governance first, then the PRD as the first
governed work (its answers fill the governance placeholders), then your task.

### Make it a one-word command (optional, one-time)

Add a `govern` shortcut to your PowerShell profile so you can run it from anywhere:

```powershell
Add-Content $PROFILE 'function Govern-Repo { & "$env:REPO_GOVERNANCE_HOME\new-governed-repo.ps1" @args }'
Add-Content $PROFILE 'Set-Alias govern Govern-Repo'
. $PROFILE   # reload (or open a new terminal)
```

After that, from any new empty folder: `govern -Name "My New App"`.

Flags: `-WithOptional` also copies the `optional/` templates · `-Force` overwrites existing
files · `-NoGit` / `-NoLefthook` skip those steps.

### Manual setup (what the script does, if you'd rather do it by hand)

1. **Ignore first.** Copy `gitignore.template` → `.gitignore` and commit it before any code.
2. **Rules.** Copy `AGENTS.template.md` → `AGENTS.md` (the real rules), then the per-agent
   pointers: `CLAUDE.template.md` → `CLAUDE.md`, `GEMINI.template.md` → `GEMINI.md`, and
   `cursor-rules.template.mdc` → `.cursor/rules/agents.mdc`. (Codex reads `AGENTS.md` natively.)
   Also copy `REPO_RULES.template.md` → `REPO_RULES.md` and `WORKLOG.template.md` → `WORKLOG.md`.
3. **Hooks + permissions.** Copy `git-guard.template.ps1`, `auto-commit.template.ps1`, and
   `protect-paths.template.ps1` → `.claude/hooks/`, then copy `claude-settings.snippet.json` →
   `.claude/settings.json` (or merge it into an existing one).
4. **Commit checks.** Install both tools first — `scoop install lefthook gitleaks` (the pipeline
   no-ops or fails if either is missing). Copy `lefthook.template.yml` → `lefthook.yml`,
   `gitleaks.template.toml` → `.gitleaks.toml`, `no-commit-on-main.template.sh` →
   `scripts/hooks/no-commit-on-main.sh`, and `gitattributes.template` → `.gitattributes`
   (the last keeps the sh hook LF-only on Windows). Then run `lefthook install`.
5. **Optional extras.** Add anything from `optional/` that fits.

## Notes

- **One rule set, many agents.** Codex, Cursor, Claude Code, and Antigravity each look for a
  different filename, so `AGENTS.md` holds the rules and the others (`CLAUDE.md`, `GEMINI.md`,
  `.cursor/rules/agents.mdc`) just point at it. Whichever agent opens the project reads the same
  rules before touching code. Change rules in `AGENTS.md` only. The git-level guardrails
  (branch guard + secret scan in `lefthook.yml`) apply to all of them; the `.claude/` hooks are
  a convenience layer for Claude Code specifically.
- **Reviewer Agent & Bot Auth:** Before opening a PR, the agent invokes a reviewer subagent to critique the diff and writes `.claude/review/receipt.json` (`git-guard` verifies this receipt matches `HEAD`). For GitHub Actions automation, set `CLAUDE_CODE_OAUTH_TOKEN` (bills to subscription) rather than `ANTHROPIC_API_KEY` (metered API). Note: bot runs draw from subscription rate limits, and GitHub Actions minutes are consumed regardless of auth method. Run `/install-github-app` to automate GitHub App setup.
- These are *templates*, not live config — editing them here never affects an existing repo.
  Each project gets its own filled-in copy.
- Keep `AGENTS.md` lean. A bloated rules file gets ignored by the agent; if a rule can be
  enforced by a hook or check instead of prose, prefer that.
