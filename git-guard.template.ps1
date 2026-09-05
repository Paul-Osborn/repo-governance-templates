# PreToolUse hook (Bash): every git/PR policy for this repo, in one place.
#
# INSTALL: copy to `.claude/hooks/git-guard.ps1` and point .claude/settings.json at it.
#
# WHY ONE FILE: Claude Code runs every matching PreToolUse hook on every Bash call.
# Six separate guards would mean six PowerShell process spawns per command, which is
# genuinely slow on Windows. One script, clearly sectioned, costs one spawn.
#
# The rules, in order:
#   0. Redirection guard  -- refuses `>`/`>>` aimed at governance files (protect-paths bypass)
#   1. No-verify guard    -- refuses --no-verify / `git commit -n` (one-flag lefthook bypass)
#   2. Branch guard       -- refuses commit/push on main/master
#   3. Review receipt     -- refuses `gh pr create` / `fj pr create` for UNREVIEWED substantive work
#   4. Merge gate         -- refuses `gh pr merge` when checks aren't green, or --admin is used
#   5. Authority ceiling  -- refuses any PR merge that edits the rules themselves
#
# FAIL DIRECTION: rules 1-3 fail OPEN (a parse or git error gets out of the way).
# Rules 4/5 fail CLOSED -- if it can't be determined, the merge is refused. Merging is the
# irreversible one; "I couldn't tell" must not mean "go ahead".
#
# HOSTS: `gh` (GitHub) and `fj` (Forgejo) are both handled. The receipt and authority rules
# are computed from local git, so they work on any host. The green-CI gate needs the host
# API and is GitHub-only; on Forgejo the local gates plus the authority ceiling apply.

$ErrorActionPreference = 'Stop'

function Deny([string]$reason) {
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

try {
    $raw = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }
    $payload = $raw | ConvertFrom-Json
} catch {
    exit 0  # can't parse -- stay out of the way
}

$cmd = [string]$payload.tool_input.command
if ([string]::IsNullOrWhiteSpace($cmd)) { exit 0 }

# Blank out quoted strings before pattern matching, so a commit MESSAGE that happens to
# mention "--no-verify" or "gh pr merge" doesn't trip a guard. Matching runs on $cmdClean;
# anything shown back to the user uses the original $cmd.
$cmdClean = $cmd -replace '"[^"]*"', '""' -replace "'[^']*'", "''"

# ---------------------------------------------------------------------------
# Shared: which files are "governance" (rules, gates, authority)
# ---------------------------------------------------------------------------
# One list, used by both the review-receipt classifier and the authority ceiling, so the
# two can never drift apart. Paths are repo-relative with forward slashes.
$GovernancePatterns = @(
    '^AGENTS\.md$',
    '^CLAUDE\.md$',
    '^GEMINI\.md$',
    '^REPO_RULES\.md$',
    '^\.claude/',
    '^\.cursor/',
    '^\.github/workflows/',
    '^scripts/hooks/',
    '^lefthook\.yml$',
    '^\.gitleaks\.toml$',
    '^\.governance-version$'
)

# The review receipt lives under .claude/ but is EVIDENCE, not authority. If it counted as
# governance it would be self-defeating twice over: committing the receipt would change the
# reviewed code and invalidate itself (an unbreakable loop), and a PR could never be merged
# by the agent simply because it carried its own proof of review.
function Test-ReviewEvidence([string]$path) {
    return ($path -match '^\.claude/review/')
}

function Test-Governance([string]$path) {
    if (Test-ReviewEvidence $path) { return $false }
    foreach ($p in $GovernancePatterns) { if ($path -match $p) { return $true } }
    return $false
}

# "Exempt" = prose that cannot change behaviour. A branch touching ONLY these is trivial
# and does not need an independent AI review; and a doc commit added AFTER a review does
# not invalidate that review. Governance files are never exempt, even though they are .md.
function Test-Exempt([string]$path) {
    if (Test-ReviewEvidence $path) { return $true }
    if (Test-Governance $path) { return $false }
    if ($path -match '^docs/') { return $true }
    if ($path -match '\.md$') { return $true }
    if ($path -match '^(WORKLOG|CHANGELOG)(\.[A-Za-z]+)?$') { return $true }
    return $false
}

# The branch's base: the commit this work forks from. Prefer the remote default branch.
function Get-BaseCommit {
    foreach ($ref in @('origin/main', 'origin/master', 'main', 'master')) {
        $exists = (git rev-parse --verify --quiet "$ref" 2>$null | Out-String).Trim()
        if ($exists) {
            $mb = (git merge-base HEAD $ref 2>$null | Out-String).Trim()
            if ($mb) { return $mb }
        }
    }
    return $null
}

