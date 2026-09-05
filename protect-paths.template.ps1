# PreToolUse hook: block edits/writes to protected files and folders.
# Stops an agent from touching files that should only change deliberately
# (the governance gates, CI config, this hook itself, etc.).
#
# Install: copy to `.claude/hooks/protect-paths.ps1`, then wire it up in
# `.claude/settings.json` (see claude-settings.snippet.json in this template set).
# Edit the $protected list below for your project.
#
# Scope note: this blocks the AGENT's Edit/Write tools. It is a convenience layer for
# Claude Code, not a security boundary -- the gates that hold for every agent and for
# manual commits are the lefthook ones. Deny here means "not by accident".

$ErrorActionPreference = 'Stop'

# Glob-ish patterns (regex) for paths that must not be edited by the agent.
$protected = @(
    '(^|[\\/])\.git[\\/]',
    '(^|[\\/])\.github[\\/]workflows[\\/]',
    '(^|[\\/])\.claude[\\/]hooks[\\/]',

    # The agent must not be able to widen its own permission allowlist.
    # Merge power lives in settings.json; letting the agent edit it makes the whole
    # authority ceiling decorative.
    '(^|[\\/])\.claude[\\/]settings\.json$',

    # CI green is what unlocks a self-merge. If the agent can rewrite the
    # tests, it controls what "green" means and the gate leaks.
    # Replace/uncomment for your project's test directory (e.g. '(^|[\\/])tests[\\/]', '(^|[\\/])MyProject\.Tests[\\/]')
    # '(^|[\\/])tests[\\/]',

    # Governance gates. These define what "safe" means, so the agent must not be able to
    # edit them; a rule change is a PR for the human to ratify, not a quiet edit.
    '(^|[\\/])lefthook\.yml$',
    '(^|[\\/])\.gitleaks\.toml$',
    '(^|[\\/])scripts[\\/]hooks[\\/]',
    '(^|[\\/])\.claude[\\/]agents[\\/]',
    '(^|[\\/])\.governance-version$'

    # NOT protected in V2: dependency lockfiles (package-lock.json, poetry.lock, ...).
    # V1 blocked them outright, which also blocked the legitimate case -- you approve a
    # dependency, the package manager regenerates the lockfile, and the agent hits a wall
    # it can only clear by routing around a guardrail. The rule now lives where it belongs:
    # AGENTS.md says never hand-edit a lockfile (regenerate it through the package manager),
    # and scripts/hooks/check-lockfiles.sh warns on lockfile-only churn.
)

try {
    $raw = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }
    $payload = $raw | ConvertFrom-Json
} catch {
    exit 0  # can't parse -- stay out of the way
}

# Only guard tools that write files.
$tool = [string]$payload.tool_name
if ($tool -notin @('Edit', 'Write', 'NotebookEdit', 'MultiEdit')) { exit 0 }

$path = [string]$payload.tool_input.file_path
if ([string]::IsNullOrWhiteSpace($path)) { exit 0 }

foreach ($pattern in $protected) {
    if ($path -match $pattern) {
        $reason = @"
Refused: '$path' is a protected path (matches '$pattern').
These files change only by deliberate human decision, not automatically.
If this edit is genuinely intended, make it yourself or update the protected
list in .claude/hooks/protect-paths.ps1 first.
"@
        $out = @{
            hookSpecificOutput = @{
                hookEventName            = 'PreToolUse'
                permissionDecision       = 'deny'
                permissionDecisionReason = $reason
            }
        } | ConvertTo-Json -Compress -Depth 5
        Write-Output $out
        exit 0
    }
}

exit 0
