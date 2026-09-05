#requires -Version 5.1
<#
.SYNOPSIS
  Scaffold a new project with the repo-governance templates.

.DESCRIPTION
  Copies the template files into a target folder under their REAL names and
  locations (no manual renaming), initialises git, and installs the lefthook
  pre-commit checks. After it runs, open the folder in any agent (Claude Code,
  Codex, Cursor, Antigravity) and tell it what you're building — it reads
  AGENTS.md, fills in the <PLACEHOLDER>s, and makes the first commit per the rules.

.EXAMPLE
  .\new-governed-repo.ps1
  # Sets up the CURRENT folder.

.EXAMPLE
  .\new-governed-repo.ps1 -Target C:\projects\my-new-app -Name "My New App"
  # Creates/sets up that folder and fills the project name in.

.PARAMETER Target        Folder to set up (default: current folder). Created if missing.
.PARAMETER Name          Project name; fills every <PROJECT_NAME> placeholder.
.PARAMETER WithOptional  Also copy the optional/ reference templates.
.PARAMETER Force         Overwrite files that already exist in the target.
.PARAMETER NoGit         Skip 'git init'.
.PARAMETER NoLefthook    Skip 'lefthook install'.
#>
[CmdletBinding()]
param(
    [string]$Target = ".",
    [string]$Name,
    [switch]$WithOptional,
    [switch]$Force,
    [switch]$NoGit,
    [switch]$NoLefthook
)

$ErrorActionPreference = 'Stop'
$src = $PSScriptRoot

# template file (in this repo)  ->  destination path (relative to the target folder)
$map = [ordered]@{
    'AGENTS.template.md'            = 'AGENTS.md'
    'CLAUDE.template.md'            = 'CLAUDE.md'
    'GEMINI.template.md'           = 'GEMINI.md'
    'REPO_RULES.template.md'        = 'REPO_RULES.md'
    'PRD.template.md'              = 'PRD.md'             # project brief; agent fills it via interview
    'WORKLOG.template.md'          = 'WORKLOG.md'
    'SPEC.template.md'             = 'SPEC.template.md'   # stays a template; copy per feature
    'gitignore.template'          = '.gitignore'
    'gitattributes.template'       = '.gitattributes'    # keeps *.sh LF-only so the sh hooks run on Windows
    'lefthook.template.yml'        = 'lefthook.yml'
    'no-commit-on-main.template.sh' = 'scripts/hooks/no-commit-on-main.sh'  # branch guard (LF-only POSIX sh)
    'check-large-files.template.sh' = 'scripts/hooks/check-large-files.sh'  # large-file gate (LF-only POSIX sh)
    'check-lockfiles.template.sh'  = 'scripts/hooks/check-lockfiles.sh'    # lockfile sanity warning (LF-only POSIX sh)
    'gitleaks.template.toml'       = '.gitleaks.toml'
    'cursor-rules.template.mdc'    = '.cursor/rules/agents.mdc'
    'git-guard.template.ps1'       = '.claude/hooks/git-guard.ps1'
    'protect-paths.template.ps1'   = '.claude/hooks/protect-paths.ps1'
    'auto-commit.template.ps1'     = '.claude/hooks/auto-commit.ps1'
    'claude-settings.snippet.json' = '.claude/settings.json'
    'code-reviewer.template.md'    = '.claude/agents/code-reviewer.md'   # the one permitted subagent
}

# Resolve / create the target folder.
$dest = if ([System.IO.Path]::IsPathRooted($Target)) { $Target } else { Join-Path (Get-Location) $Target }
$dest = [System.IO.Path]::GetFullPath($dest)
if (-not (Test-Path $dest)) { New-Item -ItemType Directory -Path $dest -Force | Out-Null }

Write-Host "Scaffolding governance into: $dest" -ForegroundColor Cyan