# ---------------------------------------------------------------------------
# 0. Redirection guard
# ---------------------------------------------------------------------------
# Stops `>` / `>>` from overwriting a governance file, which would sidestep
# protect-paths.ps1 entirely (that hook only sees Edit/Write, not Bash).
if ($cmdClean -match '>>?\s*[''"]?(\.claude/|\.github/|scripts/hooks/|AGENTS\.md|REPO_RULES\.md|CLAUDE\.md|GEMINI\.md|lefthook\.yml|\.gitleaks\.toml|\.governance-version)') {
    Deny @"
Refused: shell redirection ('>' or '>>') targeting a governance path is blocked.

Rules, hooks, CI workflows and settings change deliberately -- by an edit you can see in a
diff -- not by a redirect buried in a command line.
"@
}

# ---------------------------------------------------------------------------
# 1. No-verify guard
# ---------------------------------------------------------------------------
# `git commit --no-verify` skips lefthook entirely -- branch guard, secret scan and
# large-file gate all at once. It is a one-flag hole through the whole local gate.
# `-n` is only dangerous on commit (on push it means --dry-run, which is harmless).
# Detects standalone `--no-verify`, `-n`, and bundled short flags (e.g. `-anm`).
if ($cmdClean -match '\bgit\b[^&|;]*--no-verify\b' -or
    $cmdClean -match '\bgit\s+commit\b[^&|;]*\s-[a-zA-Z0-9]*n[a-zA-Z0-9]*\b') {
    Deny @"
Refused: --no-verify skips the pre-commit checks (branch guard, secret scan, large-file gate).

AGENTS.md: don't disable or work around a guardrail to get unblocked -- fix the underlying
cause. If a hook is failing, read what it said and address it. If the hook itself is wrong,
that's a governance change: raise it with the owner.
"@
}

# ---------------------------------------------------------------------------
# 2. Branch guard
# ---------------------------------------------------------------------------
# Match primary subcommands per segment so `git log --grep=commit` and `git stash push`
# are allowed through.
$isCommitOrPush = $false
foreach ($segment in ($cmdClean -split '[&|;]')) {
    if ($segment -match '^\s*git\s+(?:-[Cc]\s+\S+\s+)*(commit|push)\b' -and
        $segment -notmatch '\bgit\s+stash\s+push\b') {
        $isCommitOrPush = $true
        break
    }
}

if ($isCommitOrPush) {

    # Prefer the repo the command targets via `-C <path>`, else the hook's own cwd.
    $repoPath = $null
    if ($cmd -match 'git\s+-C\s+"([^"]+)"') { $repoPath = $Matches[1] }
    elseif ($cmd -match "git\s+-C\s+'([^']+)'") { $repoPath = $Matches[1] }
    elseif ($cmd -match 'git\s+-C\s+(\S+)') { $repoPath = $Matches[1] }

    # `symbolic-ref --short -q HEAD` FIRST, because it is the only one that works before the
    # repo's first commit. `rev-parse --abbrev-ref HEAD` answers "HEAD" on an unborn branch,
    # which used to let the very first commit of a brand-new project land straight on main --
    # the one moment a new repo most needs the guard. Falls back to rev-parse for a detached
    # HEAD, where symbolic-ref legitimately has no answer.
    try {
        if ($repoPath) {
            $branch = (git -C $repoPath symbolic-ref --short -q HEAD 2>$null)
            if (-not ($branch | Out-String).Trim()) { $branch = (git -C $repoPath rev-parse --abbrev-ref HEAD 2>$null) }
        } else {
            $branch = (git symbolic-ref --short -q HEAD 2>$null)
            if (-not ($branch | Out-String).Trim()) { $branch = (git rev-parse --abbrev-ref HEAD 2>$null) }
        }
    } catch {
        exit 0  # not a git repo / git unavailable -- stay out of the way
    }

    $branch = ($branch | Out-String).Trim()
    if ($branch -in @('main', 'master')) {
        Deny @"
Refused: you are on '$branch' and the rules require branching before any commit or push.
Create a branch first, then re-run:
  git switch -c <type>/<short-desc>   # e.g. feat/add-export, fix/null-on-empty-input

Note: merging a reviewed, green PR into main is allowed and is a different act.
Committing directly to main is not.
"@
    }
}

