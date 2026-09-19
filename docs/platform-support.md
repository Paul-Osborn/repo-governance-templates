# Platform support

## Linux / Omarchy

Linux is a first-class path. Required base tools are POSIX `sh`, Git, `sed`, `awk`, and SHA-256
utilities. Bootstrap uses no language runtime. Safe updates additionally require `jq` to parse the
manifest. Lefthook and Gitleaks are required to activate all local gates; install them with the
platform package/tool manager, then run `lefthook install`.

```sh
export REPO_GOVERNANCE_HOME=/path/to/repo-governance-templates
"$REPO_GOVERNANCE_HOME/new-governed-repo.sh" --target . --name "My project" --owner my-login
"$REPO_GOVERNANCE_HOME/update-governance.sh" --target . --dry-run
```

The acceptance suite creates disposable repositories and can use tool paths supplied through the
environment. Omarchy-specific desktop configuration is neither required nor modified.
`sync-remotes.sh` provides the V2 safe mirror-convergence behavior on Linux.

## Windows PowerShell

PowerShell 5.1 remains supported by `new-governed-repo.ps1`, `update-governance.ps1`,
`update-global-rules.ps1`, and `github-governance.ps1`. Git for Windows supplies the POSIX shell
used by Lefthook; `.gitattributes` forces LF endings for hook scripts. Install Lefthook and Gitleaks,
then run `lefthook install` in the governed repository.

```powershell
& "$env:REPO_GOVERNANCE_HOME\new-governed-repo.ps1" -Target . -Name "My project" -Owner "my-login"
& "$env:REPO_GOVERNANCE_HOME\update-governance.ps1" -Target . -DryRun
```

V3's Linux acceptance suite runs on this project's Linux path. The PowerShell acceptance suite can
also run under PowerShell Core on Linux for real script-execution coverage, and Windows scripts
receive fixture and static compatibility tests. That is not a substitute for a native Windows run;
a release must state explicitly when it was not executed on a real Windows host.

## GitHub controls

GitHub setup requires authenticated `gh`; the Linux command also uses `jq`. Both setup tools are
plan-only by default. Rulesets are preferred. If the API reports them unavailable, the tool plans
classic branch protection and reports any rejected setting for manual owner action.

GitHub documents that repository rulesets are available for public repositories on Free and for
private repositories on Pro/Team/Enterprise, while protected-branch availability also varies by
visibility and plan. Verify the current matrix in GitHub's
[rulesets documentation](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets)
and [protected-branch documentation](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches).
