#requires -Version 5.1
<#
.SYNOPSIS
  Refresh the governance rules inside each agent's GLOBAL (user-level) instruction file,
  without touching anything else you have written there.

.DESCRIPTION
  The instructions in global/ are meant to be installed once into each agent's own
  user-level config, so any agent in any folder governs a new project automatically. The
  problem with "install once" is updating: the file usually also holds personal notes you do
  not want overwritten, and copying the whole file over would take them with it.

  So this writes the governance content between two markers:

      <!-- BEGIN repo-governance (managed) -->
      ...governance content, replaced wholesale each time...
      <!-- END repo-governance (managed) -->

  Everything outside those markers is never read, never moved and never changed. If the
  markers are not there yet, the block is APPENDED -- your existing file is kept.

  Run with -DryRun first. It backs up any file it modifies.

.EXAMPLE
  .\update-global-rules.ps1 -DryRun
.EXAMPLE
  .\update-global-rules.ps1

.PARAMETER DryRun  Report what would change and stop. Writes nothing.
.PARAMETER Agent   Limit to one agent: claude, codex or gemini. Default: all of them.
.PARAMETER NoBackup  Skip the .bak copy.
#>
[CmdletBinding()]
param(
    [switch]$DryRun,
    [ValidateSet('claude', 'codex', 'gemini', 'all')]
    [string]$Agent = 'all',
    [switch]$NoBackup
)

$ErrorActionPreference = 'Stop'
$kit = $PSScriptRoot

$BEGIN = '<!-- BEGIN repo-governance (managed) -->'
$END   = '<!-- END repo-governance (managed) -->'

# The governance content, assembled from the files in global/. Edit those, not this script.
$sources = @('global/new-project-bootstrap.md', 'global/server-rules.md')
$parts = @()
foreach ($s in $sources) {
    $path = Join-Path $kit $s
    if (-not (Test-Path $path)) { throw "Missing source: $s" }
    $parts += (Get-Content $path -Raw).TrimEnd()
}
$managed = ($BEGIN, '', ($parts -join "`n`n---`n`n"), '', $END) -join "`n"
# Normalise to LF. The source files may be CRLF, and comparing a CRLF block against an
# LF-normalised one made every run report a change -- the tool was never idempotent.
$managed = $managed -replace "`r`n", "`n"

$targets = [ordered]@{
    claude = Join-Path $HOME '.claude\CLAUDE.md'
    codex  = Join-Path $HOME '.codex\AGENTS.md'
    gemini = Join-Path $HOME '.gemini\GEMINI.md'
}
if ($Agent -ne 'all') { $targets = @{ $Agent = $targets[$Agent] } }

Write-Host ""
if ($DryRun) { Write-Host "DRY RUN -- nothing will be written" -ForegroundColor Yellow; Write-Host "" }

$changedAny = $false
foreach ($name in $targets.Keys) {
    $path = $targets[$name]
    $exists = Test-Path $path

    $existing = if ($exists) { Get-Content $path -Raw } else { '' }
    $hasMarkers = $existing.Contains($BEGIN) -and $existing.Contains($END)

    if ($hasMarkers) {
        $i = $existing.IndexOf($BEGIN)
        $j = $existing.IndexOf($END) + $END.Length
        if ($j -le $i) {
            Write-Host "  $name : markers are out of order in $path -- fix by hand, skipping." -ForegroundColor Red
            continue
        }
        $current = $existing.Substring($i, $j - $i)
        if (($current -replace "`r`n", "`n") -eq $managed) {
            Write-Host "  $name : already current" -ForegroundColor DarkGray
            continue
        }
        $updated = $existing.Substring(0, $i) + $managed + $existing.Substring($j)
        $action = 'update the managed block in'
        $keptChars = $existing.Length - $current.Length
    }
    else {
        $sep = if ($existing.TrimEnd()) { "`n`n" } else { '' }
        $updated = $existing.TrimEnd() + $sep + $managed + "`n"
        $action = if ($exists) { 'append the managed block to' } else { 'create' }
        $keptChars = $existing.TrimEnd().Length
    }

    $changedAny = $true
    Write-Host "  $name : $action $path" -ForegroundColor Green
    if ($keptChars -gt 0) {
        Write-Host "          keeping $keptChars characters of your own content outside the markers" -ForegroundColor DarkGray
    }

    if ($DryRun) { continue }

    $dir = Split-Path $path -Parent
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    if ($exists -and -not $NoBackup) {
        $bak = "$path.bak-" + (Get-Date -Format 'yyyyMMdd-HHmmss')
        Copy-Item $path $bak -Force
        Write-Host "          backup: $bak" -ForegroundColor DarkGray
    }
    Set-Content $path $updated -Encoding UTF8 -NoNewline
}

Write-Host ""
if (-not $changedAny) {
    Write-Host "Every agent's global rules are already current." -ForegroundColor Green
}
elseif ($DryRun) {
    Write-Host "Dry run: nothing written. Re-run without -DryRun to apply." -ForegroundColor Yellow
}
else {
    Write-Host "Done." -ForegroundColor Green
}

Write-Host ""
Write-Host "Cursor stores its user rules in the app, not in a file, so it can't be updated here." -ForegroundColor Cyan
Write-Host "To refresh it: Cursor -> Settings -> Rules -> User Rules, and paste the contents of" -ForegroundColor Cyan
Write-Host "  $(Join-Path $kit 'global\cursor-user-rules.txt')" -ForegroundColor Cyan
exit 0