# ---------------------------------------------------------------------------
# 3. Review receipt  --  gh pr create / fj pr create
# ---------------------------------------------------------------------------
# The rule: substantive work gets one independent review before the PR opens. The reviewer
# leaves findings; the primary agent records them in .claude/review/receipt.json.
#
# V2 changes two things about V1's version of this gate:
#
#   * TRIVIAL WORK IS EXEMPT. V1 demanded a receipt for every PR, including a README typo.
#     That taught the habit of running a costly reviewer purely to produce a file. If a
#     branch touches only prose (docs, *.md that isn't a rules file), no receipt is needed.
#
#   * THE RECEIPT TRACKS THE CODE, NOT THE COMMIT. V1 pinned the receipt to a SHA, so
#     appending a WORKLOG entry after the review invalidated it and forced a re-review that
#     could not possibly find anything new. V2 hashes the diff of the SUBSTANTIVE files
#     only. Change the code and the digest moves (review is stale, correctly). Add prose
#     and it doesn't (review still stands).
#
# HONEST LIMITATION, unchanged from V1: this forces the review to HAPPEN and to be recorded
# against specific code. It cannot force the agent to act on what the review said, and an
# agent determined to fake a receipt can. It is a tripwire, not a cage.
if ($cmdClean -match '\b(gh|fj)\s+pr\s+create\b') {
    $root = $null; $head = $null; $base = $null
    try {
        $root = (git rev-parse --show-toplevel 2>$null | Out-String).Trim()
        $head = (git rev-parse HEAD 2>$null | Out-String).Trim()
        $base = Get-BaseCommit
    } catch {
        exit 0  # can't resolve the repo -- stay out of the way
    }

    if ($root -and $head -and $base) {
        $changed = @(git diff --name-only $base HEAD 2>$null |
                     ForEach-Object { $_.Trim() } |
                     Where-Object { $_ })
        $substantive = @($changed | Where-Object { -not (Test-Exempt $_) })

        if ($substantive.Count -gt 0) {

            # Digest = SHA-256 of the diff restricted to substantive files.
            $diffText = (git diff $base HEAD -- $substantive 2>$null | Out-String)
            $sha256 = [System.Security.Cryptography.SHA256]::Create()
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($diffText)
            $digest = ([BitConverter]::ToString($sha256.ComputeHash($bytes)) -replace '-', '').ToLower()
            $sha256.Dispose()

            $receiptPath = Join-Path $root '.claude/review/receipt.json'
            $template = @"
       {
         "sha":        "$head",
         "codeDigest": "$digest",
         "reviewer":   "code-reviewer",
         "verdict":    "PASS"  (or "CHANGES_ADDRESSED"),
         "reviewedAt": "<ISO-8601 timestamp>",
         "findings":   "<one line per finding, and what you did about it>"
       }
"@

            if (-not (Test-Path $receiptPath)) {
                $list = ($substantive | Select-Object -First 12 | ForEach-Object { "  - $_" }) -join "`n"
                Deny @"
Refused: no review receipt at .claude/review/receipt.json, and this branch changes code.

Substantive files on this branch:
$list

Do this now:
  1. Launch the 'code-reviewer' subagent ONCE and give it this branch's diff.
  2. Fix what it finds that is valid.
  3. Write .claude/review/receipt.json:
$template
  4. Say in the PR body what you pushed back on and why.

If this branch really is prose-only, nothing here would have triggered -- so it isn't.
"@
            }

            $receipt = $null
            try { $receipt = Get-Content $receiptPath -Raw | ConvertFrom-Json }
            catch {
                Deny "Refused: .claude/review/receipt.json is not valid JSON. Re-run the reviewer and rewrite it."
            }

            $verdict = [string]$receipt.verdict
            if ($verdict -notin @('PASS', 'CHANGES_ADDRESSED')) {
                Deny @"
Refused: the review receipt has no usable verdict (found: '$verdict').

A receipt has to state a conclusion. Set "verdict" to "PASS" if the reviewer found nothing
material, or "CHANGES_ADDRESSED" if it found things and you fixed them.
"@
            }

            $recordedDigest = [string]$receipt.codeDigest
            if ($recordedDigest -ne $digest) {
                Deny @"
Refused: the review receipt does not match the code on this branch.

  reviewed code: $(if ($recordedDigest) { $recordedDigest.Substring(0, [Math]::Min(16, $recordedDigest.Length)) } else { '(none recorded)' })
  current code:  $($digest.Substring(0, 16))

The code changed after it was reviewed, so what you're about to submit has not been looked
at. Expected when you commit the reviewer's fixes -- re-run the reviewer on the current
branch and rewrite the receipt:
$template

(Prose-only commits -- docs, WORKLOG, plain *.md -- do NOT change this digest. If it moved,
real code moved.)
"@
            }
        }
    }
}

