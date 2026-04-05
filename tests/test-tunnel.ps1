#!/usr/bin/env pwsh

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("wsl-tunnel-tests-" + [guid]::NewGuid().Guid)
$tests = New-Object System.Collections.Generic.List[object]

function Add-TestResult {
    param(
        [string]$Name,
        [string]$Result,
        [string]$Message = ""
    )

    $tests.Add([PSCustomObject]@{
        Name = $Name
        Result = $Result
        Message = $Message
    })
}

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Invoke-Test {
    param(
        [string]$Name,
        [scriptblock]$ScriptBlock
    )

    try {
        & $ScriptBlock
        Add-TestResult -Name $Name -Result "PASS"
    } catch {
        Add-TestResult -Name $Name -Result "FAIL" -Message $_.Exception.Message
    }
}

function Write-JsonFile {
    param(
        [string]$Path,
        [object]$Data
    )

    if ($Data -is [System.Array] -and $Data.Count -eq 0) {
        Set-Content -LiteralPath $Path -Value "[]"
        return
    }

    $json = $Data | ConvertTo-Json -Depth 10
    Set-Content -LiteralPath $Path -Value $json
}

New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
$runtimeRoot = Join-Path $tempRoot "runtime"
$processFixture = Join-Path $tempRoot "processes.json"
$portFixture = Join-Path $tempRoot "ports.json"
$selectionFixture = Join-Path $tempRoot "selection.json"
$duplicateCatalog = Join-Path $tempRoot "duplicate-catalog.json"
$missingFieldCatalog = Join-Path $tempRoot "missing-field-catalog.json"

$env:WSL_TUNNEL_RUNTIME_ROOT = $runtimeRoot
$env:WSL_TUNNEL_PROCESS_FIXTURE = $processFixture
$env:WSL_TUNNEL_PORT_FIXTURE = $portFixture
$env:WSL_TUNNEL_SELECTION_FIXTURE = $null
$env:WSL_TUNNEL_CATALOG_PATH = Join-Path $repoRoot "catalog\tunnels.json"

. (Join-Path $repoRoot "wsl-tunnel.ps1")

Invoke-Test -Name "Guided CLI and catalog files exist" -ScriptBlock {
    Assert-True (Test-Path -LiteralPath (Join-Path $repoRoot "wsl-tunnel.ps1")) "Missing wsl-tunnel.ps1"
    Assert-True (Test-Path -LiteralPath (Join-Path $repoRoot "catalog\tunnels.json")) "Missing catalog/tunnels.json"
}

Invoke-Test -Name "Catalog loads and required services exist" -ScriptBlock {
    $catalog = @(Get-WslTunnelCatalog)
    Assert-True ($catalog.Count -ge 2) "Expected at least two catalog services."
    Assert-True (($catalog | Select-Object -ExpandProperty name) -contains "api") "Catalog should include 'api'."
    Assert-True (($catalog | Select-Object -ExpandProperty name) -contains "jobs") "Catalog should include 'jobs'."
}

Invoke-Test -Name "Catalog rejects duplicate windowsPort and wslPort" -ScriptBlock {
    Write-JsonFile -Path $duplicateCatalog -Data @{
        services = @(
            @{ name = "api"; description = "a"; windowsPort = 8443; wslPort = 18443; protocol = "https" },
            @{ name = "api-copy"; description = "b"; windowsPort = 8443; wslPort = 18443; protocol = "https" }
        )
    }

    $failed = $false
    try {
        Get-WslTunnelCatalog -Path $duplicateCatalog | Out-Null
    } catch {
        $failed = $true
        Assert-True ($_.Exception.Message -match "duplicated") "Expected duplicate validation message."
    }

    Assert-True $failed "Duplicate catalog should fail validation."
}

Invoke-Test -Name "Catalog rejects missing required field" -ScriptBlock {
    Write-JsonFile -Path $missingFieldCatalog -Data @{
        services = @(
            @{ name = "api"; windowsPort = 8443; wslPort = 18443; protocol = "https" }
        )
    }

    $failed = $false
    try {
        Get-WslTunnelCatalog -Path $missingFieldCatalog | Out-Null
    } catch {
        $failed = $true
        Assert-True ($_.Exception.Message -match "required field") "Expected required field validation message."
    }

    Assert-True $failed "Missing-field catalog should fail validation."
}

