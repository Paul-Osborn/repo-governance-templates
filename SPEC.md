# Native Windows verification

## Outcome

Run V3's bootstrap, migration, hooks, and PowerShell acceptance suite on a real Windows host with
Git for Windows, and record that evidence, so the project can stop qualifying Windows support as
"not natively verified" (issue #9).

## In scope

- A permanent, least-privilege CI job that runs `tests/acceptance.ps1` on a GitHub-hosted
  `windows-latest` runner (native Git for Windows, native PowerShell), added to this repository's
  own active `.github/workflows/governance.yml`.
- Checksum-pinned Gitleaks/Lefthook binaries for Windows, verified against the same upstream
  release manifests already used for the Linux pins.
- Recording the runner OS build, PowerShell version, Git for Windows version, and pinned
  Gitleaks/Lefthook versions as part of the job's own output, and in `WORKLOG.md` /
  `docs/platform-support.md` once a run has actually passed.

## Out of scope

- Adding a Windows job to the *shipped* `github/workflows/governance.template.yml`. That template
  is copied into every downstream project bootstrapped from this kit, and those projects do not
  receive `tests/acceptance.ps1` (it is not a manifest-tracked template — it tests this kit's own
  bootstrap/migration behavior, not a downstream project's code). Shipping a Windows job by default
  to every consumer would be a real, unrequested cost/scope decision belonging to a separate
  conversation, not an implication of "verify this kit's own native Windows behavior." This mirrors
  the existing asymmetry between the `project` job's kit-specific tool installation in the active
  workflow and its generic form in the template.
- Issue #10 (distinct reviewer identity/App) and strict ruleset activation.
- Updating `docs/platform-support.md` / `WORKLOG.md` before a real passing native-Windows run
  exists to cite.

## Completion evidence

- A `Governance / windows-verification` job exists in `.github/workflows/governance.yml`, runs on
  `windows-latest`, and its own log records the Windows build, PowerShell version, Git for Windows
  version, and pinned tool versions.
- `tests/acceptance.ps1` passes on that job with 0 failures — a real run URL is the evidence, not a
  claimed count.
- `docs/platform-support.md` and `WORKLOG.md` are updated from "not natively verified" to the
  verified state, citing that run.
