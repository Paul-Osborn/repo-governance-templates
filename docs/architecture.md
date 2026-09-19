# V3 architecture

Repo Governance V3 separates advice from enforcement so the failure of one layer does not silently
erase the others.

1. `AGENTS.md` is concise canonical policy for humans and agents. Nested files may specialize local
   implementation detail but cannot weaken root security or authority.
2. Lefthook, Gitleaks, and portable shell scripts enforce workstation lifecycle gates. They work
   without Claude Code, Codex, or any other agent.
3. Agent adapters point to `AGENTS.md` and may improve ergonomics. They are never the only control
   for a critical invariant.
4. CI and GitHub rules independently re-run checks and constrain merge. Governance ratification is
   always human-only.

## Installed core

| Destination | Purpose | Ownership |
|---|---|---|
| `AGENTS.md` | Canonical concise policy | Project-owned after bootstrap |
| `REPO_RULES.md` | Rationale, recovery, control matrix | Project-owned |
| `.governance/policy.json` | Machine-readable local policy/trust roots | Template-owned until customized |
| `lefthook.yml`, `.gitleaks.toml` | Local lifecycle configuration | Template-owned until customized |
| `scripts/hooks/` | Portable local gates | Template-owned until customized |
| `scripts/ci/` | CI validation and review interface | Template-owned; `project-checks.sh` becomes project-owned when filled |
| `.github/workflows/` | Remote checks and exact-head review status | Protected trust root |
| `.github/governance-profile.json` | Desired hosting state | Project-owned after owner/repo reconciliation |
| `.github/CODEOWNERS` | Human trust-root owner | Project-owned after bootstrap |

`governance-manifest.json` belongs to the template kit. It lists only files the updater may add or
replace when their normalized hash proves they are an unchanged shipped version.

## Review sequence

Implementation stabilizes, local/broad tests run, and a distinct reviewer approves the exact PR
head. The base-branch review workflow checks the review API without running PR code and publishes
`governance/exact-head-review` on that SHA. A later push creates a new SHA and therefore has no
matching success status until reviewed again. Prose-only PRs are classified by file type, except
that every trust-root path remains substantive.

Non-GitHub hosts can implement the same verifier contract or use the local digest fallback described
in the security model.

The ruleset's blanket approval count is zero: substantive review is enforced by the exact-head
status, while CODEOWNERS separately requires the human owner on trust-root changes. This preserves
the V2 exemption for deterministically prose-only PRs instead of imposing review ceremony on them.
