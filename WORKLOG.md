# Work log — repo-governance-templates

> Dated running log of what changed. Newest at the top. Keep entries short; link to the PR
> instead of re-explaining it.

## 2026-09-05 — Governance V2

- **Branch:** `feat/governance-v2` → PR #1 (Forgejo, awaiting Paul's ratification)
- **Changed:** V2 of the kit. Autonomy after objective approval, one cohesive deliverable per
  branch, lean-engineering and subagent-economy rules native to `AGENTS.md`, one end-of-work
  independent reviewer (`.claude/agents/code-reviewer.md`, Sonnet 5 / high / read-only).
  Fixed two gates that never actually fired: the branch guard missed the first commit in a
  new repo, and the large-file gate never compared a size. Review receipt now tracks a digest
  of substantive files and is checked at merge as well as at PR creation. Lockfile blanket
  block replaced with a warning. New: `update-governance.ps1`, `sync-remotes.ps1`,
  `update-global-rules.ps1`, `governance-manifest.json`, `.governance-version`. WORKLOG CI
  toll booth removed.
- **Verified by:** `tests/acceptance.ps1` — 144 checks, 0 failures, all in disposable repos.
  Two independent reviews; both returned CHANGES REQUESTED and all findings were fixed
  (`docs/` exempting executables; receipt not re-checked at merge; the authority ceiling
  going blind when merging a PR by number from another branch).
- **Next:** Paul merges PR #1 on Forgejo, then `sync-remotes.ps1` converges GitHub's `main`.
- **Open decisions:** none. One documented limitation: on Forgejo the gate cannot verify that
  `fj pr merge <n>` refers to the checked-out branch, so "merge the branch you have checked
  out" is a rule there rather than an enforced gate.
