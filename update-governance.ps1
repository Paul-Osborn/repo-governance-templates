#requires -Version 5.1
<#
.SYNOPSIS
  Safely update the governance MACHINE GATES in an existing governed project.

.DESCRIPTION
  You update this kit; then you run this to carry the newer gates into a project that was
  scaffolded from an older one.

  It only touches files this kit owns and that are still byte-for-byte a version the kit
  knows it shipped. Anything you customised is left exactly as it is and reported as a
  conflict for you to look at. It never touches your project's own content -- PRD.md,
  WORKLOG.md, your filled-in AGENTS.md or REPO_RULES.md, your .gitleaks.toml allowlist, your
  .claude/settings.json permissions, or any source file.

  Always run it with -DryRun first. Running it twice in a row is safe: the second run has
  nothing to do and says so.

.EXAMPLE
  .\update-governance.ps1 -Target C:\projects\my-app -DryRun
  # Shows exactly what would change. Changes nothing.

.EXAMPLE
  .\update-governance.ps1 -Target C:\projects\my-app
  # Applies the safe upgrades, backing up every file it replaces first.

.PARAMETER Target      The governed project to update (default: current folder).
.PARAMETER DryRun      Report what would change and stop. Writes nothing.
.PARAMETER BackupDir   Where to put backups (default: <target>\.governance-backup\<timestamp>).
.PARAMETER NoBackup    Skip backups. Only sensible if the target's work is already committed.
.PARAMETER RebuildManifest  Kit maintenance: regenerate governance-manifest.json from the
                            templates in this folder. Not for use on a project.
.PARAMETER Version     With -RebuildManifest, the version string to stamp.
#>
[CmdletBinding()]
param(
    [string]$Target = ".",
    [switch]$DryRun,
    [string]$BackupDir,
    [switch]$NoBackup,
    [switch]$RebuildManifest,
    [string]$Version
)

$ErrorActionPreference = 'Stop'
$kit = $PSScriptRoot
$manifestPath = Join-Path $kit 'governance-manifest.json'