# ---------------------------------------------------------------------------
# 4 & 5. Merge gate + authority ceiling  --  gh pr merge / fj pr merge
# ---------------------------------------------------------------------------
if ($cmdClean -match '\b(gh|fj)\s+pr\s+merge\b') {

    $isGh = $cmdClean -match '\bgh\s+pr\s+merge\b'

    # --admin bypasses required checks. Never legitimate here.
    if ($cmdClean -match '--admin\b') {
        Deny "Refused: --admin bypasses the checks that make self-merging safe. Fix what's red instead."
    }

    # --- 5. Authority ceiling ---------------------------------------------
    # The agent may propose rule changes; only the human ratifies them. Without this, merge
    # power is self-amplifying: the agent could merge a PR widening its own permissions.
    #
    # Computed from LOCAL git, not the host API, so it holds on GitHub and Forgejo alike and
    # cannot be dodged by merging from a host the gate doesn't speak.
    $touched = @()
    $baseKnown = $false
    try {
        $base = Get-BaseCommit
        if ($base) {
            $baseKnown = $true
            foreach ($f in @(git diff --name-only $base HEAD 2>$null)) {
                $p = $f.Trim()
                if ($p -and (Test-Governance $p)) { $touched += $p }
            }
        }
    } catch {
        $baseKnown = $false
    }

    if (-not $baseKnown) {
        Deny @"
Refused: couldn't work out what this branch changes relative to the default branch, so the
authority ceiling can't be checked.

Fetch the default branch (`git fetch origin`) and try again. A merge that can't be checked
does not get to proceed on the assumption it's fine.
"@
    }

    if ($touched.Count -gt 0) {
        $list = ($touched | Select-Object -Unique | ForEach-Object { "  - $_" }) -join "`n"
        Deny @"
Refused: this PR changes the rules that govern you, so it is the owner's to merge -- not yours.

Governance files touched:
$list

This is the ceiling on your own authority: you may propose and argue for a rule change, but
you may not ratify one. Post the PR link and let the owner decide.
"@
    }

    # --- 4. Merge gate: every check must be green --------------------------
    # Needs the host API. `gh` has it; `fj` (Forgejo) has no equivalent wrapper, and V2 is
    # deliberately not building a cross-host PR abstraction. On Forgejo the branch guard,
    # secret scan, large-file gate, review receipt and authority ceiling above still apply --
    # this specific check does not.
    if (-not $isGh) { exit 0 }

    # `gh pr merge 38` targets a number; bare `gh pr merge` uses the current branch.
    $prRef = $null
    if ($cmdClean -match '\bgh\s+pr\s+merge\s+(\d+)') { $prRef = $Matches[1] }

    $viewArgs = @('pr', 'view')
    if ($prRef) { $viewArgs += $prRef }
    $viewArgs += @('--json', 'statusCheckRollup,number,title')

    $info = $null
    try {
        $json = & gh @viewArgs 2>$null
        if ($json) { $info = ($json | Out-String) | ConvertFrom-Json }
    } catch {
        $info = $null
    }

    # FAIL CLOSED: unable to read the PR means unable to prove it's safe to merge.
    if (-not $info) {
        Deny @"
Refused: couldn't read this PR's status from GitHub, so the merge gate can't verify it.

Check `gh auth status` and `gh pr view`. Do not route around this by merging in the web UI --
if the gate can't see the PR, nobody has confirmed the checks are green.
"@
    }

    $checks = @($info.statusCheckRollup)
    if ($checks.Count -eq 0) {
        Deny @"
Refused: PR #$($info.number) has no status checks reported yet.

Either CI hasn't started, or it isn't configured for this branch. Wait for it, then re-check
with `gh pr checks`. Merging unverified work defeats the point of the gate.
"@
    }

    foreach ($c in $checks) {
        $name = if ($c.name) { $c.name } else { $c.context }

        # A CheckRun still running has status != COMPLETED. Don't merge mid-flight.
        if ($c.status -and $c.status -ne 'COMPLETED') {
            Deny "Refused: check '$name' is still running ($($c.status)). Wait for it to finish, then merge."
        }

        # CheckRun uses .conclusion; the older StatusContext type uses .state.
        $state = if ($c.conclusion) { [string]$c.conclusion } else { [string]$c.state }

        if ($state -notin @('SUCCESS', 'NEUTRAL', 'SKIPPED')) {
            Deny @"
Refused: check '$name' is $state. Never merge red.

Fix the underlying failure and push again. If the check is wrong rather than the code, say so
explicitly and let the owner make the call -- don't merge around it.
"@
        }
    }
}

exit 0