Invoke-Test -Name "State discovery marks active tunnels from mocked ssh command lines" -ScriptBlock {
    Write-JsonFile -Path $processFixture -Data @(
        @{ ProcessId = 101; CommandLine = "ssh -N -R 18443:localhost:8443 wsl-localhost" },
        @{ ProcessId = 202; CommandLine = "ssh -N -R 18080:localhost:8080 wsl-localhost" }
    )
    Write-JsonFile -Path $portFixture -Data @{ listeningPorts = @(8443, 8080) }

    $catalog = @(Get-WslTunnelCatalog)
    $states = @(Get-WslTunnelServiceStates -Catalog $catalog)
    $api = $states | Where-Object { $_.name -eq "api" } | Select-Object -First 1
    $jobs = $states | Where-Object { $_.name -eq "jobs" } | Select-Object -First 1

    Assert-True $api.Active "api should be active from process fixture."
    Assert-True $jobs.Active "jobs should be active from process fixture."
    Assert-True ($api.PrimaryPid -eq 101) "api PID should be discovered from process fixture."
}

Invoke-Test -Name "Interactive selection fixture resolves multiple services" -ScriptBlock {
    Write-JsonFile -Path $selectionFixture -Data @{ services = @("jobs", "api") }
    $env:WSL_TUNNEL_SELECTION_FIXTURE = $selectionFixture
    Write-JsonFile -Path $processFixture -Data @()
    Write-JsonFile -Path $portFixture -Data @{ listeningPorts = @(8443, 8080) }

    $catalog = @(Get-WslTunnelCatalog)
    $states = @(Get-WslTunnelServiceStates -Catalog $catalog)
    $selected = @(Show-WslTunnelSelectionMenu -States $states)

    Assert-True ($selected.Count -eq 2) "Expected two selected services from fixture."
    Assert-True ($selected[0].name -eq "jobs") "Selection order should follow the fixture."
    Assert-True ($selected[1].name -eq "api") "Selection order should follow the fixture."
    $env:WSL_TUNNEL_SELECTION_FIXTURE = $null
}

Invoke-Test -Name "Stale marker files are cleaned when no live process exists" -ScriptBlock {
    Write-JsonFile -Path $processFixture -Data @()
    Write-JsonFile -Path $portFixture -Data @{ listeningPorts = @(8443) }

    $markerDir = Get-WslTunnelMarkerRoot
    New-Item -ItemType Directory -Path $markerDir -Force | Out-Null
    Write-JsonFile -Path (Join-Path $markerDir "api.json") -Data @{
        serviceName = "api"
        pid = 999
        windowsPort = 8443
        wslPort = 18443
        sshHostAlias = "wsl-localhost"
        createdAt = (Get-Date).ToString("o")
    }

    $catalog = @(Get-WslTunnelCatalog)
    $null = Get-WslTunnelServiceStates -Catalog $catalog

    Assert-True (-not (Test-Path -LiteralPath (Join-Path $markerDir "api.json"))) "Expected stale api marker to be removed."
}

Invoke-Test -Name "list command works with fixtures" -ScriptBlock {
    Write-JsonFile -Path $processFixture -Data @()
    Write-JsonFile -Path $portFixture -Data @{ listeningPorts = @(8443) }
    $output = & pwsh -NoProfile -File (Join-Path $repoRoot "wsl-tunnel.ps1") list 2>&1
    Assert-True ($LASTEXITCODE -eq 0) "list command should exit successfully."
    Assert-True (($output | Out-String) -match "api") "list output should mention api."
}

Invoke-Test -Name "status command supports a named service" -ScriptBlock {
    Write-JsonFile -Path $processFixture -Data @(
        @{ ProcessId = 101; CommandLine = "ssh -N -R 18443:localhost:8443 wsl-localhost" }
    )
    Write-JsonFile -Path $portFixture -Data @{ listeningPorts = @(8443) }
    $output = & pwsh -NoProfile -File (Join-Path $repoRoot "wsl-tunnel.ps1") status api 2>&1
    Assert-True ($LASTEXITCODE -eq 0) "status api should exit successfully."
    Assert-True (($output | Out-String) -match "api") "status api should print the requested service."
}

