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
#   3. Review receipt     -- refuses UNREVIEWED substantive work, at `pr create` AND `pr merge`
#   4. Merge gate         -- refuses `gh pr merge` when checks aren't green, or --admin is used
#   5. Authority ceiling  -- refuses any PR merge that edits the rules themselves
#
# On a merge the order is: --admin, authority ceiling, review, then green CI. Authority comes
# first deliberately -- no amount of reviewing or green CI makes it the agent's call.
#
# FAIL DIRECTION: rules 1-3 fail OPEN at `pr create` (a parse or git error gets out of the
# way). Everything on the merge path fails CLOSED -- if it can't be determined, the merge is
# refused. Merging is the irreversible one; "I couldn't tell" must not mean "go ahead".
#
# HOSTS: `gh` (GitHub) and `fj` (Forgejo) are both handled. The receipt and authority rules
# are computed from local git, so they work on any host.
#
# Everything local depends on ONE assumption: that the branch checked out here is the PR being
# merged. `gh pr merge 42` breaks that assumption -- it merges PR 42 on the remote whatever is
# in front of you, so a receipt and a clean authority check for branch A would be used to wave
# through PR 42. On GitHub the gate closes this: it compares the PR's head commit with local
# HEAD and refuses a mismatch, and it re-runs the authority ceiling against the PR's own file
# list from the API.
#
# On Forgejo it cannot. `fj` has no equivalent query and V2 deliberately does not build a
# cross-host PR abstraction, so `fj pr merge <n>` run from a branch that is NOT that PR's is
# checked against the wrong branch. The mitigation is a rule, not code: merge the branch you
# have checked out. Same for the green-CI gate, which is GitHub-only.

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

# "Exempt" = prose that cannot change behaviour. A branch touching ONLY these is trivial and
# needs no independent review, and a doc commit added AFTER a review does not invalidate it.
# Governance files are never exempt, even though they are .md.
#
# Exemption is by FILE TYPE, never by folder. An earlier version of this exempted everything
# under docs/, which meant `docs/setup.sh` -- a shell script, executable, doing whatever it
# liked -- was classified as prose and reached a PR with no review at all. A folder name says
# nothing about what a file does. If a new prose format needs exempting, add its extension
# here; do not add a directory.
function Test-Exempt([string]$path) {
    if (Test-ReviewEvidence $path) { return $true }
    if (Test-Governance $path) { return $false }
    if ($path -match '\.(md|markdown|txt|rst|adoc)$') { return $true }
    if ($path -match '(^|/)(WORKLOG|CHANGELOG|CHANGES|NOTICE|LICENCE|LICENSE|AUTHORS|CONTRIBUTORS|README)$') { return $true }
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
# 3. Review receipt
# ---------------------------------------------------------------------------
# The rule: substantive work gets one independent review. The reviewer leaves findings; the
# primary agent records them in .claude/review/receipt.json.
#
# V2 changes two things about V1's version of this gate:
#
#   * TRIVIAL WORK IS EXEMPT. V1 demanded a receipt for every PR, including a README typo.
#     That taught the habit of running a costly reviewer purely to produce a file. A branch
#     touching only prose needs no receipt.
#
#   * THE RECEIPT TRACKS THE CODE, NOT THE COMMIT. V1 pinned the receipt to a SHA, so
#     appending a WORKLOG entry after the review invalidated it and forced a re-review that
#     could not possibly find anything new. V2 hashes the diff of the SUBSTANTIVE files only.
#     Change the code and the digest moves (review is stale, correctly). Add prose and it
#     doesn't (review still stands).
#
# Checked at BOTH `pr create` and `pr merge`. Checking only at create left a hole wide enough
# to drive the auto-commit Stop hook through: open a PR with a clean receipt, push three more
# commits of real code, merge. Nothing re-validated. Merge is the irreversible act, so it is
# the one that must not be able to happen unreviewed.
#
# HONEST LIMITATION, unchanged from V1: this forces the review to HAPPEN and to be recorded
# against specific code. It cannot force the agent to act on what the review said, and an
# agent determined to fake a receipt can. It is a tripwire, not a cage.

function Assert-Reviewed([string]$stage) {
    # $stage is 'create' or 'merge' -- it only changes the wording and the fail direction.
    $root = $null; $head = $null; $base = $null
    try {
        $root = (git rev-parse --show-toplevel 2>$null | Out-String).Trim()
        $head = (git rev-parse HEAD 2>$null | Out-String).Trim()
        $base = Get-BaseCommit
    } catch {
        $root = $null
    }

    if (-not ($root -and $head -and $base)) {
        # At create: stay out of the way (fail open) -- this may not even be a real repo.
        # At merge: refuse. Merging is irreversible; "I couldn't tell" must not mean "go on".
        if ($stage -eq 'merge') {
            Deny @"
Refused: couldn't work out what this branch changes, so the review gate can't check it.

Fetch the default branch (git fetch origin) and run this from the PR's own branch.
"@
        }
        return
    }

    $changed = @(git diff --name-only $base HEAD 2>$null |
                 ForEach-Object { $_.Trim() } |
                 Where-Object { $_ })

    if ($changed.Count -eq 0 -and $stage -eq 'merge') {
        # Nothing differs from the base, so whatever this PR contains, it is not here. Almost
        # always: `gh pr merge 5` run from main. The receipt and authority checks below would
        # both "pass" by looking at an empty diff, which is worse than useless.
        Deny @"
Refused: this branch has no changes against the default branch, so the PR being merged is
not what is checked out here -- and the review and authority checks would be inspecting
nothing at all.

Check out the PR's own branch first, then merge:
  git switch <the-pr-branch>
"@
    }

    $substantive = @($changed | Where-Object { -not (Test-Exempt $_) })
    if ($substantive.Count -eq 0) { return }   # prose only: no review required

    # Digest = SHA-256 of the diff restricted to substantive files.
    $diffText = (git diff $base HEAD -- $substantive 2>$null | Out-String)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($diffText)
        $digest = ([BitConverter]::ToString($sha256.ComputeHash($bytes)) -replace '-', '').ToLower()
    } finally { $sha256.Dispose() }

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
    $what = if ($stage -eq 'merge') { "merge" } else { "submit" }

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

If this branch really were prose-only, nothing here would have triggered -- so it isn't.
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
        $shown = if ($recordedDigest) { $recordedDigest.Substring(0, [Math]::Min(16, $recordedDigest.Length)) } else { '(none recorded)' }
        Deny @"
Refused: the review receipt does not match the code on this branch.

  reviewed code: $shown
  current code:  $($digest.Substring(0, 16))

The code changed after it was reviewed, so what you are about to $what has not been looked
at. Expected when you commit the reviewer's fixes -- re-run the reviewer on the current
branch and rewrite the receipt:
$template

(Prose-only commits -- WORKLOG, plain *.md, *.txt -- do NOT change this digest. If it moved,
real code moved.)
"@
    }
}