foreach ($entry in $map.GetEnumerator()) {
    $from = Join-Path $src $entry.Key
    $to   = Join-Path $dest $entry.Value
    if (-not (Test-Path $from)) { Write-Warning "missing template: $($entry.Key)"; continue }
    if ((Test-Path $to) -and -not $Force) {
        Write-Host "  skip (exists): $($entry.Value)" -ForegroundColor DarkYellow
        continue
    }
    $toDir = Split-Path $to -Parent
    if ($toDir -and -not (Test-Path $toDir)) { New-Item -ItemType Directory -Path $toDir -Force | Out-Null }
    Copy-Item $from $to -Force
    Write-Host "  + $($entry.Value)" -ForegroundColor Green
}

# Record which generation of the kit this project got, so `update-governance.ps1` and a
# human can both answer "what rules is this repo on?" without inferring it from the files.
$manifestPath = Join-Path $src 'governance-manifest.json'
if (Test-Path $manifestPath) {
    $gv = (Get-Content $manifestPath -Raw | ConvertFrom-Json).governanceVersion
    Set-Content (Join-Path $dest '.governance-version') $gv -Encoding UTF8
    Write-Host "  + .governance-version ($gv)" -ForegroundColor Green
}

if ($WithOptional) {
    $optFrom = Join-Path $src 'optional'
    if (Test-Path $optFrom) {
        Copy-Item $optFrom (Join-Path $dest 'optional') -Recurse -Force
        Write-Host "  + optional/ (reference templates)" -ForegroundColor Green
    }
}

# Fill the project-name placeholder if one was given (other <PLACEHOLDER>s are left for the agent).
if ($Name) {
    Get-ChildItem $dest -Recurse -File -Include *.md, *.toml | ForEach-Object {
        $c = Get-Content $_.FullName -Raw
        if ($c -contains '<PROJECT_NAME>' -or $c.Contains('<PROJECT_NAME>')) {
            $c.Replace('<PROJECT_NAME>', $Name) | Set-Content $_.FullName -NoNewline
            Write-Host "  set <PROJECT_NAME> -> '$Name' in $($_.Name)" -ForegroundColor Green
        }
    }
}

# git init on 'main' (so every governed repo uses 'main' regardless of your git default).
# Default-branch commits are blocked by the guardrails — the agent branches first.
if (-not $NoGit -and -not (Test-Path (Join-Path $dest '.git'))) {
    if (Get-Command git -ErrorAction SilentlyContinue) {
        git -C $dest init -q -b main 2>$null
        if ($LASTEXITCODE -ne 0) { git -C $dest init -q; git -C $dest symbolic-ref HEAD refs/heads/main }
        Write-Host "  git initialised (branch: main)" -ForegroundColor Green
    }
    else {
        Write-Warning "git command not found. Skipping 'git init'."
    }
}

# Turn on the commit checks (branch guard + secret scan) for every agent and manual commits.
if (-not $NoLefthook -and -not $NoGit) {
    if (Get-Command lefthook -ErrorAction SilentlyContinue) {
        Push-Location $dest
        try { lefthook install | Out-Null; Write-Host "  lefthook installed (commit checks active)" -ForegroundColor Green }
        catch { Write-Warning "lefthook install failed: $($_.Exception.Message)" }
        finally { Pop-Location }
    }
    else {
        Write-Warning "lefthook not found. Install it (scoop install lefthook), then run 'lefthook install' in the project."
    }
}

Write-Host ""
Write-Host "Done. Next:" -ForegroundColor Cyan
Write-Host "  1. Open '$dest' in your agent (Claude Code, Codex, Cursor, or Antigravity)."
Write-Host '  2. Tell it: "Read AGENTS.md, then fill in the placeholders for <what you are building> and make the first commit."'
Write-Host "     The agent branches first, fills the <PLACEHOLDER>s, commits .gitignore, then the rest."
Write-Host ""
Write-Host "  Later, to take a newer version of the gates into this project:" -ForegroundColor Cyan
Write-Host "     & \"$env:REPO_GOVERNANCE_HOME\\update-governance.ps1\" -Target '$dest' -DryRun"
