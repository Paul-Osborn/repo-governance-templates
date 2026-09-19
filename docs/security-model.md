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

Remaining limitation: the baseline uses the repository's GitHub Actions identity, not a dedicated
reviewer GitHub App. A repository administrator or a credential able to alter protections/workflows
can forge or replace the status source. Private repositories may also lack ruleset/code-owner
features on their plan. The clean extension point is the `governance/exact-head-review` status:
replace its producer with an independently credentialed GitHub App and bind the ruleset's
`integration_id` to that App. Until then, governance changes remain human-only even when CI is green.

GitHub's [ruleset status-check documentation](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets#require-status-checks-to-pass-before-merging)
explains that a required check can be bound to an expected GitHub App source. V3's profile exposes
that integration boundary so a dedicated reviewer service can replace the baseline producer.

The local-attestation fallback hashes path, Git mode, and object identity for every substantive
change. It allows deterministically prose-only follow-ups without changing the digest. Because the
attestation file and verifier live in the repository, an implementation agent with branch write
access can fabricate both. It is useful evidence for hosts without an API, not cryptographic
independence and not authority to merge governance.

## Fail direction

Merge-critical capability, review, path classification, and governance consistency checks fail
closed. Advisory warnings (for example lockfile-only changes) do not block. Capability tooling
prints plan-dependent gaps rather than silently treating an unavailable feature as enabled.
