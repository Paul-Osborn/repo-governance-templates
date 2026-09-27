# Requires PowerShell 5.1+
param(
    [string]$Server = 'minisforum',
    [string]$BaseUrl = 'https://gitserver.tail97bf76.ts.net',
    [switch]$LocalOnly
)

$ErrorActionPreference = 'Stop'

Write-Host "Verifying server routing health and ingress..." -ForegroundColor Cyan

$routes = @(
    @{ Path = '/'; ExpectedStatus = '200'; Description = 'Home portal' },
    @{ Path = '/git/'; ExpectedStatus = '200'; Description = 'Forgejo web UI' },
    @{ Path = '/mealprep/'; ExpectedStatus = '200,501'; Description = 'Meal Prep AI' },
    @{ Path = '/keycase/'; ExpectedStatus = '200,303'; Description = 'Keycase unlock redirect' },
    @{ Path = '/factory'; ExpectedStatus = '200,401'; Description = 'Paul software factory (auth gated)' },
    @{ Path = '/neon-labrinth/'; ExpectedStatus = '200'; Description = 'neon-labrinth static app' },
    @{ Path = '/astrocade-specialist/'; ExpectedStatus = '200,302,303,401'; Description = 'Astrocade Specialist' },
    @{ Path = '/cozytavern/'; ExpectedStatus = '200'; Description = 'Cozy Tavern room' },
    @{ Path = '/happy-hour/'; ExpectedStatus = '200'; Description = 'Happy Hour game' },
    @{ Path = '/simpled/'; ExpectedStatus = '200'; Description = 'simpLED strip control' },
    @{ Path = '/sentry/'; ExpectedStatus = '200'; Description = 'Sentry AI camera stream' },
    @{ Path = '/andy/'; ExpectedStatus = '200,502'; Description = 'Andy 3.0 live view (502 when not playing)' }
)

$allPassed = $true

# Helper function to run curl locally or remotely
function Invoke-RouteProbe([string]$url, [string]$targetServer, [bool]$forceLocal) {
    if (-not $forceLocal -and $targetServer) {
        $cmd = "curl -k -sS -o /dev/null -w '%{http_code}' --max-time 10 '$url' 2>&1"
        $res = ssh $targetServer $cmd 2>$null
        return ($res | Out-String).Trim()
    } else {
        $res = & curl.exe -k -sS -o NUL -w '%{http_code}' --max-time 10 "$url" 2>&1
        return ($res | Out-String).Trim()
    }
}

# 1. Test Ingress Routes
Write-Host "`n1. Testing Ingress Routes over Tailscale ($BaseUrl):" -ForegroundColor Cyan
foreach ($r in $routes) {
    $fullUrl = $BaseUrl.TrimEnd('/') + $r.Path
    $code = Invoke-RouteProbe -url $fullUrl -targetServer $Server -forceLocal $LocalOnly
    $expected = $r.ExpectedStatus -split ','
    if ($code -in $expected) {
        Write-Host ("  [PASS] {0,-18} HTTP {1,-4} ({2})" -f $r.Path, $code, $r.Description) -ForegroundColor Green
    } else {
        Write-Host ("  [FAIL] {0,-18} HTTP {1,-4} (expected {2}; {3})" -f $r.Path, $code, $r.ExpectedStatus, $r.Description) -ForegroundColor Red
        $allPassed = $false
    }
}

# 2. Test Forgejo Subpath & Git HTTP Endpoint
Write-Host "`n2. Testing Forgejo Subpath & Git HTTP Endpoint:" -ForegroundColor Cyan
$gitProbeUrl = $BaseUrl.TrimEnd('/') + '/git/paul/repo-governance-templates.git/info/refs?service=git-upload-pack'
$gitCode = Invoke-RouteProbe -url $gitProbeUrl -targetServer $Server -forceLocal $LocalOnly
if ($gitCode -in @('401', '200')) {
    Write-Host ("  [PASS] Git HTTP endpoint reached Forgejo backend (HTTP {0} Auth Challenge)" -f $gitCode) -ForegroundColor Green
} else {
    Write-Host ("  [FAIL] Git HTTP endpoint failed (HTTP {0})" -f $gitCode) -ForegroundColor Red
    $allPassed = $false
}

# 3. Test Caddy Loopback Isolation (Ensure 8080 is NOT exposed to LAN)
if ($Server) {
    Write-Host "`n3. Testing Loopback Isolation on $($Server):" -ForegroundColor Cyan
    $rawIps = (ssh $Server "hostname -I 2>/dev/null" | Out-String).Trim()
    $lanIp = if ($rawIps) { $rawIps.Split(" `t`r`n", [StringSplitOptions]::RemoveEmptyEntries)[0] } else { $null }
    if ($lanIp) {
        $lanProbe = (ssh $Server "curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 2 'http://$lanIp:8080/' 2>&1" | Out-String).Trim()
        if ($LASTEXITCODE -ne 0 -or $lanProbe -eq '000' -or $lanProbe -match 'Failed to connect|Connection refused') {
            Write-Host ("  [PASS] Caddy port 8080 rejected direct LAN access at http://$lanIp:8080") -ForegroundColor Green
        } else {
            Write-Host ("  [FAIL] Caddy port 8080 answered on direct LAN IP ($lanProbe)") -ForegroundColor Red
            $allPassed = $false
        }
    }

    # 4. Check Service Health
    Write-Host "`n4. Checking Systemd Service Health on $($Server):" -ForegroundColor Cyan
    $services = @('caddy', 'forgejo', 'mealprep', 'keycase', 'pauls-software-factory', 'dashboard', 'astrocade-specialist-server', 'simpled')
    foreach ($svc in $services) {
        $state = (ssh $Server "systemctl is-active $svc 2>/dev/null" | Out-String).Trim()
        if ($state -eq 'active') {
            Write-Host ("  [PASS] {0,-25} is active" -f $svc) -ForegroundColor Green
        } else {
            Write-Host ("  [FAIL] {0,-25} state is '$state'" -f $svc) -ForegroundColor Red
            $allPassed = $false
        }
    }
}

Write-Host ""
if ($allPassed) {
    Write-Host "Overall verification: ALL CHECKS PASSED" -ForegroundColor Green
} else {
    Write-Host "Overall verification: ONE OR MORE CHECKS FAILED" -ForegroundColor Red
    exit 1
}
