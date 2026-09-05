# Stop hook: safety net that auto-commits and pushes leftover work when a turn ends.
# Keeps git hands-off -- work is never left uncommitted or unpushed. It is a backstop;
# the agent should still commit deliberately with good messages during the turn.
#
# Rules it follows:
#   - Never acts on `main`/`master` (those are protected; work belongs on a branch).
#   - Only commits if there are actual changes.
#   - The commit runs the normal pre-commit gates (branch guard, secret scan, large-file
#     check). If one fails the commit fails, the work stays uncommitted, and this hook exits
#     quietly -- so the safety net never leaks a credential or smuggles a huge file in.
#   - Pushes the branch to EVERY remote, so a mirror never silently falls behind and the
#     owner never has to push twice.
#   - Best-effort: it never blocks the turn from ending.
#
# Install: copy to `.claude/hooks/auto-commit.ps1`, then wire it up in `.claude/settings.json`
# (see claude-settings.snippet.json in this template set).

$ErrorActionPreference = 'SilentlyContinue'

try {
    $branch = (git rev-parse --abbrev-ref HEAD 2>$null | Out-String).Trim()
    if (-not $branch -or $branch -in @('main', 'master', 'HEAD')) { exit 0 }

    $changes = (git status --porcelain 2>$null | Out-String).Trim()
    if ($changes) {
        git add -A 2>$null | Out-Null
        # If this commit fails (e.g. a gate blocks it), the work stays uncommitted. That is
        # the correct outcome -- better a dirty tree than a bad commit.
        git commit -m "chore: checkpoint (auto-saved at end of turn)" 2>$null | Out-Null
    }

    # Back the branch up to every remote. Harmless if already up to date. Only ever
    # fast-forwards: no --force, ever, from an automatic hook.
    foreach ($remote in @(git remote 2>$null)) {
        $r = ([string]$remote).Trim()
        if ($r) { git push -u $r $branch 2>$null | Out-Null }
    }
} catch {
    # Never get in the way of the turn ending.
}

exit 0
