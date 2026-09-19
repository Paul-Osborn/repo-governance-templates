# Work log — repo-governance-templates

> Durable public project history. Newest first; link to issues/PRs instead of duplicating them.

## 2026-09-19 — V3 self-bootstrap after ratification

- **Branch:** `chore/bootstrap-v3-governance`
- **Changed:** After human ratification and squash-merge of PR #7, installed the reviewed V3
  governance files into this repository itself, filled its project-specific policy/PRD, and wired
  the active project check to run both disposable acceptance suites with checksum-pinned Gitleaks
  and Lefthook binaries. The strict GitHub ruleset remains intentionally unapplied until issue #10
  provides a distinct non-author reviewer identity/App.
- **Verified by:** governance structure/manifest validation, shell/JSON syntax, generated-file
  comparison, Linux and PowerShell acceptance suites where local prerequisites are available, and
  the follow-up PR's GitHub checks.
- **Next:** human-merge the self-bootstrap PR, submit the expanded GitHub Support cleanup request,
  resolve #10, verify the active review transition, and only then apply the strict ruleset.
- **Open decisions:** issue #10 owns reviewer identity; issue #9 owns native-Windows verification.

## 2026-09-18 — Repo Governance V3 implementation

- **Branch:** `codex/v3-01-agent-neutral-governance`
- **Changed:** Implemented issue #6 as a cross-platform, agent-neutral four-layer governance kit:
  Linux/Windows bootstrap and migration, portable gates, protected-base exact-state review,
  pinned CI and workflow analysis, GitHub plan/apply policy, public/private separation, and
  disposable acceptance coverage. Owner-approved review remediation preserved company-specific
  infrastructure material privately, scrubbed it from reachable public Git history, and made the
  large-file range gate fail closed when Git cannot resolve the comparison.
- **Verified by:** Linux/Omarchy acceptance suite (75 checks), PowerShell 7.6.6 compatibility
  suite on Linux (21 checks), manifest consistency, ShellCheck, actionlint, offline zizmor,
  Gitleaks, JSON/YAML/shell syntax, and rewritten-history private-data scans. A disposable public
  [ruleset test repository](https://github.com/Paul-Osborn/governance-v3-ruleset-live-test-20260919)
  and [evidence PR](https://github.com/Paul-Osborn/governance-v3-ruleset-live-test-20260919/pull/1)
  confirmed that direct default-branch pushes are rejected, all four executable CI jobs pass,
  the exact-head status fails closed without independent approval, and GitHub blocks merging until
  someone other than the last pusher approves. The organization-enforced Actions setting prevents
  `github-actions[bot]` from opening or approving pull requests, so a positive two-identity approval
  transition remains tracked by issue #10. Native Windows execution remains pending under issue #9.
- **Next:** self-bootstrap active V3 workflows, request GitHub Support cleanup of the rewritten
  repository's cached pull-request views and internal references, then resolve issue #10 before
  applying the strict ruleset.
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
