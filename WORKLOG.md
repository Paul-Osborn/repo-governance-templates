# Work log — repo-governance-templates

> Durable public project history. Newest first; link to issues/PRs instead of duplicating them.

## 2026-09-18 — Repo Governance V3 implementation

- **Branch:** `codex/v3-01-agent-neutral-governance`
- **Changed:** Implemented issue #6 as a cross-platform, agent-neutral four-layer governance kit:
  Linux/Windows bootstrap and migration, portable gates, protected-base exact-state review,
  pinned CI and workflow analysis, GitHub plan/apply policy, public/private separation, and
  disposable acceptance coverage.
- **Verified by:** Linux/Omarchy acceptance suite (68 checks), PowerShell 7.6.6 compatibility
  suite on Linux (15 checks), manifest consistency, actionlint, offline zizmor,
  JSON/YAML/shell syntax, and a real GitHub policy dry-run. Native Windows execution remains
  pending and is called out in the PR evidence.
- **Next:** open the human-ratified PR for issue #6; Claude performs the independent PR review.
- **Open decisions:** none; the security model documents the reviewer-status trust limitation.

## 2026-09-05 — Deterministic V1 fixture

- **Branch:** `fix/governance-v1-acceptance-fixture` → PR #5
- **Changed:** Pinned the acceptance fixture to the final V1 commit so later `main` history cannot
  silently change the migration input.
- **Verified by:** V2 PowerShell acceptance suite (144 checks, 0 failures).

## 2026-09-05 — Governance V2

- **Branch:** `feat/governance-v2` → PR #1
- **Changed:** Added autonomy boundaries, cohesive deliverables, lean engineering, substantive-code
  review digests, working default-branch/large-file gates, lockfile warnings, safe update tooling,
  governance versioning, and meaningful WORKLOG guidance.
- **Verified by:** V2 PowerShell acceptance suite (144 checks, 0 failures) and independent review.
