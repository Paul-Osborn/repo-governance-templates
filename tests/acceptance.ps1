#requires -Version 5.1
<#
.SYNOPSIS
  Acceptance tests for the governance kit. Proves the gates actually fire.

.DESCRIPTION
  Everything runs in disposable repositories under a temp folder. This script never touches
  the kit repository it lives in, and never installs gates into it.

  Needs on PATH: git, lefthook, gitleaks, tar.

.EXAMPLE
  .\tests\acceptance.ps1
.EXAMPLE
  .\tests\acceptance.ps1 -Keep      # leave the temp repos behind for inspection
#>
[CmdletBinding()]
param(
    [switch]$Keep,
    [string]$WorkDir
)

$ErrorActionPreference = 'Stop'
$kit = Split-Path $PSScriptRoot -Parent

# --- tiny harness ----------------------------------------------------------
$script:pass = 0; $script:fail = 0; $script:failures = @()

function Section($name) { Write-Host ""; Write-Host "== $name" -ForegroundColor Cyan }
function Check($name, [bool]$ok, $detail) {
    if ($ok) { $script:pass++; Write-Host "  PASS  $name" -ForegroundColor Green }
    else {
        $script:fail++; $script:failures += $name
        Write-Host "  FAIL  $name" -ForegroundColor Red
        if ($detail) { Write-Host "        $(($detail | Out-String).Trim())" -ForegroundColor DarkRed }
    }
}

# git writes to stderr on success; under EAP=Stop that becomes a terminating error in 5.1.
function RunGit {
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { & git @args 2>&1 | Out-String } finally { $ErrorActionPreference = $prev }
}

# Run git-guard against a Bash-tool payload and return the DENIAL REASON (or $null if it
# allowed). Tests assert on the reason, never merely on "something was denied" -- in a
# disposable repo a merge can be refused for an unrelated reason (no GitHub PR to read),
# which would let an authority test pass without the authority rule doing anything.
# Let ConvertTo-Json do the escaping. Hand-rolling it got the backslashes wrong and silently
# broke every multi-segment Windows path pattern -- the tests then reported the hook as
# permissive when the hook was fine.
function HookPayload([string]$tool, $inputObj) {
    return (@{ tool_name = $tool; tool_input = $inputObj } | ConvertTo-Json -Compress -Depth 5)
}
function HookDecision([string]$payload, [string]$hookPath) {
    $out = ($payload | powershell -NoProfile -ExecutionPolicy Bypass -File $hookPath) | Out-String
    if (-not $out.Trim()) { return $null }
    try { $o = ($out | ConvertFrom-Json).hookSpecificOutput } catch { return $null }
    if (-not $o -or $o.permissionDecision -ne 'deny') { return $null }
    # Read it back through the JSON parser, so assertions match the text a human would see
    # rather than escape-sequence soup.
    return [string]$o.permissionDecisionReason
}
function GuardReason([string]$command, [string]$hookPath) {
    return (HookDecision (HookPayload 'Bash' @{ command = $command }) $hookPath)
}
function GuardDenies([string]$command, [string]$hookPath) { return ($null -ne (GuardReason $command $hookPath)) }

function ProtectDenies([string]$file, [string]$hookPath) {
    return ($null -ne (HookDecision (HookPayload 'Edit' @{ file_path = $file }) $hookPath))
}

# Ask git-guard itself for the digest it expects, exactly as an agent would read it out of
# the refusal. Deliberately NOT recomputed here: duplicating the classification logic in the
# test would let the test agree with a bug.
function Write-Receipt($repo, $guardPath, $verdict = 'PASS') {
    $reason = GuardReason 'gh pr create --title x' $guardPath
    if (-not $reason) { throw "expected git-guard to refuse and print a digest, but it allowed the PR" }
    if ($reason -notmatch 'codeDigest[^0-9a-f]{0,24}([0-9a-f]{64})') { throw "no digest in refusal: $reason" }
    $digest = $Matches[1]
    New-Item -ItemType Directory -Force -Path (Join-Path $repo '.claude/review') | Out-Null
    @{ sha = (RunGit -C $repo rev-parse HEAD).Trim(); codeDigest = $digest; reviewer = 'code-reviewer'
       verdict = $verdict; reviewedAt = '2026-09-05T00:00:00Z'; findings = 'none' } |
        ConvertTo-Json | Set-Content (Join-Path $repo '.claude/review/receipt.json')
    return $digest
}

# --- workspace -------------------------------------------------------------
if (-not $WorkDir) { $WorkDir = Join-Path $env:TEMP ("gov-accept-" + (Get-Date -Format 'yyyyMMdd-HHmmss')) }
New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
Write-Host "Workspace: $WorkDir" -ForegroundColor DarkGray
Write-Host "Kit:       $kit" -ForegroundColor DarkGray

foreach ($tool in @('git', 'lefthook', 'gitleaks', 'tar')) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { throw "$tool is not on PATH; these tests need it." }
}

