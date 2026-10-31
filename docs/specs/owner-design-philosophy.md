# Owner design philosophy proposal

Scope: [issue #24](https://github.com/Paul-Osborn/repo-governance-templates/issues/24).
The owner requested the same philosophy across this V3 kit and GRL on 2026-10-31:
remove friction, obvious next steps, intuitive onboarding, smart defaults with user
control, progressive disclosure, minimal babysitting, transparent progress, and
technology adapting to users.

Outcome: concise canonical agent guidance, a clear README starting path, and actionable
prompts in generated briefs/specifications and optional issue/PR templates. The agent
reuses decisions and handles routine authorized work; the user retains control.

Files: `AGENTS.md` and `AGENTS.template.md` carry matching principles; `README.md` routes
new/existing/continuing users; `PRD.template.md`, `SPEC.template.md` and optional issue/PR
templates carry experience and evidence prompts. `WORKLOG.md` records the result.
The template files changed here are bootstrap seeds, not manifest-owned replaceable
controls; existing filled project policy/briefs remain preserved by the updater.

Out of scope: executables, infrastructure, paid services, new dependencies, remote
settings, profile/review changes, bulk updates to consuming projects and merges.
Preserve the existing solo-owner profile, current review rules, all hooks/checks,
protected-branch workflow and human-only ratification of governance proposals.

Validation: existing shell and native-Windows acceptance suites, governance/manifest
validation, whitespace and secret checks, generated-template inspection, unchanged
control-file diff and distinct exact-head AI review. Record actual outcomes and CI
state in the PR; unavailable checks remain merge blockers under normal rules.
