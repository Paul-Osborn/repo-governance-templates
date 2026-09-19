# Work log — repo-governance-templates

> Durable public project history. Newest first; link to issues/PRs instead of duplicating them.

## 2026-09-18 — Repo Governance V3 implementation

- **Branch:** `codex/v3-01-agent-neutral-governance`
- **Changed:** Implemented issue #6 as a cross-platform, agent-neutral four-layer governance kit:
  Linux/Windows bootstrap and migration, portable gates, protected-base exact-state review,
  pinned CI and workflow analysis, GitHub plan/apply policy, public/private separation, and
  disposable acceptance coverage. Owner-approved review remediation preserved company-specific
  infrastructure material privately, scrubbed it from reachable public Git history, and made the
  large-file range gate fail closed when Git cannot resolve the comparison.
- **Verified by:** Linux/Omarchy acceptance suite (70 checks), PowerShell 7.6.6 compatibility
  suite on Linux (16 checks), manifest consistency, ShellCheck, actionlint, offline zizmor,
  Gitleaks, JSON/YAML/shell syntax, and rewritten-history private-data scans. Native Windows
  execution remains pending under issue #9.
- **Next:** live-test the remote ruleset on a disposable public repository, then obtain a new
  independent review bound to the stabilized exact HEAD.
- **Open decisions:** none; issues #8, #9, and #10 own the accepted follow-up work.

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
