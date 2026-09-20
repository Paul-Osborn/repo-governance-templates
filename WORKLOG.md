# Work log — repo-governance-templates

> Durable public project history. Newest first; link to issues/PRs instead of duplicating them.

## 2026-09-19 — Close the unattributed-changes review gap found live

- **Branch:** `fix/v3-unattributed-changes-approval`.
- **Changed:** Follow-up to the residual gap recorded below (2026-09-19, ruleset activation).
  Confirmed via a live `GET /repos/.../rulesets/{id}` read that GitHub's `pull_request` rule
  carries a fifth native parameter, `require_extra_approval_for_unattributed_changes` (boolean;
  requires one extra approving review on a PR containing a commit GitHub cannot attribute to a
  verified account), which GitHub defaults to `true` on every ruleset it creates regardless of the
  request payload. Added an explicit `review.requireExtraApprovalForUnattributedChanges` field to
  `governance-profile.json`, following the same naming and null-check discipline as
  `requireCodeOwnerReview`/`requireLastPushApproval`. Wired it through `github-governance.sh` and
  `.ps1` (rulesets path only — classic branch protection has no equivalent parameter, and both
  scripts now say so in their plan output rather than dropping it silently). Gave the reusable
  ruleset template (`github/rulesets/default-branch.json`) an explicit `true` default instead of
  relying on GitHub's implicit one. Set this repository's own profile to `false`: with a solo
  maintainer and commits that carry an AI co-author trailer, leaving GitHub's default `true` in
  place would reproduce the same self-approval deadlock already fixed for the other two native
  review settings. Bumped `governance-manifest.json`'s hash for `github/governance-profile.json`
  and preserved the prior hash in `knownHashes`.
- **Verified by:** `sh tests/acceptance.sh` (100 pass, 1 pre-existing unrelated local `lefthook`
  environment failure present on `main` before this change too) and
  `pwsh -NoLogo -NoProfile -File tests/acceptance.ps1` (22/22), both run locally via an isolated
  `mise exec powershell@7.6.6` invocation that did not touch global mise config. New coverage:
  explicit `true`, explicit `false`, and missing-field-defaults-to-`true` cases for both `sh` and
  PowerShell, plus byte-identical ruleset-payload equivalence checks between the two
  implementations for all three cases.
- **Next:** after merge, sync `main` and re-run `./github-governance.sh --apply` against this
  repository so the live ruleset converges on the new explicit `false`, then independently verify
  via a fresh API read (not command output) that the live value actually changed.

## 2026-09-19 — Strict GitHub ruleset activated on this repository

- **Branch:** `docs/v3-ruleset-activated`.
- **Changed:** Ran `./github-governance.sh --repo Paul-Osborn/repo-governance-templates --profile
  .github/governance-profile.json --apply` against `main` after PR #17 merged and a fresh preflight
  found no material blocker. GitHub-side branch protection for this repository moved from
  plan-only to actually enforced for the first time. This WORKLOG update is itself the first change
  to go through the newly active ruleset's required pull-request flow — direct pushes to `main` are
  no longer possible for anyone, including the owner, without first editing the ruleset.
- **Verified independently** (fresh API reads, not command output): ruleset `repo-governance-v3`
  (id 23713259) is `active`, targets `~DEFAULT_BRANCH` (resolves to `main`), and its rules exactly
  match intent — `deletion`, `non_fast_forward`, `required_linear_history` present;
  `pull_request` rule has `required_approving_review_count: 0`, `require_code_owner_review: false`,
  `require_last_push_approval: false` (no self-approval trap for this solo-maintainer repo);
  `required_status_checks` lists all six intended contexts with correct `integration_id`s,
  including `governance/exact-head-review` bound to the dedicated reviewer App (5005110), not the
  shared Actions identity. `GET /repos/.../rules/branches/main` (GitHub's own live rule-resolution
  endpoint) confirms the same rule set is actually bound to `main`, not merely stored. Actions
  permissions (`default_workflow_permissions: read`, `can_approve_pull_request_reviews: false`)
  were already at the desired state — the apply's Actions-permissions call was a no-op, no
  unrelated settings changed. Deleted the fully-merged `fix/v3-ruleset-review-wiring` branch.
- **Known residual gap found live, not previously visible:** GitHub defaulted the new ruleset's
  `pull_request` rule to `require_extra_approval_for_unattributed_changes: true` — a field this
  kit's template never set and that only appears once GitHub actually creates the object. If a
  future commit's author/committer identity isn't a verified, linked GitHub account, this could
  reproduce the same solo-maintainer self-approval trap that `require_code_owner_review` and
  `require_last_push_approval` already had to be fixed for. Not yet remediated; tracked as follow-up
  work rather than fixed silently outside the reviewed change that activated the ruleset.