$startDir = Get-Location
try {

# ===========================================================================
Section 'A. SCAFFOLD'
# ===========================================================================
$A = Join-Path $WorkDir 'A-scaffold'
& (Join-Path $kit 'new-governed-repo.ps1') -Target $A -Name 'Test Project' *>$null
Check 'A1 scaffold completes' (Test-Path $A)

$expected = @(
    'AGENTS.md', 'CLAUDE.md', 'GEMINI.md', 'REPO_RULES.md', 'PRD.md', 'WORKLOG.md',
    '.gitignore', '.gitattributes', 'lefthook.yml', '.gitleaks.toml', '.governance-version',
    'scripts/hooks/no-commit-on-main.sh', 'scripts/hooks/check-large-files.sh',
    'scripts/hooks/check-lockfiles.sh',
    '.claude/hooks/git-guard.ps1', '.claude/hooks/protect-paths.ps1',
    '.claude/hooks/auto-commit.ps1', '.claude/agents/code-reviewer.md',
    '.claude/settings.json', '.cursor/rules/agents.mdc'
)
$missing = @($expected | Where-Object { -not (Test-Path (Join-Path $A $_)) })
Check 'A2 every expected file is in place' ($missing.Count -eq 0) "missing: $($missing -join ', ')"
Check 'A3 project name filled in' ((Get-Content (Join-Path $A 'AGENTS.md') -Raw) -match 'Test Project')
Check 'A4 git initialised on main' ((RunGit -C $A symbolic-ref --short -q HEAD).Trim() -eq 'main')

$kitVersion = (Get-Content (Join-Path $kit 'governance-manifest.json') -Raw | ConvertFrom-Json).governanceVersion
$gv = (Get-Content (Join-Path $A '.governance-version') -Raw).Trim()
Check "A5 governance version stamped ($gv)" ($gv -eq $kitVersion)

Set-Location $A
lefthook install *>$null
Set-Location $startDir
Check 'A6 lefthook pre-commit hook installed' (Test-Path (Join-Path $A '.git/hooks/pre-commit'))

$guard   = Join-Path $A '.claude/hooks/git-guard.ps1'
$protect = Join-Path $A '.claude/hooks/protect-paths.ps1'

# ===========================================================================
Section 'B. MAIN BRANCH GUARD'
# ===========================================================================
Set-Location $A
Set-Content 'first.txt' 'hello'
RunGit add -A | Out-Null
$onMain = RunGit commit -m 'chore: should be refused'
Check 'B1 lefthook refuses a commit on main' ($LASTEXITCODE -ne 0) $onMain
Check 'B2 and says to branch first' ($onMain -match 'Branch first') $onMain

# git-guard's branch guard reads the branch of ITS OWN cwd, so this must run from the repo.
$r = GuardReason 'git commit -m x' $guard
Check 'B3 git-guard refuses a commit on main, for that reason' ($r -match "you are on 'main'") $r
$r = GuardReason 'git push' $guard
Check 'B4 git-guard refuses a push on main' ($r -match "you are on 'main'") $r

RunGit switch -q -c feat/acceptance | Out-Null
$onBranch = RunGit commit -m 'chore: baseline'
Check 'B5 commit on a feature branch succeeds' ($LASTEXITCODE -eq 0) $onBranch

# main was unborn (its first commit was correctly refused). Establish it at the baseline so
# later branches have a base to diff against, as they would after a real first merge.
RunGit branch -f main HEAD | Out-Null
Check 'B6 main now exists as a base' ((RunGit rev-parse --verify --quiet main).Trim().Length -gt 0)

Check 'B7 git-guard allows git log --grep=commit' (-not (GuardDenies 'git log --grep=commit' $guard))
Check 'B8 git-guard allows git stash push'        (-not (GuardDenies 'git stash push -m wip' $guard))
Set-Location $startDir

# ===========================================================================
Section 'C. SECRET GATE'
# ===========================================================================
# Assembled at runtime, so no credential-shaped literal is ever committed to the kit and the
# kit's own secret scan stays clean. A GitHub-token shape is used deliberately: gitleaks
# 8.30's default ruleset no longer flags a bare AWS access key ID, so an AKIA fixture would
# make this test pass or fail for reasons that have nothing to do with the gate being wired
# up. See the note at the bottom of gitleaks.template.toml.
$rand36 = -join ((1..36) | ForEach-Object { '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ'[(Get-Random -Maximum 62)] })
$fakeToken = 'ghp_' + $rand36
Set-Location $A
Set-Content 'config.txt' ("GITHUB_TOKEN=" + $fakeToken)
RunGit add -A | Out-Null
$secretOut = RunGit commit -m 'chore: fake credential'
Check 'C1 a commit containing a credential is refused' ($LASTEXITCODE -ne 0) $secretOut
Check 'C2 the secret scan is what refused it' ($secretOut -match '(?i)leaks found|gitleaks') $secretOut
Check 'C3 the value is redacted, not echoed back' (-not ($secretOut -match [regex]::Escape($fakeToken))) 'the raw token appeared in the output'
RunGit reset -q HEAD . | Out-Null
Remove-Item 'config.txt' -Force

Set-Content 'ordinary.txt' 'just some ordinary project text, nothing secret here'
RunGit add -A | Out-Null
$normalOut = RunGit commit -m 'chore: ordinary content'
Check 'C4 ordinary content commits fine' ($LASTEXITCODE -eq 0) $normalOut
Set-Location $startDir

# ===========================================================================
Section 'D. LARGE-FILE GATE'
# ===========================================================================
Set-Location $A
# Compressible content on purpose: `git cat-file -s` reports the real content size, and
# repeated bytes cannot be mistaken for a high-entropy secret by the scanner running
# alongside. That keeps this test about the size gate and nothing else.
[System.IO.File]::WriteAllText((Join-Path $A 'big.bin'), ('A' * (3 * 1024 * 1024)))
RunGit add -A | Out-Null
$bigOut = RunGit commit -m 'chore: oversized file'
Check 'D1 an oversized new file is refused' ($LASTEXITCODE -ne 0) $bigOut
Check 'D2 the size gate is what refused it' ($bigOut -match 'over the 2048 KB limit') $bigOut
Check 'D3 the refusal names the file'       ($bigOut -match 'big\.bin') $bigOut
Check 'D4 the refusal says what to do'      ($bigOut -match 'gitignore|Git LFS') $bigOut
RunGit reset -q HEAD . | Out-Null
Remove-Item 'big.bin' -Force

Set-Content 'small.txt' ('x' * 2000)
RunGit add -A | Out-Null
$smallOut = RunGit commit -m 'chore: normal sized file'
Check 'D5 a normal-sized file is accepted' ($LASTEXITCODE -eq 0) $smallOut

RunGit config governance.maxFileKB 1 | Out-Null
Set-Content 'medium.txt' ('y' * 40000)
RunGit add -A | Out-Null
$medOut = RunGit commit -m 'chore: over the tightened limit'
Check 'D6 a configured tighter limit is honoured' ($LASTEXITCODE -ne 0) $medOut
Check 'D7 and the message quotes that limit' ($medOut -match 'over the 1 KB limit') $medOut
RunGit reset -q HEAD . | Out-Null
Remove-Item 'medium.txt' -Force
RunGit config --unset governance.maxFileKB | Out-Null
Set-Location $startDir

# ===========================================================================
Section 'E. BYPASS PROTECTION'
# ===========================================================================
Set-Location $A
$r = GuardReason 'git commit --no-verify -m x' $guard
Check 'E1 --no-verify is refused for skipping the checks' ($r -match 'no-verify skips the pre-commit checks') $r
$r = GuardReason 'git commit -anm "msg"' $guard
Check 'E2 a bundled -n is caught too' ($r -match 'no-verify skips the pre-commit checks') $r
$r = GuardReason 'echo x >> AGENTS.md' $guard
Check 'E3 redirection at a rules file is refused' ($r -match 'shell redirection') $r
$r = GuardReason 'echo x > scripts/hooks/no-commit-on-main.sh' $guard
Check 'E4 redirection at a gate script is refused' ($r -match 'shell redirection') $r
Check 'E5 a commit MESSAGE mentioning --no-verify is still allowed' `
      (-not (GuardDenies 'git commit -m "docs: explain why --no-verify is blocked"' $guard))
Check 'E6 an ordinary redirect is allowed' (-not (GuardDenies 'echo hi > notes.txt' $guard))
Set-Location $startDir

# ===========================================================================
Section 'F. AUTHORITY'
# ===========================================================================
Set-Location $A
$r = GuardReason 'gh pr merge 1 --squash --admin' $guard
Check 'F1 --admin is refused as a bypass' ($r -match '--admin bypasses the checks') $r

# Negative control FIRST: on a branch with no governance change, the merge is still refused
# in this disposable repo -- but for the CI-status reason, NOT the authority reason. Without
# this, every authority assertion below could pass without the authority rule doing anything.
RunGit switch -q main | Out-Null
RunGit switch -q -c chore/ordinary-change | Out-Null
Set-Content 'ordinary-code.py' 'x = 1'
RunGit add -A | Out-Null; RunGit commit -q -m 'chore: ordinary' | Out-Null
$rOrdinary = GuardReason 'gh pr merge 1 --squash' $guard
Check 'F2 a non-governance merge is NOT refused on authority grounds' `
      ($rOrdinary -notmatch 'changes the rules that govern you') $rOrdinary
Check 'F3 (it is refused for the unrelated CI-status reason instead)' `
      ($rOrdinary -match "couldn.t read this PR.s status") $rOrdinary

RunGit switch -q main | Out-Null
RunGit switch -q -c chore/gov-change | Out-Null
Add-Content 'AGENTS.md' "`n- an extra rule the agent gave itself"
RunGit add -A | Out-Null; RunGit commit -q -m 'docs: widen my own authority' | Out-Null
$rGov = GuardReason 'gh pr merge 1 --squash' $guard
Check 'F4 a merge touching AGENTS.md is refused ON AUTHORITY GROUNDS' `
      ($rGov -match 'changes the rules that govern you') $rGov
Check 'F5 and it names the offending file'   ($rGov -match 'AGENTS\.md') $rGov
Check 'F6 and it says the owner must decide' ($rGov -match "owner.s to merge") $rGov

$rFj = GuardReason 'fj pr merge 1 --squash' $guard
Check 'F7 the same authority rule applies on Forgejo' ($rFj -match 'changes the rules that govern you') $rFj

# A gate script is authority too, not just the .md rule files.
RunGit switch -q main | Out-Null
RunGit switch -q -c chore/gate-change | Out-Null
Add-Content 'scripts/hooks/check-large-files.sh' "`n# tampered"
RunGit add -A | Out-Null; RunGit commit -q -m 'chore: tweak a gate' | Out-Null
$rGate = GuardReason 'gh pr merge 1 --squash' $guard
Check 'F8 editing a GATE is also an authority change' ($rGate -match 'changes the rules that govern you') $rGate
Check 'F9 and it names the gate'                      ($rGate -match 'check-large-files\.sh') $rGate
RunGit switch -q main | Out-Null
Set-Location $startDir

Check 'F10 protect-paths denies editing settings.json' (ProtectDenies (Join-Path $A '.claude/settings.json') $protect)
Check 'F11 protect-paths denies editing a gate script' (ProtectDenies (Join-Path $A 'scripts/hooks/check-large-files.sh') $protect)
Check 'F12 protect-paths denies editing lefthook.yml'  (ProtectDenies (Join-Path $A 'lefthook.yml') $protect)
Check 'F13 protect-paths denies editing the reviewer'  (ProtectDenies (Join-Path $A '.claude/agents/code-reviewer.md') $protect)
Check 'F14 protect-paths allows an ordinary source file' (-not (ProtectDenies (Join-Path $A 'src/app.py') $protect))

# ===========================================================================
Section 'G. REVIEWER'
# ===========================================================================
$rev = Get-Content (Join-Path $A '.claude/agents/code-reviewer.md') -Raw
Check 'G1 reviewer is installed in a scaffolded project' ($rev.Length -gt 0)
Check 'G2 reviewer pinned to Sonnet 5'  ($rev -match '(?m)^model:\s*claude-sonnet-5\s*$') $rev
Check 'G3 reviewer set to high effort'  ($rev -match '(?m)^effort:\s*high\s*$')
Check 'G4 reviewer cannot write files'  ($rev -match '(?m)^disallowedTools:.*\bWrite\b' -and $rev -match '(?m)^disallowedTools:.*\bEdit\b')
Check 'G5 reviewer cannot spawn agents' ($rev -match '(?m)^disallowedTools:.*\bTask\b')
Check 'G6 reviewer is told to review once, at the end' ($rev -match '(?i)ONCE')

Set-Location $A
RunGit switch -q main | Out-Null
RunGit switch -q -c docs/prose-only | Out-Null
Add-Content 'NOTES.md' 'a purely prose change'
RunGit add -A | Out-Null; RunGit commit -q -m 'docs: prose' | Out-Null
Check 'G7 a prose-only branch needs no reviewer at all' (-not (GuardDenies 'gh pr create --title x' $guard))

RunGit switch -q main | Out-Null
RunGit switch -q -c feat/real-code | Out-Null
Set-Content 'module.py' "def add(a, b):`n    return a + b`n"
RunGit add -A | Out-Null; RunGit commit -q -m 'feat: add' | Out-Null
$r = GuardReason 'gh pr create --title x' $guard
Check 'G8 a code change with no receipt is refused' ($r -match 'no review receipt') $r
Check 'G9 and the refusal names the substantive file' ($r -match 'module\.py') $r

$d1 = Write-Receipt $A $guard
Check 'G10 a valid receipt lets the PR open' (-not (GuardDenies 'gh pr create --title x' $guard))

RunGit add -A | Out-Null; RunGit commit -q -m 'chore: record the review' | Out-Null
Check 'G11 committing the receipt does not invalidate it' (-not (GuardDenies 'gh pr create --title x' $guard))

Add-Content 'WORKLOG.md' "`n## 2026-09-05 - a note"
RunGit add -A | Out-Null; RunGit commit -q -m 'docs: worklog' | Out-Null
Check 'G12 prose committed after review keeps the review valid' (-not (GuardDenies 'gh pr create --title x' $guard))

Add-Content 'module.py' "`ndef subtract(a, b):`n    return a - b`n"
RunGit add -A | Out-Null; RunGit commit -q -m 'feat: subtract' | Out-Null
$r = GuardReason 'gh pr create --title x' $guard
Check 'G13 code committed after review DOES invalidate it' ($r -match 'does not match the code') $r

$d2 = Write-Receipt $A $guard
Check 'G14 the digest actually moved with the code' ($d1 -ne $d2) "$d1 / $d2"
Check 'G15 re-reviewing restores validity' (-not (GuardDenies 'gh pr create --title x' $guard))

# Editing a governance file is substantive even though it is markdown.
RunGit add -A | Out-Null; RunGit commit -q -m 'chore: re-review' | Out-Null
Add-Content 'AGENTS.md' "`n- a rule change slipped in after review"
RunGit add -A | Out-Null; RunGit commit -q -m 'docs: rule tweak' | Out-Null
$r = GuardReason 'gh pr create --title x' $guard
Check 'G16 a rules-file edit is NOT treated as exempt prose' ($r -match 'does not match the code') $r
Write-Receipt $A $guard | Out-Null
RunGit add -A | Out-Null; RunGit commit -q -m 'chore: re-review again' | Out-Null

$rc = Get-Content (Join-Path $A '.claude/review/receipt.json') -Raw | ConvertFrom-Json
$rc.verdict = 'looks fine to me'
$rc | ConvertTo-Json | Set-Content (Join-Path $A '.claude/review/receipt.json')
$r = GuardReason 'gh pr create --title x' $guard
Check 'G17 a receipt with no real verdict is refused' ($r -match 'no usable verdict') $r

Set-Content (Join-Path $A '.claude/review/receipt.json') 'not json at all'
$r = GuardReason 'gh pr create --title x' $guard
Check 'G18 a corrupt receipt is refused' ($r -match 'not valid JSON') $r
RunGit switch -q main | Out-Null
RunGit checkout -q -- . 2>&1 | Out-Null
Set-Location $startDir

# ===========================================================================
Section 'H. LOCKFILES'
# ===========================================================================
Check 'H1 protect-paths no longer blanket-blocks package-lock.json' `
      (-not (ProtectDenies (Join-Path $A 'package-lock.json') $protect))
Check 'H2 protect-paths no longer blanket-blocks poetry.lock' `
      (-not (ProtectDenies (Join-Path $A 'poetry.lock') $protect))

Set-Location $A
RunGit switch -q -c chore/deps | Out-Null
Set-Content 'package.json' '{ "name": "t", "dependencies": { "left-pad": "1.3.0" } }'
Set-Content 'package-lock.json' '{ "lockfileVersion": 3, "packages": {} }'
RunGit add -A | Out-Null
$bothOut = RunGit commit -m 'chore: add a dependency properly'
Check 'H3 manifest + lockfile together commits cleanly' ($LASTEXITCODE -eq 0) $bothOut
Check 'H4 and produces no lockfile warning' (-not ($bothOut -match 'changed but')) $bothOut

Set-Content 'package-lock.json' '{ "lockfileVersion": 3, "packages": { "handEdited": true } }'
RunGit add -A | Out-Null
$lockOnly = RunGit commit -m 'chore: lockfile only'
Check 'H5 a lockfile-only change still commits (warn, not block)' ($LASTEXITCODE -eq 0) $lockOnly
Check 'H6 but it is surfaced' ($lockOnly -match "package-lock.json' changed but") $lockOnly
RunGit switch -q main | Out-Null
Set-Location $startDir

# ===========================================================================
Section 'I. GOVERNANCE UPDATER'
# ===========================================================================
# A genuine V1 kit out of history -> a genuine V1 project -> upgrade it.
# A local clone at the V1 commit: no tar dependency, no binary through a PowerShell pipe
# (which corrupts it), and no worktree metadata left behind in the kit repo.
$v1kit = Join-Path $WorkDir 'v1-kit'
$v1sha = (& git -C $kit merge-base HEAD main | Out-String).Trim()
& git clone --quiet --no-checkout $kit $v1kit 2>&1 | Out-Null
$cloneOk = ($LASTEXITCODE -eq 0)
& git -C $v1kit checkout --quiet $v1sha 2>&1 | Out-Null
$checkoutOk = ($LASTEXITCODE -eq 0)
Check 'I0 V1 kit checked out from history' `
      ($cloneOk -and $checkoutOk -and (Test-Path (Join-Path $v1kit 'new-governed-repo.ps1'))) `
      "sha=$v1sha clone=$cloneOk checkout=$checkoutOk"

$I = Join-Path $WorkDir 'I-v1-project'
& (Join-Path $v1kit 'new-governed-repo.ps1') -Target $I -Name 'Legacy Project' -NoLefthook *>$null
Check 'I1 V1 project scaffolds'                (Test-Path (Join-Path $I 'lefthook.yml'))
Check 'I2 V1 project has no reviewer yet'      (-not (Test-Path (Join-Path $I '.claude/agents/code-reviewer.md')))
Check 'I3 V1 project has no large-file gate'   (-not (Test-Path (Join-Path $I 'scripts/hooks/check-large-files.sh')))
Check 'I4 V1 project has no version marker'    (-not (Test-Path (Join-Path $I '.governance-version')))

# Project-owned content that must survive untouched, plus one deliberately customised gate.
Set-Content (Join-Path $I 'PRD.md') 'MY PROJECT BRIEF - must survive'
Set-Content (Join-Path $I 'WORKLOG.md') "## 2026-01-01 - real history`n- must survive"
Add-Content (Join-Path $I 'AGENTS.md') "`n<!-- PROJECT SPECIFIC RULE - must survive -->"
Add-Content (Join-Path $I 'REPO_RULES.md') "`n<!-- PROJECT SPECIFIC RATIONALE - must survive -->"
Set-Content (Join-Path $I 'src.py') 'print("my actual program")'
Set-Content (Join-Path $I '.gitleaks.toml') "title = 'my allowlist'`n[extend]`nuseDefault = true"
Add-Content (Join-Path $I '.claude/hooks/protect-paths.ps1') "`n# customised by this project"
$snapshot = @{}
foreach ($f in @('PRD.md', 'WORKLOG.md', 'AGENTS.md', 'REPO_RULES.md', 'src.py', '.gitleaks.toml',
                 '.claude/settings.json', '.claude/hooks/protect-paths.ps1')) {
    $snapshot[$f] = Get-Content (Join-Path $I $f) -Raw
}

$updater = Join-Path $kit 'update-governance.ps1'
$dry = & $updater -Target $I -DryRun *>&1 | Out-String
Check 'I5 DryRun reports the reviewer as an addition'         ($dry -match 'ADD\s+\.claude/agents/code-reviewer\.md') $dry
Check 'I6 DryRun reports the large-file gate as an addition'  ($dry -match 'ADD\s+scripts/hooks/check-large-files\.sh') $dry
Check 'I7 DryRun reports the V1 git-guard as upgradeable'     ($dry -match 'UPGRADE\s+\.claude/hooks/git-guard\.ps1') $dry
Check 'I8 DryRun reports the customised hook as a conflict'   ($dry -match 'CONFLICT\s+\.claude/hooks/protect-paths\.ps1') $dry
Check 'I9 DryRun says it wrote nothing'                       ($dry -match 'nothing was written') $dry
Check 'I10 DryRun really wrote nothing'                       (-not (Test-Path (Join-Path $I '.claude/agents/code-reviewer.md')))

$run1 = & $updater -Target $I *>&1 | Out-String
Check 'I11 the reviewer is installed by the update' (Test-Path (Join-Path $I '.claude/agents/code-reviewer.md'))
Check 'I12 the large-file gate is installed'        (Test-Path (Join-Path $I 'scripts/hooks/check-large-files.sh'))
Check 'I13 the V1 git-guard is upgraded' `
      ((Get-Content (Join-Path $I '.claude/hooks/git-guard.ps1') -Raw) -match 'codeDigest')
Check 'I14 lefthook.yml is upgraded to run the new gates' `
      ((Get-Content (Join-Path $I 'lefthook.yml') -Raw) -match 'check-large-files\.sh')

$changed = @()
foreach ($f in $snapshot.Keys) {
    if ((Get-Content (Join-Path $I $f) -Raw) -ne $snapshot[$f]) { $changed += $f }
}
Check 'I15 project-owned content survives untouched' ($changed.Count -eq 0) "changed: $($changed -join ', ')"
Check 'I16 the customised gate is preserved exactly' `
      ((Get-Content (Join-Path $I '.claude/hooks/protect-paths.ps1') -Raw) -match 'customised by this project')
Check 'I17 the conflict is reported, not hidden' ($run1 -match 'protect-paths\.ps1') $run1

$bakRoot = Join-Path $I '.governance-backup'
$bak = @(Get-ChildItem $bakRoot -Directory -ErrorAction SilentlyContinue)
Check 'I18 replaced files were backed up' ($bak.Count -gt 0 -and (Get-ChildItem $bak[0].FullName -Recurse -File).Count -gt 0)
$bakGuard = @(Get-ChildItem $bak[0].FullName -Recurse -Filter 'git-guard.ps1' -ErrorAction SilentlyContinue)
Check 'I19 the backup holds the ORIGINAL, recoverable content' `
      ($bakGuard.Count -gt 0 -and -not ((Get-Content $bakGuard[0].FullName -Raw) -match 'codeDigest'))

Check 'I20 version is NOT claimed while a conflict remains' (-not (Test-Path (Join-Path $I '.governance-version')))

$run2 = & $updater -Target $I *>&1 | Out-String
Check 'I21 a second run is a no-op'          ($run2 -match 'Nothing to update automatically|Already current') $run2
Check 'I22 a second run changes nothing'     (-not ($run2 -match '(?m)^\s+(add|upgrade):')) $run2

# Resolve the conflict the way the tool says to, then it should go fully current.
Copy-Item (Join-Path $kit 'protect-paths.template.ps1') (Join-Path $I '.claude/hooks/protect-paths.ps1') -Force
& $updater -Target $I *>&1 | Out-Null
Check 'I23 resolving the conflict stamps the version' (Test-Path (Join-Path $I '.governance-version'))
Check 'I24 the stamped version matches the kit' `
      (((Get-Content (Join-Path $I '.governance-version') -Raw).Trim()) -eq $kitVersion)

$run4 = & $updater -Target $I -DryRun *>&1 | Out-String
Check 'I25 DryRun after the update reports current' ($run4 -match 'Already current') $run4

$notGoverned = Join-Path $WorkDir 'not-a-project'
New-Item -ItemType Directory -Path $notGoverned -Force | Out-Null
$refused = $false
try { & $updater -Target $notGoverned *>&1 | Out-Null } catch { $refused = $true }
Check 'I26 it refuses a folder that was never governed' $refused

# ===========================================================================
Section 'J. REMOTE SYNC'
# ===========================================================================
$sync = Join-Path $kit 'sync-remotes.ps1'
$J = Join-Path $WorkDir 'J-sync'
$authRemote = Join-Path $WorkDir 'J-authoritative.git'
$mirror     = Join-Path $WorkDir 'J-mirror.git'
RunGit init -q --bare $authRemote | Out-Null
RunGit init -q --bare $mirror | Out-Null
New-Item -ItemType Directory -Path $J -Force | Out-Null
Set-Location $J
RunGit init -q -b main | Out-Null
RunGit config user.email 'test@example.invalid' | Out-Null
RunGit config user.name 'Acceptance Test' | Out-Null
Set-Content 'a.txt' '1'; RunGit add -A | Out-Null; RunGit commit -q -m 'init' | Out-Null
RunGit remote add origin $authRemote | Out-Null
RunGit remote add github $mirror | Out-Null
RunGit push -q origin main | Out-Null
RunGit push -q github main | Out-Null
Set-Location $startDir

$j1 = & $sync -Repo $J -DryRun *>&1 | Out-String
Check 'J1 equal copies report equal'        ($j1 -match 'already at the same commit') $j1
Check 'J2 origin is treated as authoritative' ($j1 -match 'Authoritative: origin') $j1

Set-Location $J
Set-Content 'a.txt' '2'; RunGit add -A | Out-Null; RunGit commit -q -m 'second' | Out-Null
RunGit push -q origin main | Out-Null       # authoritative only -- the mirror now lags
Set-Location $startDir

$mirrorBefore = (RunGit -C $mirror rev-parse main).Trim()
$j2 = & $sync -Repo $J -DryRun *>&1 | Out-String
Check 'J3 DryRun spots the lagging mirror'  ($j2 -match 'fast-forward github') $j2
Check 'J4 DryRun pushed nothing'            ((RunGit -C $mirror rev-parse main).Trim() -eq $mirrorBefore)

& $sync -Repo $J *>&1 | Out-Null
$localMain = (RunGit -C $J rev-parse main).Trim()
Check 'J5 a safe lag is fast-forwarded'     ((RunGit -C $mirror rev-parse main).Trim() -eq $localMain)
Check 'J6 the authoritative copy is right too' ((RunGit -C $authRemote rev-parse main).Trim() -eq $localMain)

$j4 = & $sync -Repo $J *>&1 | Out-String
Check 'J7 running it again is a clean no-op' ($j4 -match 'already at the same commit') $j4
Check 'J8 the no-op created no commit'       ((RunGit -C $J rev-parse main).Trim() -eq $localMain)

# Push a feature branch everywhere in one step.
Set-Location $J
RunGit switch -q -c feat/checkpoint | Out-Null
Set-Content 'work.txt' 'in progress'; RunGit add -A | Out-Null; RunGit commit -q -m 'feat: work' | Out-Null
Set-Location $startDir
& $sync -Repo $J -Branch feat/checkpoint *>&1 | Out-Null
Check 'J9 a feature branch reaches the authoritative remote' `
      ((RunGit -C $authRemote rev-parse --verify --quiet 'feat/checkpoint').Trim().Length -gt 0)
Check 'J10 and the mirror, in the same step' `
      ((RunGit -C $mirror rev-parse --verify --quiet 'feat/checkpoint').Trim().Length -gt 0)

# Genuine divergence: each remote gets a commit the other has never seen.
$K = Join-Path $WorkDir 'J-other-clone'
RunGit clone -q $mirror $K | Out-Null
Set-Location $K
RunGit config user.email 'test@example.invalid' | Out-Null
RunGit config user.name 'Acceptance Test' | Out-Null
RunGit switch -q main | Out-Null
Set-Content 'b.txt' 'mirror-only work'; RunGit add -A | Out-Null; RunGit commit -q -m 'mirror side' | Out-Null
RunGit push -q origin main | Out-Null
Set-Location $J
Set-Content 'c.txt' 'authoritative-only work'
RunGit switch -q main | Out-Null
RunGit add -A | Out-Null; RunGit commit -q -m 'auth side' | Out-Null
RunGit push -q origin main | Out-Null
Set-Location $startDir

$authBefore = (RunGit -C $authRemote rev-parse main).Trim()
$mirBefore  = (RunGit -C $mirror rev-parse main).Trim()
$j5 = & $sync -Repo $J *>&1 | Out-String
Check 'J11 genuine divergence is refused'    ($j5 -match 'REFUSED') $j5
Check 'J12 the refusal explains rather than picking a side' ($j5 -match 'throwing one side') $j5
Check 'J13 the authoritative copy was not touched' ((RunGit -C $authRemote rev-parse main).Trim() -eq $authBefore)
Check 'J14 the mirror was not touched'             ((RunGit -C $mirror rev-parse main).Trim() -eq $mirBefore)
Check 'J15 sync-remotes contains no force-push at all' `
      (-not ((Get-Content $sync -Raw) -match '--force\b|push\s+-f\b|\+refs/'))

# ===========================================================================
Section 'K. WORKLOG'
# ===========================================================================
$ci = Get-Content (Join-Path $kit 'optional/ci-github-actions.template.yml') -Raw
Check 'K1 CI no longer FAILS a PR for not touching WORKLOG' (-not ($ci -match '::error::[^\n]*WORKLOG'))
Check 'K2 CI still reminds on substantive PRs'  ($ci -match '::warning::[^\n]*WORKLOG')
Check 'K3 CI skips the reminder for prose-only PRs' ($ci -match 'Prose-only PR')
$agents = Get-Content (Join-Path $kit 'AGENTS.template.md') -Raw
Check 'K4 AGENTS still requires WORKLOG at real checkpoints' ($agents -match 'materially advances')
Check 'K5 AGENTS says not to commit purely for a WORKLOG line' ($agents -match "don't make a commit purely")

# ===========================================================================
Section 'L. REGRESSION / HYGIENE'
# ===========================================================================
Set-Location $kit
$prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
$leak = & gitleaks detect --no-banner --redact 2>&1 | Out-String
$leakOk = ($LASTEXITCODE -eq 0)
$ErrorActionPreference = $prev
Set-Location $startDir
Check 'L1 the kit repo itself contains no secrets' $leakOk $leak

$tracked = @((RunGit -C $kit ls-files) -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$bigTracked = @($tracked | Where-Object {
    $fp = Join-Path $kit $_
    (Test-Path $fp) -and ((Get-Item $fp).Length -gt (2048 * 1024))
})
Check 'L2 no oversized file is tracked in the kit' ($bigTracked.Count -eq 0) "$($bigTracked -join ', ')"

$selfInstalled = @('lefthook.yml', '.gitleaks.toml', '.claude/settings.json', '.claude/hooks',
                   '.governance-version', 'AGENTS.md') |
    Where-Object { Test-Path (Join-Path $kit $_) }
Check 'L3 the kit repo did not self-install active gates' ($selfInstalled.Count -eq 0) "found: $($selfInstalled -join ', ')"

$attrs = Get-Content (Join-Path $kit '.gitattributes') -Raw
Check 'L4 sh gates are kept LF-only' ($attrs -match '\*\.sh\s+text\s+eol=lf')

$shFiles = @(Get-ChildItem $kit -Filter '*.template.sh' -File)
$crlf = @($shFiles | Where-Object { [System.IO.File]::ReadAllText($_.FullName) -match "`r`n" })
Check 'L5 no sh gate has CRLF line endings' ($crlf.Count -eq 0) "$($crlf.Name -join ', ')"

$manifest = Get-Content (Join-Path $kit 'governance-manifest.json') -Raw | ConvertFrom-Json
$stale = @($manifest.files | Where-Object { -not (Test-Path (Join-Path $kit $_.template)) })
Check 'L6 every manifest entry points at a real template' ($stale.Count -eq 0) "$($stale.template -join ', ')"


# ===========================================================================
Section 'M. GLOBAL RULES UPDATER'
# ===========================================================================
# Runs against a SANDBOX home directory. It must never touch the real one.
$globalTool = Join-Path $kit 'update-global-rules.ps1'
$sandboxHome = Join-Path $WorkDir 'fake-home'
New-Item -ItemType Directory -Path (Join-Path $sandboxHome '.claude') -Force | Out-Null
$personal = "# My own notes" + "`n`n" + "A personal instruction that must survive." + "`n"
Set-Content (Join-Path $sandboxHome '.claude/CLAUDE.md') $personal

$realHome = $HOME
try {
    Set-Variable -Name HOME -Value $sandboxHome -Scope Global -Force
    $m1 = & $globalTool -Agent claude -DryRun *>&1 | Out-String
    $m2 = & $globalTool -Agent claude *>&1 | Out-String
    $m3 = & $globalTool -Agent claude *>&1 | Out-String
    $m4 = & $globalTool -Agent claude -DryRun *>&1 | Out-String
} finally {
    Set-Variable -Name HOME -Value $realHome -Scope Global -Force
}

$globalFile = Join-Path $sandboxHome '.claude/CLAUDE.md'
$after = Get-Content $globalFile -Raw
Check 'M1 DryRun reports the append without doing it' ($m1 -match 'nothing written') $m1
Check 'M2 the update applies'                    ($m2 -match 'append the managed block') $m2
Check 'M3 the personal content survives'         ($after -match 'A personal instruction that must survive')
Check 'M4 the governance block is installed'     ($after -match 'BEGIN repo-governance')
Check 'M5 the server rules came with it'         ($after -match 'bare address is the portal page')
Check 'M6 a second run is a clean no-op'         ($m3 -match 'already current') $m3
Check 'M7 DryRun after updating reports current' ($m4 -match 'already current') $m4
Check 'M8 exactly one managed block, not a pile' `
      ((([regex]::Matches($after, 'BEGIN repo-governance')).Count) -eq 1)
Check 'M9 a backup of the original was made' `
      (@(Get-ChildItem (Join-Path $sandboxHome '.claude') -Filter 'CLAUDE.md.bak-*').Count -gt 0)
Check 'M10 it says Cursor must be done by hand'  ($m2 -match 'Cursor stores its user rules')
Check 'M11 the real home directory was untouched' `
      ($realHome -eq $HOME -and $realHome -notmatch 'fake-home')

} finally {
    Set-Location $startDir
    Write-Host ""
    Write-Host ("=" * 62)
    Write-Host "PASS: $script:pass   FAIL: $script:fail" -ForegroundColor $(if ($script:fail) { 'Red' } else { 'Green' })
    if ($script:fail) {
        Write-Host "Failed:" -ForegroundColor Red
        $script:failures | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    }
    if ($Keep) { Write-Host "Left in place: $WorkDir" -ForegroundColor DarkGray }
    else { try { Remove-Item $WorkDir -Recurse -Force -ErrorAction SilentlyContinue } catch { } }
}

exit $(if ($script:fail) { 1 } else { 0 })
