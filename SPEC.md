# Dedicated reviewer GitHub App (issue #10)

## Outcome

Give the independent-review status producer (`governance/exact-head-review`) a distinct,
least-privilege GitHub identity so a required status check can trust that specific producer
instead of the shared Actions bot every other check also uses (issue #10).

## In scope (agent-executable, no owner credentials)

- `.github/workflows/review-gate.yml` / `github/workflows/review-gate.template.yml`: mint an
  installation token from a GitHub App (`actions/create-github-app-token`, pinned by commit SHA)
  when `vars.GOVERNANCE_REVIEWER_APP_ID` and `secrets.GOVERNANCE_REVIEWER_APP_PRIVATE_KEY` are
  configured, scoped to `contents:read`, `pull-requests:read`, `statuses:write` only. Falls back
  to `github.token` (today's behavior) when unconfigured, so nothing regresses before the owner
  finishes setup.
- `github-governance.sh` / `github-governance.ps1`: resolve `integration_id` per required-check
  context instead of hardcoding one value for all five. `governance/exact-head-review` binds to
  `review.externalReviewerAppId` once the owner sets it in the profile; every other context keeps
  `review.preferredTrustedIntegrationId` (the default Actions identity, 15368). The plan output
  now shows which identity each check is bound to.
- `governance-manifest.json`: updated normalized hash for `review-gate.template.yml`, prior hash
  preserved in `knownHashes`.
- `docs/security-model.md`: describe the implemented mechanism and what remains owner-only.

## Out of scope (human-only; see the owner checkpoint delivered with this work)

- Registering the GitHub App itself, choosing its name, generating or handling its private key,
  and installing it on the repository. An agent must not do this: it requires the owner's GitHub
  identity, may prompt 2FA, and handling a downloaded private key belongs to the owner alone.
- Setting `GOVERNANCE_REVIEWER_APP_ID` (repo variable) and `GOVERNANCE_REVIEWER_APP_PRIVATE_KEY`
  (repo secret) in GitHub repository settings.
- Setting `github/governance-profile.json` / `.github/governance-profile.json`'s
  `review.externalReviewerAppId` to the real App ID — an agent can do this once the owner supplies
  the ID (no credentials required for that step), but not before the App exists.
- Activating the strict GitHub ruleset (`github-governance.sh --apply`). It remains plan-only per
  `AGENTS.md`'s control boundaries regardless of App status.

## Completion evidence

- `sh tests/acceptance.sh` and `pwsh tests/acceptance.ps1` pass with the updated scripts/workflow.
- `zizmor` reports no findings on the updated `review-gate.yml`.
- A live PR against `main`, opened after the owner finishes the human-only setup, shows the
  `governance/exact-head-review` status posted by the dedicated App identity (not
  `github-actions[bot]`).
- `docs/security-model.md` no longer describes the App-based identity as a future extension point
  only; it describes the implemented, owner-activatable mechanism.
