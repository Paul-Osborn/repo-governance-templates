# Wire native GitHub review settings to governance-profile.json

## Outcome

Fix a gap found during the strict-ruleset activation preflight: `review.requireIndependentReview`
correctly governs the custom `governance/exact-head-review` status check, but GitHub's own native
`require_code_owner_review` / `require_last_push_approval` rule was hardcoded `true` in the static
ruleset template, independent of any profile setting. For this repository — a solo maintainer whose
`CODEOWNERS` names only themselves — applying the ruleset as shipped would have made every future
governance-affecting PR unmergeable through GitHub's own UI (no one else can approve, and
self-approval isn't possible). This work wires those settings to the profile so the opt-out this
repository already made is consistent everywhere it's enforced, not just in the custom check.

## In scope

- `github-governance.sh` / `.ps1`: derive the ruleset's (and classic-branch-protection fallback's)
  `required_approving_review_count`, `dismiss_stale_reviews_on_push`, `require_code_owner_review`,
  and `require_last_push_approval` from `review.requiredApprovals`, `review.dismissStaleApprovals`,
  `review.requireCodeOwnerReview`, and `review.requireLastPushApproval` respectively, instead of the
  static template's hardcoded values. Booleans use an explicit `$v == null` check, not jq's `//` or
  PowerShell's naive `-or`, since both would silently treat an explicit `false` as "unset."
- `.github/governance-profile.json` (this repo only): set `requireCodeOwnerReview: false` and
  `requireLastPushApproval: false`, consistent with `requireIndependentReview: false` already set
  here — the same solo-maintainer rationale, now applied where it actually takes effect on GitHub's
  side. Also add `Governance / windows-verification` to `requiredStatusChecks`: it runs and passes
  on every PR already and is part of this kit's own acceptance surface, so it should be enforced
  once the ruleset is real.
- `github/governance-profile.json` (reusable template): unchanged — `true`/`true`/`0`/`true` remain
  the shipped defaults for downstream teams. `Governance / windows-verification` is deliberately
  *not* added here; it tests this kit's own bootstrap/migration behavior, not a downstream project's
  code, so it must not become a mandatory Windows-CI requirement for every consumer.
- `tests/acceptance.sh`: new coverage proving (a) explicit `false`/`0` review settings survive into
  the applied payload for both `sh` and (guarded by a real, working `pwsh`) PowerShell, (b) missing
  fields still fail closed to the strict defaults, and (c) the two implementations produce
  byte-identical `pull_request` rule parameters for the same input profile.
- `docs/security-model.md`: document that `requireIndependentReview` only ever governed the custom
  status check, and that the native review rule is now separately, explicitly wired.

## Out of scope

- Actually running `github-governance.sh --apply` — that's the owner's decision, made separately,
  after this fix merges and a fresh preflight confirms the blocker is gone.
- Any change to `review-gate.yml`'s base-SHA-only read pattern (already correct, untouched).
- `refs/pull/*` and GitHub Support ticket #4773987 — untouched, not part of this change.

## Completion evidence

- `sh tests/acceptance.sh`: all new checks pass; one pre-existing, unrelated environment failure
  (`lefthook` not resolved by `mise` in this shell) persists, not caused by this change.
- Manually verified (via `mise exec powershell@7.6.6 -- pwsh`, an isolated invocation that does not
  touch global `mise` config) that the PowerShell path produces byte-identical `pull_request`
  parameters to the shell path, for both the explicit-`false` fixture and the fields-omitted
  fixture, on both the ruleset path and the classic-branch-protection fallback path.
- `./github-governance.sh --repo Paul-Osborn/repo-governance-templates --profile .github/governance-profile.json`
  now prints `code owner review: false; last-push approval: false` for this repository, and the
  same command against the reusable template's profile still prints `true`/`true`.
