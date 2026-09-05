#requires -Version 5.1
<#
.SYNOPSIS
  Check, and safely fast-forward, a branch across every remote this repo has.

.DESCRIPTION
  A project can live in more than one place -- typically a self-hosted server that is the
  source of truth, plus a mirror on GitHub. This makes them agree, without you pushing twice
  and without anything being overwritten.

  What it will do:
    * report where every copy stands, in plain language;
    * fast-forward any copy that is simply behind (nothing is lost by a fast-forward);
    * create the branch on a remote that doesn't have it yet.

  What it will NEVER do:
    * force-push. Equality obtained by discarding someone's commits is not synchronisation.
    * make a commit. Synchronising is not a change to the project.
    * pick a side when the copies have genuinely diverged. It stops and tells you.

  Run it with -DryRun first if you want to see the plan. Running it when everything already
  agrees is a clean no-op.

.EXAMPLE
  .\sync-remotes.ps1 -DryRun
  # Are all copies of the default branch in the same place?

.EXAMPLE
  .\sync-remotes.ps1
  # Bring every copy of the default branch into line.

.EXAMPLE
  .\sync-remotes.ps1 -Branch feat/new-export
  # Push the current piece of work to every remote.

.PARAMETER Repo    The repository (default: current folder).
.PARAMETER Branch  Branch to synchronise (default: the repo's default branch).
.PARAMETER DryRun  Report only. Pushes nothing.
#>
[CmdletBinding()]
param(
    [string]$Repo = ".",
    [string]$Branch,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$root = if ([System.IO.Path]::IsPathRooted($Repo)) { $Repo } else { Join-Path (Get-Location) $Repo }
$root = [System.IO.Path]::GetFullPath($root)
if (-not (Test-Path (Join-Path $root '.git'))) { throw "Not a git repository: $root" }

# git writes progress and hints to stderr even when nothing is wrong. Under
# $ErrorActionPreference = 'Stop', PowerShell 5.1 turns a redirected native stderr line into
# a terminating NativeCommandError -- so a perfectly successful `git fetch` would blow up.
# Every call site checks $LASTEXITCODE explicitly instead.
function Git {
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { & git -C $root @args } finally { $ErrorActionPreference = $prev }
}

function Rev([string]$ref) {
    $r = (Git rev-parse --verify --quiet "$ref^{commit}" 2>$null | Out-String).Trim()
    if ($r) { return $r } else { return $null }
}

# Is $a an ancestor of $b? (i.e. b can fast-forward to include a)
function Test-Ancestor([string]$a, [string]$b) {
    Git merge-base --is-ancestor $a $b 2>$null | Out-Null
    return ($LASTEXITCODE -eq 0)
}

$remotes = @(Git remote | ForEach-Object { $_.Trim() } | Where-Object { $_ })
if ($remotes.Count -eq 0) {
    Write-Host "No remotes configured. Nothing to synchronise." -ForegroundColor Yellow
    exit 0
}

# The authoritative copy: 'origin' by convention, else the only/first remote.
$authoritative = if ($remotes -contains 'origin') { 'origin' } else { $remotes[0] }

if (-not $Branch) {
    $head = (Git symbolic-ref --short -q "refs/remotes/$authoritative/HEAD" 2>$null | Out-String).Trim()
    if ($head) { $Branch = $head -replace "^$([regex]::Escape($authoritative))/", '' }
    if (-not $Branch) { $Branch = if (Rev "refs/remotes/$authoritative/main") { 'main' } else { 'master' } }
}

Write-Host ""
Write-Host "Repository:    $root" -ForegroundColor Cyan
Write-Host "Branch:        $Branch"
Write-Host "Authoritative: $authoritative"
Write-Host "Mirrors:       $((@($remotes | Where-Object { $_ -ne $authoritative }) -join ', '))"
if ($DryRun) { Write-Host "Mode:          DRY RUN -- nothing will be pushed" -ForegroundColor Yellow }
Write-Host ""

Write-Host "Fetching..." -ForegroundColor DarkGray
$unreachable = @()
foreach ($r in $remotes) {
    Git fetch $r --prune --quiet 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { $unreachable += $r }
}
if ($unreachable.Count -gt 0) {
    throw @"
Couldn't reach: $($unreachable -join ', ')

Nothing was changed. Until every copy can be read, there is no way to tell whether they
agree, and guessing is exactly what this tool exists to avoid. Check the network / your
connection to the server, then run this again.
"@
}

# ---------------------------------------------------------------------------
# Where does every copy stand?
# ---------------------------------------------------------------------------
$copies = @()
$copies += [pscustomobject]@{ Name = 'local'; Ref = "refs/heads/$Branch"; Sha = (Rev "refs/heads/$Branch"); IsLocal = $true; Remote = $null }
foreach ($r in $remotes) {
    $copies += [pscustomobject]@{ Name = $r; Ref = "refs/remotes/$r/$Branch"; Sha = (Rev "refs/remotes/$r/$Branch"); IsLocal = $false; Remote = $r }
}

$present = @($copies | Where-Object { $_.Sha })
if ($present.Count -eq 0) { throw "Branch '$Branch' does not exist locally or on any remote." }

# ---------------------------------------------------------------------------
# Divergence check: every pair must be on one line of history.
# ---------------------------------------------------------------------------
$diverged = @()
for ($i = 0; $i -lt $present.Count; $i++) {
    for ($j = $i + 1; $j -lt $present.Count; $j++) {
        $a = $present[$i]; $b = $present[$j]
        if ($a.Sha -eq $b.Sha) { continue }
        if (-not (Test-Ancestor $a.Sha $b.Sha) -and -not (Test-Ancestor $b.Sha $a.Sha)) {
            $diverged += "$($a.Name) and $($b.Name)"
        }
    }
}

foreach ($c in $copies) {
    $label = if ($c.Sha) { $c.Sha.Substring(0, 8) } else { '(branch not there)' }
    Write-Host ("  {0,-12} {1}" -f $c.Name, $label)
}
Write-Host ""

if ($diverged.Count -gt 0) {
    Write-Host "REFUSED -- these copies have genuinely gone their separate ways:" -ForegroundColor Red
    foreach ($d in ($diverged | Select-Object -Unique)) { Write-Host "  $d" -ForegroundColor Red }
    Write-Host ""
    Write-Host @"
Each of them has work the other does not. There is no safe automatic answer: making them
match would mean throwing one side's commits away, and this tool will not do that.

Nothing has been changed. To see what each side has that the other doesn't:
  git log --oneline $authoritative/$Branch ^<other-remote>/$Branch

Then decide deliberately -- merge the two, or rebase one onto the other -- and say which.
"@ -ForegroundColor Red
    exit 1
}

# One line of history: the newest tip is the one all the others are ancestors of.
$newest = $present[0]
foreach ($c in $present) { if (Test-Ancestor $newest.Sha $c.Sha) { $newest = $c } }

Write-Host "Newest: $($newest.Name) at $($newest.Sha.Substring(0,8))" -ForegroundColor Cyan
if ($newest.Name -ne $authoritative -and $newest.Name -ne 'local') {
    Write-Host "Note: the authoritative copy ($authoritative) is behind the mirror '$($newest.Name)'." -ForegroundColor Yellow
    Write-Host "      Fast-forwarding it loses nothing, so that is what will happen." -ForegroundColor Yellow
}
Write-Host ""

# ---------------------------------------------------------------------------
# Plan
# ---------------------------------------------------------------------------
$behind = @($copies | Where-Object { $_.Sha -ne $newest.Sha })
if ($behind.Count -eq 0) {
    Write-Host "All copies of '$Branch' are already at the same commit. Nothing to do." -ForegroundColor Green
    exit 0
}

foreach ($c in $behind) {
    $what = if ($c.Sha) { 'fast-forward' } else { 'create' }
    Write-Host "  $what $($c.Name)" -ForegroundColor Green
}
Write-Host ""

if ($DryRun) {
    Write-Host "Dry run: nothing pushed. Re-run without -DryRun to apply." -ForegroundColor Yellow
    exit 0
}

# ---------------------------------------------------------------------------
# Apply. Plain pushes only -- git itself refuses a non-fast-forward, which is a second
# safety net underneath the divergence check above.
# ---------------------------------------------------------------------------
$failed = @()
foreach ($c in $behind) {
    if ($c.IsLocal) {
        $currentBranch = (Git rev-parse --abbrev-ref HEAD | Out-String).Trim()
        if ($currentBranch -eq $Branch) {
            $dirty = (Git status --porcelain | Out-String).Trim()
            if ($dirty) {
                Write-Host "  skipped local: '$Branch' is checked out and has uncommitted changes." -ForegroundColor Yellow
                Write-Host "                 Commit or stash them, then run this again." -ForegroundColor Yellow
                continue
            }
            Git merge --ff-only $newest.Sha --quiet 2>$null | Out-Null
        } else {
            # Not checked out: move the ref directly. Safe, and leaves the working tree alone.
            Git update-ref "refs/heads/$Branch" $newest.Sha 2>$null | Out-Null
        }
        if ($LASTEXITCODE -eq 0) { Write-Host "  local updated" -ForegroundColor Green }
        else { $failed += 'local' }
        continue
    }

    Git push $c.Remote "$($newest.Sha):refs/heads/$Branch" 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { Write-Host "  $($c.Remote) updated" -ForegroundColor Green }
    else { $failed += $c.Remote }
}

Write-Host ""
if ($failed.Count -gt 0) {
    Write-Host "Failed to update: $($failed -join ', ')" -ForegroundColor Red
    Write-Host "Nothing was forced. Run this again once you know why, and the rest stays as it is." -ForegroundColor Red
    exit 1
}

Write-Host "All copies of '$Branch' now at $($newest.Sha.Substring(0,8))." -ForegroundColor Green
exit 0
