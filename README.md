# Repo Governance V3

A public, reusable governance kit for AI-assisted repositories. V3 keeps policy concise and moves
critical invariants into agent-neutral Git hooks, CI, hosting protection, and human approval.

> Written rules guide agents. Independent controls enforce invariants. An agent must not be able
> to grant itself more authority by editing the rules that govern it.

## What V3 provides

- one canonical cross-agent policy in `AGENTS.md`, with thin Claude/Gemini/Cursor adapters;
- Linux/Omarchy and Windows bootstrap/update paths;
- Lefthook gates for the protected branch, staged secrets, new large files, commit messages, and
  suspicious lockfile-only changes;
- least-privilege, commit-pinned GitHub CI that re-runs governance, Gitleaks, project checks, and
  zizmor workflow analysis;
- exact-HEAD independent GitHub review verification, with an honestly limited digest fallback;
- a machine-readable trust root and desired GitHub profile;
- plan-first GitHub ruleset/branch-protection setup with capability reporting;
- hash-safe V2→V3 migration: dry-run, backups, customization preservation, and idempotency.

No agent product, cloud service, server, database, or specification framework is required.

## Control layers

| Layer | What belongs there | What it can guarantee |
|---|---|---|
| Advisory | `AGENTS.md`, `REPO_RULES.md` | Shared expected behavior; not a security boundary |
| Local | Lefthook, Gitleaks, portable shell gates | Early refusal on every agent/manual commit when hooks are installed |
| Remote | CI, exact-head status, GitHub ruleset/branch protection | Independent re-check and merge constraints after push |
| Human-only | Trust-root ratification and exceptional authority decisions | An implementation agent cannot approve its own authority change |

See [architecture](docs/architecture.md) and [security model](docs/security-model.md) for the trust
boundaries and remaining review-attestation limitation.

## Bootstrap a new repository

Install Git, Lefthook, and Gitleaks first. Linux updates also use `jq`.

Linux / Omarchy:

```sh
./new-governed-repo.sh --target /path/to/project --name "My project" --owner github-login
```

Windows PowerShell 5.1+:

```powershell
& "$env:REPO_GOVERNANCE_HOME\new-governed-repo.ps1" `
  -Target C:\path\to\project -Name "My project" -Owner "github-login"
```

The scripts preserve unrelated pre-existing files, refuse an already governed target unless the
explicit force option is used, initialize `main`, install Lefthook when available, and stamp
`.governance-version`. Use the updater—not bootstrap—to migrate existing governance. Then:

1. fill `PRD.md` and the project-specific placeholders in `AGENTS.md` / `REPO_RULES.md`;
2. put real lint/test/build commands in `scripts/ci/project-checks.sh`;
3. create a branch and commit governance before product code;
4. inspect the GitHub remote plan before applying it.

The specification workflow stays deliberately small: project intent in `PRD.md`, a bounded
`SPEC.md` for substantial work, explicit non-goals/acceptance evidence, and durable `WORKLOG.md`
entries only at meaningful checkpoints.

## Local enforcement

`lefthook.yml` activates these portable gates:

| Gate | Behavior |
|---|---|
| protected default branch | refuses commits on `main`, `master`, or the configured/remote default |
| Gitleaks | refuses staged credentials and redacts findings |
| large files | refuses newly added files over 2048 KiB (configurable) |
| lockfiles | warns, but does not block, when a lockfile changes without its manifest |
| Conventional Commits | checks the commit subject type/scope/length |
| project checks | runs the repository-configured script before push |

Hooks are early feedback, not the final trust boundary. CI re-runs the critical checks.

## Independent review

The default GitHub path requires an approval by someone other than the PR author whose review
`commit_id` equals the current PR head. A protected base-branch workflow publishes
`governance/exact-head-review` on that exact SHA. A behavior-changing push changes the SHA and
invalidates review. Deterministically prose-only PRs are exempt; governance Markdown never is.

For other hosts, copy `review-attestation.template.json` to
`.governance/review-attestation.json`, fill it from an independent review, and run:

```sh
scripts/ci/verify-review.sh --mode local-attestation --base origin/main
```

That fallback binds evidence to a deterministic code digest, but anyone who can write the branch
can fabricate it. It is not cryptographic independence. A dedicated reviewer GitHub App can later
replace the status producer without changing the required status interface.

## GitHub policy: inspect before mutation

The desired state lives in `github/governance-profile.json` (and is copied into governed GitHub
repositories). Plan mode is the default:

```sh
./github-governance.sh --repo OWNER/REPOSITORY
```

```powershell
.\github-governance.ps1 -Repo OWNER/REPOSITORY
```

Only after the human owner reviews the output:

```sh
./github-governance.sh --repo OWNER/REPOSITORY --apply
```

Rulesets are preferred. If the API reports them unavailable, the tool attempts classic branch
protection only when apply is explicitly requested and reports rejected settings. GitHub plan and
visibility determine availability of rulesets, code-owner review, private-repository protection,
and Advanced Security. The zizmor job deliberately uses its non-Advanced-Security mode, and the
Gitleaks job uses the checksum-pinned open-source CLI rather than the separately licensed Action. See
[platform support](docs/platform-support.md).

## Upgrade an existing governed repository

Always inspect first:

```sh
./update-governance.sh --target /path/to/project --dry-run
```

```powershell
.\update-governance.ps1 -Target C:\path\to\project -DryRun
```

`ADD` and `UPGRADE` are safe manifest-owned changes. `CONFLICT` means the project customized that
file; it is preserved for human reconciliation. Apply without the dry-run flag. Replaced files are
backed up under `.governance-backup/`; a second run is a no-op. Project source, briefs, worklogs, and
filled canonical policy are never blindly replaced. Follow the full [V2 migration guide](docs/migration-v2-to-v3.md).

## Repository contents

| Path | Purpose |
|---|---|
| `AGENTS.template.md` | concise canonical policy installed as `AGENTS.md` |
| `REPO_RULES.template.md` | rationale, control matrix, recovery, platform details |
| `new-governed-repo.{sh,ps1}` | Linux/Windows bootstrap |
| `update-governance.{sh,ps1}` | hash-safe migration/update |
| `sync-remotes.{sh,ps1}` | safe fast-forward synchronization; refuses divergence and force |
| `governance-manifest.json` | template-owned destinations and known shipped hashes |
| `lefthook.template.yml`, `*.template.sh` | agent-neutral local gates |
| `scripts/ci/` | consistency, classification, and review-verification interfaces |
| `github/` | workflow, CODEOWNERS, profile, and ruleset templates |
| `github-governance.{sh,ps1}` | plan/apply remote controls |
| `adapters/` and root adapter templates | agent-specific pointers/notes |
| `global/` | generic new-project user-level bootstrap |
| `tests/` | disposable-repository acceptance suites |
| `docs/` | architecture, security, platforms, and migration |

The V2 Claude PowerShell hooks remain as clearly labeled legacy optional adapters for existing
Windows projects. V3 does not install them by default and no critical invariant depends on them.

## Verification

Linux / Omarchy:

```sh
sh tests/acceptance.sh
```

Windows PowerShell:

```powershell
.\tests\acceptance.ps1
```

Both suites use disposable repositories. Release/PR evidence must state which operating systems
were actually executed; static compatibility checks are not represented as real Windows execution.

## Governance changes

The trust-root paths are listed in `.governance/policy.json` in an installed repository and owned
through CODEOWNERS. An agent may propose a change, test it, and open a PR. It may not approve or
merge that PR. Final ratification belongs to the human owner, even when every automated check is
green.
