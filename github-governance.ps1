#requires -Version 5.1
<# Inspect or apply GitHub governance. Plan-only is the default. #>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Repo,
    [string]$Profile = (Join-Path $PSScriptRoot 'github/governance-profile.json'),
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { throw 'gh is required.' }
if (-not (Test-Path $Profile)) { throw "Profile not found: $Profile" }

$desired = Get-Content $Profile -Raw | ConvertFrom-Json
$repoInfo = (& gh api "repos/$Repo" | Out-String) | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) { throw "Cannot inspect $Repo. Check gh auth and repository access." }

$rulesets = $null
$rulesetsSupported = $true
try {
    $raw = & gh api "repos/$Repo/rulesets" 2>$null | Out-String
    if ($LASTEXITCODE -ne 0) { throw 'rulesets unavailable' }
    $rulesets = $raw | ConvertFrom-Json
} catch { $rulesetsSupported = $false }

Write-Host 'GitHub governance plan' -ForegroundColor Cyan
Write-Host "  repository: $Repo ($($repoInfo.visibility))"
Write-Host "  default branch: $($repoInfo.default_branch)"
Write-Host "  governance owner: $($desired.governanceOwner)"
Write-Host "  detected capability: $(if ($rulesetsSupported) { 'rulesets' } else { 'branch-protection-fallback' })"
Write-Host '  required checks:'
$reviewContext = $desired.review.statusContext
$defaultIntegrationId = $desired.review.preferredTrustedIntegrationId
$reviewerAppId = $desired.review.externalReviewerAppId
$requireReview = if ($null -eq $desired.review.requireIndependentReview) { $true } else { $desired.review.requireIndependentReview }
foreach ($check in $desired.requiredStatusChecks) {
    if ($check -eq $reviewContext) {
        if (-not $requireReview) {
            Write-Host "    - $check (independent review not required by policy; this check always succeeds)"
        } elseif ($reviewerAppId) {
            Write-Host "    - $check (integration_id $reviewerAppId, dedicated reviewer App)"
        } else {
            Write-Host "    - $check (integration_id $defaultIntegrationId, default Actions identity; no reviewer App configured yet)"
        }
    } else {
        Write-Host "    - $check (integration_id $defaultIntegrationId)"
    }
}
Write-Host '  pull requests, code-owner/last-push review, linear history, no force push/deletion'
Write-Host '  workflow token default: read; Actions cannot approve PRs'

$existing = @($rulesets | Where-Object name -eq $desired.rulesetName | Select-Object -First 1)
if ($rulesetsSupported) {
    Write-Host "  action: $(if ($existing) { "update ruleset $($existing.id)" } else { "create ruleset '$($desired.rulesetName)'" })"
} else {
    Write-Warning 'Rulesets unavailable; apply will attempt classic branch protection. Plan/visibility may require a manual fallback.'
}

if (-not $Apply) {
    Write-Host 'PLAN ONLY: no repository settings were changed. Re-run with -Apply after review.' -ForegroundColor Yellow
    exit 0
}
if ($desired.governanceOwner -match '<owner>' -or -not $desired.governanceOwner) {
    throw 'Replace <owner> in the profile before applying.'
}

& gh api --method PUT "repos/$Repo/actions/permissions/workflow" `
    -f default_workflow_permissions=read -F can_approve_pull_request_reviews=false | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Failed to set least-privilege Actions defaults.' }

$temp = [System.IO.Path]::GetTempFileName()
try {
    if ($rulesetsSupported) {
        $payload = Get-Content (Join-Path $PSScriptRoot 'github/rulesets/default-branch.json') -Raw | ConvertFrom-Json
        $payload.name = $desired.rulesetName
        $statusRule = $payload.rules | Where-Object type -eq 'required_status_checks'
        $statusRule.parameters.required_status_checks = @($desired.requiredStatusChecks | ForEach-Object {
            $integrationId = if ($_ -eq $reviewContext -and $reviewerAppId) { $reviewerAppId } else { $defaultIntegrationId }
            [pscustomobject]@{ context = $_; integration_id = $integrationId }
        })
        [IO.File]::WriteAllText($temp, ($payload | ConvertTo-Json -Depth 12), (New-Object Text.UTF8Encoding($false)))
        if ($existing) { & gh api --method PUT "repos/$Repo/rulesets/$($existing.id)" --input $temp | Out-Null }
        else { & gh api --method POST "repos/$Repo/rulesets" --input $temp | Out-Null }
        if ($LASTEXITCODE -ne 0) { throw 'GitHub rejected the ruleset payload.' }
        Write-Host "Applied GitHub ruleset '$($desired.rulesetName)'." -ForegroundColor Green
    } else {
        $payload = [ordered]@{
            required_status_checks = @{ strict = $true; contexts = @($desired.requiredStatusChecks) }
            enforce_admins = $true
            required_pull_request_reviews = @{
                dismissal_restrictions = @{}; dismiss_stale_reviews = $true
                require_code_owner_reviews = $true; required_approving_review_count = 0
                require_last_push_approval = $true; bypass_pull_request_allowances = @{}
            }
            restrictions = $null; required_linear_history = $true
            allow_force_pushes = $false; allow_deletions = $false
            required_conversation_resolution = $true; lock_branch = $false; allow_fork_syncing = $true
        }
        [IO.File]::WriteAllText($temp, ($payload | ConvertTo-Json -Depth 12), (New-Object Text.UTF8Encoding($false)))
        & gh api --method PUT "repos/$Repo/branches/$($repoInfo.default_branch)/protection" --input $temp | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Classic branch protection was rejected; owner setup is required in GitHub settings.' }
        Write-Host 'Applied classic branch protection fallback; verify CODEOWNERS review in GitHub settings.' -ForegroundColor Green
    }
} finally { Remove-Item $temp -Force -ErrorAction SilentlyContinue }