- **Next:** decide whether to wire `require_extra_approval_for_unattributed_changes` to the profile
  the same way the other four review settings were (a small, same-shaped follow-up to PR #17), or
  set it directly via the GitHub UI/API now that the ruleset exists.
- **Open decisions:** none blocking; see the residual gap above.

## 2026-09-19 — Wire native GitHub review settings to governance-profile.json

- **Branch:** `fix/v3-ruleset-review-wiring`.
- **Changed:** A strict-ruleset activation preflight (read-only; `--apply` was never run) found that
  `review.requireIndependentReview` only ever governed the custom `governance/exact-head-review`
  status check — GitHub's own native `require_code_owner_review` / `require_last_push_approval`
  rule was hardcoded `true` in the static ruleset template regardless of the profile. Since this
  repository's `CODEOWNERS` names only its solo maintainer, applying the ruleset as shipped would
  have made every governance-affecting PR unmergeable (no second identity exists to approve, and
  GitHub doesn't allow self-approval). `github-governance.sh`/`.ps1` now derive
  `required_approving_review_count`, `dismiss_stale_reviews_on_push`, `require_code_owner_review`,
  and `require_last_push_approval` from the profile's `review.requiredApprovals`,
  `dismissStaleApprovals`, `requireCodeOwnerReview`, and `requireLastPushApproval` fields — for both
  the ruleset path and the classic-branch-protection fallback — using an explicit null-check so an
  explicit `false`/`0` is preserved rather than silently replaced by jq's `//` or PowerShell's naive
  `-or`. This repository's own profile now sets `requireCodeOwnerReview`/`requireLastPushApproval`
  to `false`, consistent with its existing `requireIndependentReview: false`; the reusable template
  keeps `true`/`true`/`0`/`true` as shipped defaults for downstream teams. Also added
  `Governance / windows-verification` to this repository's own required status checks (it already
  runs and passes on every PR) without making it a downstream-consumer requirement.
- **Verified by:** `sh tests/acceptance.sh` (new coverage: explicit `false`/`0` survives for both
  `sh` and PowerShell, missing fields still fail closed to strict defaults, and the two
  implementations produce byte-identical `pull_request` rule parameters for the same input);
  `pwsh tests/acceptance.ps1` (22/22, via an isolated `mise exec powershell@7.6.6` invocation that
  does not touch global `mise` config, since this shell has no pinned global `pwsh`);
  `scripts/ci/validate-governance.sh`; manual fake-`gh` runs of both the ruleset and classic
  fallback paths in both languages.
- **Next:** re-run the strict-ruleset activation preflight against `main` once this merges; if the
  code-owner/last-push blocker is confirmed gone, the owner activates the ruleset
  (`github-governance.sh --apply`) — owner approval for that eventual step was already given.
- **Open decisions:** none blocking; a pre-existing, unrelated local environment gap remains
  (`lefthook`/`pwsh`/`zizmor` have no pinned global `mise` version in this interactive shell — CI
  is unaffected).

## 2026-09-19 — Dedicated reviewer App + optional independent review (issue #10)

- **Branches:** `feat/v3-reviewer-app-identity` → PR #14; `feat/v3-optional-independent-review` → PR #15.
- **Changed:** `review-gate.yml` mints an installation token via `actions/create-github-app-token`
  when `GOVERNANCE_REVIEWER_APP_ID` (repo variable) and `GOVERNANCE_REVIEWER_APP_PRIVATE_KEY`
  (repo secret) are configured, scoped to `contents:read`, `pull-requests:read`, `statuses:write`,
  and publishes `governance/exact-head-review` under that identity instead of the shared
  `github-actions[bot]`; falls back to `github.token` when unconfigured. `github-governance.sh`/
  `.ps1` resolve `integration_id` per required check via `review.externalReviewerAppId`. Separately,
  added `review.requireIndependentReview` to `governance-profile.json` (default `true` in the
  reusable template); the workflow reads it from the PR's **base SHA** copy of the profile (never
  the PR's own copy, matching the existing `trustRootPaths` pattern) so a PR cannot flip it on
  itself. When `false` the check still runs and posts on every PR but always succeeds, keeping the
  choice auditable. This repository's own profile sets it `false`: as a solo maintainer directing
  an AI agent, no second human reviewer exists, and `AGENTS.md` rule 7 already reserves final
  ratification of governance/control-file changes to the human owner. Fixed a latent bug along the
  way: `jq`'s `//` treats `false` the same as `null`, so a naive `x // true` silently ignored an
  explicit `false`.
- **Owner-only setup performed:** registered GitHub App `repo-governance-reviewer-v3`, generated
  and stored its private key, installed it, and set the resulting repo variable/secret — all human
  identity actions no agent performed. Discovered and fixed a real setup bug: the App was first
  registered under the personal `pauldavid1974` account with "Only on this account," which cannot
  be installed on the `Paul-Osborn` org that actually owns this repo (confirmed via a `Not Found`
  error from `create-github-app-token`'s installation lookup); transferred App ownership to
  `Paul-Osborn` and reinstalled scoped to just this repository.
- **Verified by:** `sh tests/acceptance.sh` (81/81 relevant; one pre-existing, unrelated local
  environment failure — `lefthook` not resolved by `mise` in this shell), `validate-governance.sh`,
  `sh -n` on all shell entry points, and live confirmation on PR #15's head commit: the
  `governance/exact-head-review` status posted by `repo-governance-reviewer-v3[bot]`, not
  `github-actions[bot]` (run
  [35476784383](https://github.com/Paul-Osborn/repo-governance-templates/actions/runs/35476784383)).
- **Next:** the strict GitHub ruleset (`github-governance.sh --apply`) is still unapplied; branch
  protection today is enforced only by convention (owner ratification of governance-file changes),
  not by GitHub itself. Applying it is the next real milestone.
- **Open decisions:** none; issue #10 closed with live evidence.

## 2026-09-19 — Native Windows verification (issue #9)

- **Branch:** `test/v3-native-windows-verification`
- **Changed:** Added `Governance / windows-verification` to `.github/workflows/governance.yml`: a
  permanent job on GitHub-hosted `windows-latest`, installing checksum-pinned Gitleaks 8.30.1 and
  Lefthook 2.1.14 for Windows (verified against the same upstream release manifests already pinned
  for the Linux jobs) and running `tests/acceptance.ps1` for real, native execution. Deliberately
  not added to the shipped `github/workflows/governance.template.yml` — that template goes to
  every downstream project bootstrapped from this kit, and those projects don't receive
  `tests/acceptance.ps1` (it tests this kit's own bootstrap/migration behavior, not a downstream
  project's code); mandating Windows CI cost on every consumer by default is a separate, larger
  decision than verifying this kit's own native Windows behavior. Updated `docs/platform-support.md`
  from "not a substitute for a native Windows run" to cite the first green run.
- **Verified by:** first native Windows run
  [35469937248](https://github.com/Paul-Osborn/repo-governance-templates/actions/runs/35469937248) —
  Windows Server 2025 (10.0.26100), runner image `windows-2025-vs2026` (20260907.229.1), Git for
  Windows 2.55.0, PowerShell 7.6.5, bundled `bash`/`sh` 5.3.15(2): **22/22 checks passed**,
  covering bootstrap, V2→V3 migration, hooks via Git for Windows' bundled shell, the secret and
  large-file gates, and the private-marker scans. All other governance jobs (invariants, secrets,
  actions-security, project) remained green on the same PR.
- **Next:** independent review, then the human owner merges the PR; close issue #9 only after
  merge and a successful run on `main`, per the issue's own acceptance criteria.
- **Open decisions:** none for this branch; issue #10 and strict ruleset activation remain
  separately owned and are explicitly out of scope here.

## 2026-09-19 — Trust-root path consolidation (issue #8)

- **Branch:** `fix/v3-trust-root-consistency`
- **Changed:** Made `governance-policy.template.json` / installed `.governance/policy.json`
  `trustRootPaths` the single source of truth. `classify-change.sh` now reads it from the
  **base** commit rather than the working tree or head, closing a real bypass this review found:
  a branch could otherwise shrink its own `trustRootPaths` and use that shrunk definition to
  classify its own edit to a now-untracked governance file (e.g. `AGENTS.md`) as prose-only.
  `review-gate.yml` already fetched policy at the base SHA via the API; it is now `contents:
  read` and unchanged in behavior. The legacy PowerShell git-guard fallback list now prefers the
  installed policy and falls back to a literal list. Found and fixed real drift along the way:
  `.github/governance-profile.json` was in CODEOWNERS and the git-guard fallback but missing
  from the canonical `trustRootPaths`. `validate-governance.sh` now deterministically compares
  CODEOWNERS and the git-guard fallback against the canonical policy and fails closed on drift in
  either direction. An independent review of the first pass found that `git-guard.template.ps1`'s
  new "preferred" policy read still read `.governance/policy.json` off the working tree/HEAD, so
  a branch could still shrink its own policy locally and hide its own edit from the PowerShell
  adapter's authority ceiling and review-receipt gate (confirmed by re-running the attack against
  the pre-fix file: `AGENTS.md` never appeared in either check's output). Fixed to read the
  policy from the branch's base commit via `git show`, matching `classify-change.sh`, with a new
  executable regression test in `tests/acceptance.ps1`.
- **Verified by:** Linux acceptance suite (82 checks, including new trust-root fixtures proving
  CODEOWNERS drift is rejected in both directions, a policy-only trust-root addition reaches the
  classifier with no code edit, and a same-branch policy-shrink attack is defeated), PowerShell
  7.6.6 compatibility suite on Linux (22 checks, including the new git-guard base-read regression
  test), governance structure/manifest validation in both kit and installed mode, shell/PowerShell
  syntax, `git diff --check`, offline zizmor, and actionlint. Two independent code-reviewer agent
  passes: the first found the git-guard gap above; the second, at exact HEAD
  `d4ee3227dfefe7a854c9268845209f1883dc598b`, independently reran both the new regression test and
  the attack by hand against pre-fix and post-fix content, reproduced the same pass/fail split,
  and returned PASS with no findings. Native Windows execution remains pending under issue #9.
- **Next:** the human owner reviews and merges the PR, then closes issue #8.
- **Open decisions:** none for this branch; issues #9 and #10 remain separately owned.

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
