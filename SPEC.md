# Optional independent-review opt-out

## Outcome

Let an owner explicitly turn off the independent-review requirement for a repository with no
second human reviewer available (a solo maintainer doing AI-authored work), without weakening the
reusable template's default for teams that do have a second reviewer.

## Motivation

This repository's own `governance/exact-head-review` check requires an `APPROVED` GitHub review
from someone other than the PR author on the exact head SHA. For a solo maintainer directing an AI
agent, no such second identity exists by default, which made every governance-affecting PR
(including PR #14, the reviewer-App work) unable to pass that check on its own terms. `AGENTS.md`
already reserves final ratification of governance/control-file changes to the human owner (rule 7);
this change makes the review-gate mechanism itself aware of that reality instead of leaving it as
an unstated exception.

## In scope

- `governance-profile.json` (both `github/` template and this repo's `.github/` instance): add
  `review.requireIndependentReview`, defaulting to `true` in the template, set to `false` here.
- `.github/workflows/review-gate.yml` / `github/workflows/review-gate.template.yml`: read the flag
  from the pull request's **base SHA** copy of `.github/governance-profile.json` (never the PR's
  own copy — the same base-ref-only pattern already used for `trustRootPaths`), so a PR cannot
  weaken this setting in its own diff to escape review for itself. When `false`, the status still
  runs and posts on every PR but always succeeds, keeping the choice visible rather than removing
  the check outright.
- `github-governance.sh` / `.ps1`: plan output states plainly when a required check is a no-op
  because independent review is not required by policy.
- `AGENTS.md` / `AGENTS.template.md` rule 5, `REPO_RULES.md` / `REPO_RULES.template.md` §6,
  `docs/security-model.md`: document the opt-out, its default, and why it isn't a silent bypass.
- `governance-manifest.json`: updated normalized hashes for the two changed managed/add-only
  templates, prior hashes preserved in `knownHashes`.

## Out of scope

- Changing `requiredApprovals`, `requireCodeOwnerReview`, or any other native GitHub
  branch-protection review setting.
- Applying the strict ruleset (`github-governance.sh --apply`) — remains plan-only per `AGENTS.md`.
- The `local-attestation` review mode in `scripts/ci/verify-review.sh` (a separate, already-weaker
  fallback for hosts without a review API); not wired into any live check today, left unchanged.

## Known bug fixed during implementation

`jq`'s `//` operator treats a literal `false` the same as `null` (both are falsy), so a naive
`.review.requireIndependentReview // true` silently ignored an explicit `false`. Fixed with
`.review.requireIndependentReview as $v | if $v == null then true else $v end` everywhere the flag
is read, so only a genuinely absent field falls back to the safe default (`true`, still require
review).

## Completion evidence

- `sh tests/acceptance.sh`: 81/81 relevant checks pass (one unrelated environment failure —
  `lefthook` not resolved by `mise` in this shell — predates this change and is not caused by it).
- `sh scripts/ci/validate-governance.sh` and `sh -n ./*.sh ./*.template.sh scripts/ci/*.sh` pass.
- `./github-governance.sh --repo Paul-Osborn/repo-governance-templates --profile .github/governance-profile.json`
  shows `governance/exact-head-review (independent review not required by policy; this check
  always succeeds)` instead of a reviewer-App or default-identity binding.
- This PR itself still requires independent review under `main`'s current (pre-merge) policy — it
  is a governance/control-file change ratified by the owner merging it directly, per `AGENTS.md`
  rule 7 — and is the first live opportunity to confirm `governance/exact-head-review` posts under
  the dedicated reviewer App's identity now that PR #14 is on `main`.
