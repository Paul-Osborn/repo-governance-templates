# Project brief / PRD — Repo Governance Templates

> **What this is:** the project-level research document — what we're building and why. Created
> once at the start of the project (the agent interviews you to fill it), and kept updated as
> things evolve. This is the *project* brief; per-**feature** plans go in `SPEC.md`, not here.
## Problem / why
AI-assisted repositories need consistent working rules, local safeguards, remote checks, and a
human authority ceiling without depending on one agent product or relying on prose as a security
boundary.

## Goal / outcome
Provide a reusable, cross-platform governance kit whose important invariants are independently
enforced and whose trust-root changes remain subject to human ratification.

## Users / context
Repository owners and coding agents bootstrapping or upgrading Git projects on Linux/Omarchy,
Windows, and GitHub.

## Scope
- **In:** canonical agent policy, portable Git hooks, GitHub workflow/ruleset templates,
  bootstrap and safe-update tooling, remote synchronization, and disposable acceptance tests.
- **Out (for now):** product-specific build systems, private infrastructure configuration,
  credential management, automatic governance ratification, and support for hosting platforms
  without an implemented adapter.

## Requirements
- Install a concise canonical policy with thin agent adapters.
- Enforce branch, secret, large-file, commit-message, and review invariants through independent
  local and remote controls.
- Preserve project customizations during upgrades and provide dry-run, backup, rollback, and
  conflict reporting.
- Support POSIX/Linux and PowerShell paths while accurately reporting platform verification.
- Keep GitHub policy mutation plan-first and require explicit human authorization to apply.
- Prevent agents from approving or merging changes to their own governance authority.

## Non-functional needs
- **Security / privacy:** no secrets or private infrastructure details in the public kit or its
  reachable live history; least-privilege CI; fail closed where a required result is unknown.
- **Performance / limits:** bootstrap and local gates stay small and fast; exhaustive acceptance
  coverage may run in CI or release verification.
- **Platform:** POSIX shell on Linux and Git for Windows, PowerShell 5.1+ compatibility, GitHub as
  the implemented remote-policy host.

## Constraints / decisions already made
- **Stack:** POSIX shell, PowerShell, Git, JSON, YAML, Lefthook, Gitleaks, and GitHub Actions/API.
- Third-party Actions are commit-pinned and downloadable CI tools are version/checksum pinned.
- Templates remain agent-neutral; product-specific integrations are adapters, not authority.
- Governance-file changes are proposals until the human owner merges them.

## Success criteria (how we'll know it works)
- Linux and PowerShell acceptance suites pass in disposable repositories.
- Generated repositories contain the declared trust root and active local/remote controls.
- Migration preserves customized files, backs up replacements, and is idempotent.
- Live GitHub evidence demonstrates required checks and exact-HEAD review behavior before broad
  rollout.

## Risks / open questions
- A distinct GitHub reviewer identity/App is still required before safely activating the strict
  ruleset on repositories where the implementation worker uses the owner's identity (issue #10).
- Native Windows execution remains a tracked verification gap (issue #9).
- GitHub-retained pull-request refs and cached objects from the history remediation require a
  Support cleanup request.

## Milestones (optional)
1. V3 templates, migration, acceptance suites, and disposable ruleset evidence — complete in
   PR #7.
2. Self-bootstrap this repository's active workflows and checks.
3. Add a distinct reviewer identity/App, then activate the strict ruleset.