if ($cmdClean -match '\b(gh|fj)\s+pr\s+create\b') {
    Assert-Reviewed 'create'
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
    # Two sources, unioned, because each covers the other's blind spot:
    #   * LOCAL git -- works on any host, including Forgejo, which this gate does not speak.
    #   * the GitHub API -- describes the PR ITSELF, so it is right even when what is checked
    #     out locally is not what is being merged.
    # V1 used only the API (blind on Forgejo). An earlier draft of V2 used only local git,
    # which reads an empty diff when you merge by number from another branch -- and an empty
    # diff contains no governance files, so the ceiling silently passed.
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

    # --- 3b. The review must still hold at merge time ----------------------
    # Not only at `pr create`. Otherwise: open the PR with a clean receipt, push three more
    # commits of real code (the auto-commit Stop hook will do it for you), merge. Nothing
    # would re-check. Merge is the irreversible act, so it is the one that must not be able
    # to happen unreviewed. This also refuses a merge run from a branch that isn't the PR's,
    # where every local check would be inspecting an empty diff.
    Assert-Reviewed 'merge'

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
    $viewArgs += @('--json', 'statusCheckRollup,files,number,title,headRefOid,headRefName')

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

    # Is the PR being merged the branch that everything above just validated?
    #
    # `gh pr merge 42` merges PR 42 on the remote, whatever is checked out here. So every
    # local check -- the authority ceiling AND the review receipt -- may have inspected a
    # completely different branch and passed on it. A receipt that is perfectly valid for
    # branch A says nothing whatever about PR 42. Refuse unless they are the same commit.
    if ($prRef) {
        $prHead = [string]$info.headRefOid
        $localHead = (git rev-parse HEAD 2>$null | Out-String).Trim()
        if (-not $prHead -or -not $localHead -or $prHead -ne $localHead) {
            Deny @"
Refused: PR #$($info.number) is not what you have checked out, so nothing that was just
checked applies to it.

  PR #$($info.number) head: $(if ($prHead) { $prHead.Substring(0, [Math]::Min(12, $prHead.Length)) } else { '(unknown)' })  (branch '$($info.headRefName)')
  checked out here:  $(if ($localHead) { $localHead.Substring(0, [Math]::Min(12, $localHead.Length)) } else { '(unknown)' })

The review receipt and the authority check both read your LOCAL branch. Merging a different
PR by number would mean approving code that was never looked at. Check the PR out first:

  git switch $($info.headRefName)
  git pull
  gh pr merge --squash --delete-branch

(Without a number, `gh pr merge` targets the branch you are on, which is the branch that was
actually checked.)
"@
        }
    }

    # The authority ceiling again, now against the PR's OWN file list rather than whatever is
    # checked out. This is the half that is right when the two disagree.
    #
    # FAIL CLOSED on a missing field: `@($null)` yields a one-element array of $null, which
    # would walk this loop without finding anything and read as "no governance files" -- a
    # silent pass on the one check that must never fail open.
    if (-not $info.PSObject.Properties['files']) {
        Deny @"
Refused: GitHub returned no file list for PR #$($info.number), so the authority ceiling can't
tell whether this PR changes the rules.

That is not a "probably fine". Check `gh pr view $($info.number) --json files` and try again.
"@
    }
    $apiTouched = @()
    foreach ($f in @($info.files)) {
        $p = [string]$f.path
        if ($p -and (Test-Governance $p)) { $apiTouched += $p }
    }
    if ($apiTouched.Count -gt 0) {
        $list = ($apiTouched | Select-Object -Unique | ForEach-Object { "  - $_" }) -join "`n"
        Deny @"
Refused: PR #$($info.number) changes the rules that govern you, so it is the owner's to
merge -- not yours.

Governance files in this PR:
$list

This is the ceiling on your own authority: you may propose and argue for a rule change, but
you may not ratify one. Post the PR link and let the owner decide.
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
