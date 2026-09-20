# Security and authority model

## Assets and invariants

V3 protects the default branch, credential-free history, bounded repository size, current test and
review evidence, governance trust roots, and the rule that an implementation agent cannot expand
or ratify its own authority.

## Threat model

The ordinary threat is a mistaken or over-eager tool, not a hostile machine administrator. A user
who controls the workstation can bypass local hooks. A token with repository-administration rights
can change hosting rules. Defense therefore combines local prevention, remote re-checks, restricted
workflow permissions, exact-state review, and a human-only trust-root merge decision.

Repository instructions are untrusted input with respect to the host. They cannot safely grant
broader sandbox permissions, credentials, or approval authority. User/organization agent settings
remain outside the repository trust boundary.

## Trust-root paths

`.governance/policy.json` lists the minimum trust root: canonical policy, version/policy metadata,
hooks and scanners, CI and review logic, GitHub workflow/CODEOWNERS/profile files, agent adapters,
and agent permission/hook configuration. The remote profile requires code-owner review and stale-
approval dismissal. If GitHub cannot enforce those features, the owner must perform the merge and
manually inspect the changed path list.

## Review attestation

The preferred GitHub control checks for an `APPROVED` review by someone other than the PR author
where the review's `commit_id` equals the current head SHA. It runs from the protected base-branch
workflow and publishes a status on that same SHA. Required status checks should bind that context
to the expected integration when GitHub exposes that capability.

The status producer intentionally uses `pull_request_target` so GitHub loads the protected base
workflow instead of a PR-modified copy. This trigger is broadly dangerous and is narrowly suppressed
in zizmor with an inline explanation: the job never checks out or executes PR content, checks that
the event's base repository is the current repository, passes event values only through quoted
environment variables, and has only pull-request-read plus status-write permission. Do not add a
checkout, dependency install, cache restore, artifact execution, or general write token to it.

By default the baseline uses the repository's shared GitHub Actions identity (`github-actions[bot]`,
`integration_id` 15368) for every required check, including `governance/exact-head-review`. A
repository administrator, or a credential able to alter protections/workflows, can forge or replace
that status because every other Actions job in the repository shares the same identity.

The review-gate workflow's `Mint dedicated reviewer identity token` step closes that gap when the
owner configures it: given a `GOVERNANCE_REVIEWER_APP_ID` repository variable and a
`GOVERNANCE_REVIEWER_APP_PRIVATE_KEY` repository secret for a dedicated, least-privilege GitHub
App (`contents:read`, `pull-requests:read`, `statuses:write` only, installed on this repository
only), the job mints an installation token via `actions/create-github-app-token` (pinned by commit
SHA) and publishes the `governance/exact-head-review` status under that App's identity instead of
the shared Actions bot. `github-governance.sh` / `.ps1` then bind that one required-check context to
`review.externalReviewerAppId` in `governance-profile.json`, while every other context keeps the
default Actions `integration_id` — so a required status check can trust this specific producer, not
any workflow holding the default token. Absent that configuration, the job falls back to
`github.token`, matching prior behavior with no regression.

Registering the App, generating and handling its private key, and installing it are human-only
steps: they require the owner's GitHub identity and are never performed by an implementation agent.
Until the owner completes that setup and this repository's own `externalReviewerAppId` is set,
governance changes remain human-only even when CI is green, exactly as before. Private repositories
may also lack ruleset/code-owner features on their plan.

GitHub's [ruleset status-check documentation](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets#require-status-checks-to-pass-before-merging)
explains that a required check can be bound to an expected GitHub App source. V3's profile exposes
that integration boundary so a dedicated reviewer service can replace the baseline producer.

The local-attestation fallback hashes path, Git mode, and object identity for every substantive
change. It allows deterministically prose-only follow-ups without changing the digest. Because the
attestation file and verifier live in the repository, an implementation agent with branch write
access can fabricate both. It is useful evidence for hosts without an API, not cryptographic
independence and not authority to merge governance.

## Optional independent-review opt-out

`review.requireIndependentReview` in `governance-profile.json` defaults to `true`. An owner who
sets it to `false` is stating, in a durable and auditable file, that no second human reviewer is
available for this repository — typically a solo maintainer doing AI-authored work. The review-gate
workflow reads this flag from `.github/governance-profile.json` at the pull request's base SHA, the
same base-ref-only pattern used for `trustRootPaths`, so a pull request cannot weaken this setting
in its own diff to escape review for itself; only a change merged to the protected default branch
takes effect. When the flag is `false`, `governance/exact-head-review` still runs and posts on every
PR, but always succeeds, so the choice remains visible on every PR rather than disappearing along
with the check. This is a documented reduction of the review boundary, not a bypass of it: the
`governance-profile.json` change that sets the flag is itself a governance/control-file change and
so is a proposal only an owner can ratify, per `AGENTS.md`.

`review.requireIndependentReview` only governs that one custom status check. It does not, by
itself, touch GitHub's own native pull-request review rule inside the applied ruleset (or its
classic-branch-protection fallback) — `require_code_owner_review` and `require_last_push_approval`
are a separate GitHub-side gate that `github-governance.sh` / `.ps1` build from
`review.requireCodeOwnerReview`, `review.requireLastPushApproval`, `review.requiredApprovals`, and
`review.dismissStaleApprovals` in the same profile. Earlier versions of this tooling left those four
hardcoded to strict values in the static ruleset template regardless of the profile, which meant a
solo repository could set `requireIndependentReview: false` and still find every governance PR
unmergeable through GitHub's own UI — CODEOWNERS naming the same person as both the sole reviewer
and the sole author, with no self-approval possible. The tooling now derives all four from the
profile (using an explicit null-check, not `//`, so an explicit `false` or `0` is preserved rather
than silently replaced by the default), so a solo maintainer's opt-out is consistent everywhere the
policy is enforced, not just in the custom status check.

GitHub's rulesets `pull_request` rule also carries a fifth native parameter,
`require_extra_approval_for_unattributed_changes`: it demands one additional approving review on a
pull request containing any commit GitHub cannot attribute to a verified, linked GitHub account
(for example, a commit whose author/committer email, or a `Co-authored-by` trailer's email, does not
resolve to one). GitHub defaults this to `true` on every newly created ruleset regardless of what
the requesting payload contains, and it only becomes visible once the ruleset object actually
exists — this kit's static ruleset template did not set it explicitly, so it surfaced as a residual
gap only after this repository's own ruleset went live (see `WORKLOG.md`, 2026-09-19). It is now an
explicit `review.requireExtraApprovalForUnattributedChanges` profile field, derived the same
null-checked way as the other four settings, and applied only on the rulesets path — classic branch
protection has no equivalent parameter, so `github-governance.sh` / `.ps1` say so in their plan
output rather than silently dropping it. The reusable template keeps GitHub's own fail-closed
default (`true`); this repository sets it to `false` for the same reason it already sets
`requireCodeOwnerReview` and `requireLastPushApproval` to `false` — a solo maintainer whose own
commits carry an AI co-author trailer would otherwise be unable to satisfy the extra-approval
requirement and every PR would become unmergeable.

## Fail direction

Merge-critical capability, review, path classification, and governance consistency checks fail
closed. Advisory warnings (for example lockfile-only changes) do not block. Capability tooling
prints plan-dependent gaps rather than silently treating an unavailable feature as enabled.