Invoke-Test -Name "up rejects an unknown service" -ScriptBlock {
    Write-JsonFile -Path $processFixture -Data @()
    Write-JsonFile -Path $portFixture -Data @{ listeningPorts = @() }
    $output = & pwsh -NoProfile -File (Join-Path $repoRoot "wsl-tunnel.ps1") up missing 2>&1
    Assert-True ($LASTEXITCODE -eq 1) "up missing should fail."
    Assert-True (($output | Out-String) -match "Unknown service") "Expected unknown service message."
}

Invoke-Test -Name "up without a service guides non-interactive users" -ScriptBlock {
    Write-JsonFile -Path $processFixture -Data @()
    Write-JsonFile -Path $portFixture -Data @{ listeningPorts = @(8443) }
    $env:WSL_TUNNEL_SELECTION_FIXTURE = $null
    $output = & pwsh -NoProfile -File (Join-Path $repoRoot "wsl-tunnel.ps1") up 2>&1
    Assert-True ($LASTEXITCODE -eq 1) "up without a service should fail in non-interactive mode."
    Assert-True (($output | Out-String) -match "Interactive selection requires a real console") "Expected interactive guidance."
}

Invoke-Test -Name "up rejects service when Windows port is not listening" -ScriptBlock {
    Write-JsonFile -Path $processFixture -Data @()
    Write-JsonFile -Path $portFixture -Data @{ listeningPorts = @() }
    $output = & pwsh -NoProfile -File (Join-Path $repoRoot "wsl-tunnel.ps1") up api 2>&1
    Assert-True ($LASTEXITCODE -eq 1) "up api should fail when Windows port is unavailable."
    Assert-True (($output | Out-String) -match "not available") "Expected unavailable service message."
}

Invoke-Test -Name "up rejects already active service" -ScriptBlock {
    Write-JsonFile -Path $processFixture -Data @(
        @{ ProcessId = 101; CommandLine = "ssh -N -R 18443:localhost:8443 wsl-localhost" }
    )
    Write-JsonFile -Path $portFixture -Data @{ listeningPorts = @(8443) }
    $output = & pwsh -NoProfile -File (Join-Path $repoRoot "wsl-tunnel.ps1") up api 2>&1
    Assert-True ($LASTEXITCODE -eq 1) "up api should fail if already active."
    Assert-True (($output | Out-String) -match "already active") "Expected already active message."
}

Invoke-Test -Name "up reports WSL port conflict" -ScriptBlock {
    Write-JsonFile -Path $processFixture -Data @(
        @{ ProcessId = 303; CommandLine = "ssh -N -R 18443:localhost:9999 wsl-localhost" }
    )
    Write-JsonFile -Path $portFixture -Data @{ listeningPorts = @(8443) }
    $output = & pwsh -NoProfile -File (Join-Path $repoRoot "wsl-tunnel.ps1") up api 2>&1
    Assert-True ($LASTEXITCODE -eq 1) "up api should fail when the WSL port is already used."
    Assert-True (($output | Out-String) -match "already used") "Expected WSL port conflict message."
}

Write-Host "`n=== WSL Tunnel Test Summary ===" -ForegroundColor Cyan
Write-Host ""

$passCount = @($tests | Where-Object { $_.Result -eq "PASS" }).Count
$failCount = @($tests | Where-Object { $_.Result -eq "FAIL" }).Count

foreach ($test in $tests) {
    $color = if ($test.Result -eq "PASS") { "Green" } else { "Red" }
    Write-Host "[$($test.Result)]" -ForegroundColor $color -NoNewline
    Write-Host " $($test.Name)"
    if ($test.Message) {
        Write-Host "  -> $($test.Message)" -ForegroundColor Gray
    }
}

Write-Host ""
Write-Host "Summary: $passCount passed, $failCount failed." -ForegroundColor Cyan

Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
$env:WSL_TUNNEL_RUNTIME_ROOT = $null
$env:WSL_TUNNEL_PROCESS_FIXTURE = $null
$env:WSL_TUNNEL_PORT_FIXTURE = $null
$env:WSL_TUNNEL_SELECTION_FIXTURE = $null
$env:WSL_TUNNEL_CATALOG_PATH = $null

if ($failCount -gt 0) {
    exit 1
}

Write-Host "`nGuided CLI repository checks passed." -ForegroundColor Green
