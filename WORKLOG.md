# Work log — repo-governance-templates

> Dated running log of what changed. Newest at the top. Keep entries short; link to the PR
> instead of re-explaining it.

## 2026-09-05 — Deterministic V1 fixture for governance acceptance suite

- **Branch:** `fix/governance-v1-acceptance-fixture` → PR #5
- **Changed:** Fixed historical Governance V1 fixture selection in `tests/acceptance.ps1`
  (Section I). Replaced dynamic `git merge-base HEAD main` (which resolved to V2 history
  once V2 merged into `main`) with immutable historical V1 commit SHA
  `df4014f91a12ced80d26a7fb97a2c577a0144891` (the final commit of Governance V1 immediately
  preceding the V2 PR #1 merge).
- **Verified by:** Full canonical acceptance suite `tests/acceptance.ps1` (144 PASS, 0 FAIL;
  all 11 Section I failures resolved).

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
