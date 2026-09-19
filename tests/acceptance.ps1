#requires -Version 5.1
<# V3 Windows acceptance tests. All repositories are disposable. #>
[CmdletBinding()]
param([switch]$Keep, [string]$WorkDir)

$ErrorActionPreference = 'Stop'
$kit = Split-Path $PSScriptRoot -Parent
if (-not $WorkDir) { $WorkDir = Join-Path ([IO.Path]::GetTempPath()) ("governance-v3-" + [guid]::NewGuid().ToString('N')) }
$pass = 0; $fail = 0

function Check([string]$Name, [bool]$Ok, $Detail) {
    if ($Ok) { $script:pass++; Write-Host "PASS  $Name" -ForegroundColor Green }
    else { $script:fail++; Write-Host "FAIL  $Name" -ForegroundColor Red; if ($Detail) { Write-Host $Detail } }
}
function Run-Git { $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'; try { & git @args 2>&1 | Out-String } finally { $ErrorActionPreference = $old } }

foreach ($tool in @('git', 'sh', 'lefthook', 'gitleaks')) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { throw "Missing test prerequisite: $tool" }
}

New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
try {
    $repo = Join-Path $WorkDir 'scaffold'
    & (Join-Path $kit 'new-governed-repo.ps1') -Target $repo -Name 'Windows Acceptance' -Owner 'test-owner' *>$null
    Check 'PowerShell bootstrap creates AGENTS.md' (Test-Path (Join-Path $repo 'AGENTS.md')) $null
    Check 'PowerShell bootstrap installs V3 policy' (Test-Path (Join-Path $repo '.governance/policy.json')) $null
    Check 'PowerShell bootstrap installs core CI' (Test-Path (Join-Path $repo '.github/workflows/governance.yml')) $null
    Check 'PowerShell bootstrap does not require Claude hooks' (-not (Test-Path (Join-Path $repo '.claude/hooks'))) $null
    Check 'PowerShell bootstrap fills governance owner' ((Get-Content (Join-Path $repo '.github/CODEOWNERS') -Raw) -match '@test-owner') $null
    Check 'PowerShell bootstrap stamps 3.x' (((Get-Content (Join-Path $repo '.governance-version') -Raw).Trim()) -match '^3\.') $null

    Run-Git -C $repo config user.email test@example.invalid | Out-Null
    Run-Git -C $repo config user.name 'Windows Acceptance' | Out-Null
    Set-Content (Join-Path $repo 'first.txt') 'first'
    Run-Git -C $repo add first.txt | Out-Null
    Push-Location $repo
    try { $branchOut = & sh scripts/hooks/no-commit-on-main.sh 2>&1 | Out-String; $branchCode = $LASTEXITCODE }
    finally { Pop-Location }
    Check 'Windows Git shell refuses default-branch commit' ($branchCode -ne 0 -and $branchOut -match 'Branch first') $branchOut

    Run-Git -C $repo switch -q -c feat/windows-acceptance | Out-Null
    Run-Git -C $repo add -A | Out-Null
    $commit = Run-Git -C $repo commit -m 'chore: establish governed baseline'
    Check 'Lefthook permits governed feature-branch commit' ($LASTEXITCODE -eq 0) $commit

    $fake = 'ghp_' + ([guid]::NewGuid().ToString('N')) + 'abcd'
    Set-Content (Join-Path $repo 'secret.txt') "GITHUB_TOKEN=$fake"
    Run-Git -C $repo add secret.txt | Out-Null
    Push-Location $repo
    try { $leakOut = & gitleaks protect --staged --redact --config .gitleaks.toml 2>&1 | Out-String; $leakCode = $LASTEXITCODE }
    finally { Pop-Location }
    Check 'Windows staged secret is refused and redacted' ($leakCode -ne 0 -and $leakOut -notmatch [regex]::Escape($fake)) $leakOut
    Run-Git -C $repo reset -q HEAD -- secret.txt | Out-Null
    Remove-Item (Join-Path $repo 'secret.txt') -Force

    [IO.File]::WriteAllBytes((Join-Path $repo 'large.bin'), (New-Object byte[] (2050 * 1024)))
    Run-Git -C $repo add large.bin | Out-Null
    Push-Location $repo
    try { $largeOut = & sh scripts/hooks/check-large-files.sh 2>&1 | Out-String; $largeCode = $LASTEXITCODE }
    finally { Pop-Location }
    Check 'Windows oversized new file is refused' ($largeCode -ne 0 -and $largeOut -match '2048 KB limit') $largeOut

    $legacy = Join-Path $WorkDir 'v2-project'
    New-Item -ItemType Directory -Path (Join-Path $legacy 'scripts/hooks') -Force | Out-Null
    Set-Content (Join-Path $legacy 'AGENTS.md') 'legacy policy'
    Set-Content (Join-Path $legacy 'source.txt') 'project source'
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $v2Branch = (& git -C $kit show 'main:no-commit-on-main.template.sh') -join "`n"
    $v2Lefthook = (& git -C $kit show 'main:lefthook.template.yml') -join "`n"
    [IO.File]::WriteAllText((Join-Path $legacy 'scripts/hooks/no-commit-on-main.sh'), $v2Branch + "`n", $utf8NoBom)
    [IO.File]::WriteAllText((Join-Path $legacy 'lefthook.yml'), $v2Lefthook + "`n", $utf8NoBom)
    Set-Content (Join-Path $legacy '.governance-version') '2.0.0'
    $dry = & (Join-Path $kit 'update-governance.ps1') -Target $legacy -DryRun *>&1 | Out-String
    Check 'PowerShell migration recognizes V2 known hashes' ($dry -match 'UPGRADE\s+scripts/hooks/no-commit-on-main.sh') $dry
    Check 'PowerShell dry-run does not write' (-not (Test-Path (Join-Path $legacy '.github/workflows/governance.yml'))) $dry
    & (Join-Path $kit 'update-governance.ps1') -Target $legacy *>$null
    Check 'PowerShell migration installs V3 workflow' (Test-Path (Join-Path $legacy '.github/workflows/governance.yml')) $null
    Check 'PowerShell migration preserves project source' ((Get-Content (Join-Path $legacy 'source.txt') -Raw).Trim() -eq 'project source') $null
    $again = & (Join-Path $kit 'update-governance.ps1') -Target $legacy *>&1 | Out-String
    Check 'PowerShell migration is idempotent' ($again -match 'Already current') $again
}
finally {
    Write-Host "`nPASS: $pass  FAIL: $fail"
    if ($Keep) { Write-Host "Kept: $WorkDir" } else { Remove-Item $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
}

exit $(if ($fail) { 1 } else { 0 })
