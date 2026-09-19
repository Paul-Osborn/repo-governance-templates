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
function Test-ReachableGitMetadata([string]$Repository, [string]$Pattern) {
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $metadata = (& git -C $Repository log --all "--format=%an%n%ae%n%cn%n%ce%n%B" 2>&1 | Out-String)
        if ($LASTEXITCODE -ne 0) { return $false }
        $tagObjects = @(& git -C $Repository for-each-ref "--format=%(objectname)" refs/tags 2>&1)
        if ($LASTEXITCODE -ne 0) { return $false }
        foreach ($tagObject in $tagObjects) {
            if (-not $tagObject) { continue }
            $objectType = (& git -C $Repository cat-file -t $tagObject 2>&1 | Out-String).Trim()
            if ($LASTEXITCODE -ne 0) { return $false }
            if ($objectType -eq 'tag') {
                $metadata += (& git -C $Repository cat-file tag $tagObject 2>&1 | Out-String)
                if ($LASTEXITCODE -ne 0) { return $false }
            }
        }
        return $metadata -notmatch $Pattern
    }
    finally { $ErrorActionPreference = $old }
}

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

    $zeroSha = '0000000000000000000000000000000000000000'
    Push-Location $repo
    try { $rangeOut = & sh scripts/hooks/check-large-files.sh --range $zeroSha HEAD 2>&1 | Out-String; $rangeCode = $LASTEXITCODE }
    finally { Pop-Location }
    Check 'Windows Git shell large-file range fails closed for an all-zero base SHA' ($rangeCode -ne 0 -and $rangeOut -match 'unable to inspect added files for range') $rangeOut

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

    $privatePattern = 'tail[0-9a-z]+\.ts\.net|192\.168\.[0-9]+\.[0-9]+|mini' + 'sforum|server-router/' + 'routes'
    Check 'PowerShell reachable Git metadata contains no private infrastructure markers' (Test-ReachableGitMetadata $kit $privatePattern) $null

    $metadataRepo = Join-Path $WorkDir 'metadata-leak'
    Run-Git init -q -b main $metadataRepo | Out-Null
    Run-Git -C $metadataRepo config user.name 'Metadata Acceptance' | Out-Null
    Run-Git -C $metadataRepo config user.email test@example.invalid | Out-Null
    Set-Content (Join-Path $metadataRepo 'state.txt') 'baseline'
    Run-Git -C $metadataRepo add state.txt | Out-Null
    Run-Git -C $metadataRepo commit -q -m 'chore: establish metadata fixture' | Out-Null
    Add-Content (Join-Path $metadataRepo 'state.txt') 'identity leak'
    Run-Git -C $metadataRepo add state.txt | Out-Null
    $forbiddenMetadataHost = 'fixture.' + 'tailacceptance' + '.ts.net'
    $savedAuthorName = $env:GIT_AUTHOR_NAME
    $savedAuthorEmail = $env:GIT_AUTHOR_EMAIL
    $savedCommitterName = $env:GIT_COMMITTER_NAME
    $savedCommitterEmail = $env:GIT_COMMITTER_EMAIL
    try {
        $env:GIT_AUTHOR_NAME = 'Metadata Acceptance'
        $env:GIT_AUTHOR_EMAIL = "author@noreply.$forbiddenMetadataHost"
        $env:GIT_COMMITTER_NAME = 'Metadata Acceptance'
        $env:GIT_COMMITTER_EMAIL = "committer@noreply.$forbiddenMetadataHost"
        Run-Git -C $metadataRepo commit -q -m 'test: exercise forbidden identity metadata' | Out-Null
    }
    finally {
        $env:GIT_AUTHOR_NAME = $savedAuthorName
        $env:GIT_AUTHOR_EMAIL = $savedAuthorEmail
        $env:GIT_COMMITTER_NAME = $savedCommitterName
        $env:GIT_COMMITTER_EMAIL = $savedCommitterEmail
    }
    Check 'PowerShell rejects forbidden author and committer metadata' (-not (Test-ReachableGitMetadata $metadataRepo $privatePattern)) $null

    $tagRepo = Join-Path $WorkDir 'tag-metadata-leak'
    Run-Git init -q -b main $tagRepo | Out-Null
    Run-Git -C $tagRepo config user.name 'Metadata Acceptance' | Out-Null
    Run-Git -C $tagRepo config user.email test@example.invalid | Out-Null
    Set-Content (Join-Path $tagRepo 'state.txt') 'baseline'
    Run-Git -C $tagRepo add state.txt | Out-Null
    Run-Git -C $tagRepo commit -q -m 'chore: establish tag fixture' | Out-Null
    try {
        $env:GIT_COMMITTER_NAME = 'Metadata Acceptance'
        $env:GIT_COMMITTER_EMAIL = "tagger@noreply.$forbiddenMetadataHost"
        Run-Git -C $tagRepo tag -a metadata-fixture -m 'test: exercise forbidden tagger metadata' | Out-Null
    }
    finally {
        $env:GIT_COMMITTER_NAME = $savedCommitterName
        $env:GIT_COMMITTER_EMAIL = $savedCommitterEmail
    }
    Check 'PowerShell rejects forbidden tagger metadata' (-not (Test-ReachableGitMetadata $tagRepo $privatePattern)) $null
}
finally {
    Write-Host "`nPASS: $pass  FAIL: $fail"
    if ($Keep) { Write-Host "Kept: $WorkDir" } else { Remove-Item $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
}

exit $(if ($fail) { 1 } else { 0 })
