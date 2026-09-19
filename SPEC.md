# Trust-root consistency

## Outcome

Make `.governance/policy.json` (generated from `governance-policy.template.json`) the canonical
trust-root path list. Every enforcement surface must either consume that list directly or be
deterministically checked against it.

## In scope

- Make the change classifier read `trustRootPaths` from the canonical policy.
- Make the protected-base review workflow fetch the canonical policy from the exact base SHA,
  without checking out or executing pull-request content.
- Validate that CODEOWNERS covers exactly the canonical trust roots.
- Align and verify the legacy PowerShell git-guard fallback list.
- Add acceptance coverage that fails when any checked surface drifts.
- Update manifest hashes and documentation required by the behavior change.

## Out of scope

- Changing the trust-root path set itself.
- Changing review policy, reviewer identity, or GitHub ruleset activation.
- Reworking the optional path-protection adapter beyond trust-root classification.

## Completion evidence

- Linux acceptance suite passes.
- PowerShell compatibility suite passes.
- Governance structure validation passes for both the kit and a generated repository.
- A fixture with CODEOWNERS drift is rejected.
- A fixture-added trust-root Markdown path is classified as substantive without editing the
  classifier or workflow.