# Line endings differ between a template (LF) and a working-tree checkout on Windows (often
# CRLF), and that difference is not a customisation. Normalise before hashing so an
# unmodified file is recognised as unmodified.
function Get-NormalizedHash([string]$path) {
    if (-not (Test-Path $path)) { return $null }
    $text = [System.IO.File]::ReadAllText($path) -replace "`r`n", "`n"
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($text)
        return ([BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-', '').ToLower()
    } finally { $sha.Dispose() }
}

# ---------------------------------------------------------------------------
# Kit maintenance: rebuild the manifest from the templates in this folder.
# ---------------------------------------------------------------------------
if ($RebuildManifest) {
    if (-not (Test-Path $manifestPath)) { throw "No governance-manifest.json to rebuild. Create it first." }
    $m = Get-Content $manifestPath -Raw | ConvertFrom-Json
    if ($Version) { $m.governanceVersion = $Version }
    $m.generated = (Get-Date -Format 'yyyy-MM-dd')

    foreach ($f in $m.files) {
        $src = Join-Path $kit $f.template
        if (-not (Test-Path $src)) { Write-Warning "manifest lists a missing template: $($f.template)"; continue }
        $new = Get-NormalizedHash $src
        if ($f.sha256 -and $f.sha256 -ne $new) {
            # The version that was current becomes a known older version, so a project still
            # carrying it is recognised as safely upgradeable rather than as customised.
            $known = @($f.knownHashes)
            if ($known -notcontains $f.sha256) { $f.knownHashes = @($known + $f.sha256 | Where-Object { $_ }) }
            Write-Host "  rolled: $($f.dest) -> knownHashes" -ForegroundColor DarkGray
        }
        $f.sha256 = $new
    }

    $m | ConvertTo-Json -Depth 6 | Set-Content $manifestPath -Encoding UTF8
    Write-Host "Manifest rebuilt at version $($m.governanceVersion)." -ForegroundColor Green
    exit 0
}

# ---------------------------------------------------------------------------
# Resolve and sanity-check the target.
# ---------------------------------------------------------------------------
if (-not (Test-Path $manifestPath)) { throw "governance-manifest.json not found next to this script." }
$manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json

$dest = if ([System.IO.Path]::IsPathRooted($Target)) { $Target } else { Join-Path (Get-Location) $Target }
$dest = [System.IO.Path]::GetFullPath($dest)
if (-not (Test-Path $dest -PathType Container)) { throw "Target folder not found: $dest" }

# Refuse to "update" something that was never governed -- that would scatter hook files into
# an unrelated folder.
$looksGoverned = @('AGENTS.md', 'lefthook.yml', '.claude', '.governance-version') |
    Where-Object { Test-Path (Join-Path $dest $_) }
if (-not $looksGoverned) {
    throw @"
$dest does not look like a governed project (no AGENTS.md, lefthook.yml, .claude/ or
.governance-version). If you meant to set up a NEW project, use new-governed-repo.ps1 instead.
"@
}

$installedVersion = $null
$versionFile = Join-Path $dest '.governance-version'
if (Test-Path $versionFile) { $installedVersion = (Get-Content $versionFile -Raw).Trim() }

Write-Host ""
Write-Host "Target:    $dest" -ForegroundColor Cyan
Write-Host "Installed: $(if ($installedVersion) { $installedVersion } else { 'unknown (pre-versioning)' })"
Write-Host "Available: $($manifest.governanceVersion)"
if ($DryRun) { Write-Host "Mode:      DRY RUN -- nothing will be written" -ForegroundColor Yellow }
Write-Host ""

# ---------------------------------------------------------------------------
# STAGE: work out every action before performing any of them.
# ---------------------------------------------------------------------------
$plan = @()
foreach ($f in $manifest.files) {
    $src = Join-Path $kit $f.template
    if (-not (Test-Path $src)) { Write-Warning "kit is missing a template it claims to own: $($f.template)"; continue }

    $targetFile = Join-Path $dest ($f.dest -replace '/', [System.IO.Path]::DirectorySeparatorChar)
    $current = Get-NormalizedHash $targetFile
    $shipped = Get-NormalizedHash $src

    $action = if ($null -eq $current)                     { 'ADD' }
              elseif ($current -eq $shipped)              { 'CURRENT' }
              elseif (@($f.knownHashes) -contains $current) { 'UPGRADE' }
              else                                        { 'CONFLICT' }

    $plan += [pscustomobject]@{
        Action = $action
        Dest   = $f.dest
        Source = $src
        Path   = $targetFile
        Note   = $f.note
    }
}

$adds      = @($plan | Where-Object Action -eq 'ADD')
$upgrades  = @($plan | Where-Object Action -eq 'UPGRADE')
$conflicts = @($plan | Where-Object Action -eq 'CONFLICT')
$current   = @($plan | Where-Object Action -eq 'CURRENT')

foreach ($p in ($plan | Sort-Object Action, Dest)) {
    $color = switch ($p.Action) {
        'ADD'      { 'Green' }
        'UPGRADE'  { 'Green' }
        'CONFLICT' { 'Yellow' }
        default    { 'DarkGray' }
    }
    Write-Host ("  {0,-9} {1}" -f $p.Action, $p.Dest) -ForegroundColor $color
}
Write-Host ""

if ($conflicts.Count -gt 0) {
    Write-Host "Left alone because they differ from anything this kit shipped:" -ForegroundColor Yellow
    foreach ($c in $conflicts) {
        Write-Host "  - $($c.Dest)" -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "  That normally means you edited them on purpose, so they are YOURS and this" -ForegroundColor Yellow
    Write-Host "  tool will not overwrite them. To take the new version of one, compare it with" -ForegroundColor Yellow
    Write-Host "  the template in:" -ForegroundColor Yellow
    Write-Host "    $kit" -ForegroundColor Yellow
    Write-Host "  and merge the parts you want by hand." -ForegroundColor Yellow
    Write-Host ""
}

$todo = $adds.Count + $upgrades.Count
if ($todo -eq 0) {
    if ($conflicts.Count -gt 0) {
        Write-Host "Nothing to update automatically. $($conflicts.Count) customised file(s) reported above." -ForegroundColor Cyan
    } else {
        Write-Host "Already current. Nothing to do." -ForegroundColor Green
    }
    # Still stamp the version if the files are all current but the marker is missing/old.
    if (-not $DryRun -and $conflicts.Count -eq 0 -and $installedVersion -ne $manifest.governanceVersion) {
        Set-Content $versionFile $manifest.governanceVersion -Encoding UTF8
        Write-Host "Recorded governance version $($manifest.governanceVersion) in .governance-version." -ForegroundColor Green
    }
    exit 0
}

Write-Host "$($adds.Count) to add, $($upgrades.Count) to upgrade." -ForegroundColor Cyan

if ($DryRun) {
    Write-Host ""
    Write-Host "Dry run: nothing was written. Re-run without -DryRun to apply." -ForegroundColor Yellow
    exit 0
}

# ---------------------------------------------------------------------------
# APPLY: back up first, then write. On any failure, put back what we replaced.
# ---------------------------------------------------------------------------
if (-not $BackupDir) {
    $BackupDir = Join-Path $dest ('.governance-backup\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
}

$restore = @()   # {Path, Backup} for rollback
try {
    foreach ($p in ($adds + $upgrades)) {
        if ($p.Action -eq 'UPGRADE' -and -not $NoBackup) {
            $rel = $p.Dest -replace '/', [System.IO.Path]::DirectorySeparatorChar
            $bak = Join-Path $BackupDir $rel
            $bakDir = Split-Path $bak -Parent
            if (-not (Test-Path $bakDir)) { New-Item -ItemType Directory -Path $bakDir -Force | Out-Null }
            Copy-Item $p.Path $bak -Force
            $restore += [pscustomobject]@{ Path = $p.Path; Backup = $bak }
        }

        $dir = Split-Path $p.Path -Parent
        if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Copy-Item $p.Source $p.Path -Force
        Write-Host "  $($p.Action.ToLower()): $($p.Dest)" -ForegroundColor Green
    }
} catch {
    Write-Host ""
    Write-Warning "Update failed part-way: $($_.Exception.Message)"
    foreach ($r in $restore) {
        try { Copy-Item $r.Backup $r.Path -Force; Write-Host "  restored: $($r.Path)" -ForegroundColor Yellow } catch { }
    }
    throw "Update rolled back. The project is as it was. Nothing is half-applied."
}

# Only claim the new generation when every managed file actually is on it.
if ($conflicts.Count -eq 0) {
    Set-Content $versionFile $manifest.governanceVersion -Encoding UTF8
    Write-Host ""
    Write-Host "Updated to governance version $($manifest.governanceVersion)." -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "Gates updated, but $($conflicts.Count) customised file(s) were left as they are," -ForegroundColor Yellow
    Write-Host "so .governance-version is unchanged. Merge those by hand, then re-run this." -ForegroundColor Yellow
}

if ($restore.Count -gt 0) {
    Write-Host "Backups of everything replaced: $BackupDir" -ForegroundColor Cyan
}

Write-Host ""
Write-Host "Next: check the changes into git on a branch, the same as any other change." -ForegroundColor Cyan
exit 0
