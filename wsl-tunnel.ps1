param(
    [Parameter(Position = 0)]
    [ValidateSet("list", "up", "down", "status")]
    [string]$Action = "list",

    [Parameter(Position = 1)]
    [string]$ServiceName,

    [string]$SshHostAlias = "wsl-localhost"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 3

function Get-WslTunnelRepoRoot {
    return $PSScriptRoot
}

function Get-WslTunnelCatalogPath {
    if ($env:WSL_TUNNEL_CATALOG_PATH) {
        return $env:WSL_TUNNEL_CATALOG_PATH
    }

    return Join-Path (Get-WslTunnelRepoRoot) "catalog\tunnels.json"
}

function Get-WslTunnelRuntimeRoot {
    if ($env:WSL_TUNNEL_RUNTIME_ROOT) {
        return $env:WSL_TUNNEL_RUNTIME_ROOT
    }

    if ($env:LOCALAPPDATA) {
        return Join-Path $env:LOCALAPPDATA "wsl-tunnel"
    }

    return Join-Path ([System.IO.Path]::GetTempPath()) "wsl-tunnel"
}

function Get-WslTunnelMarkerRoot {
    return Join-Path (Get-WslTunnelRuntimeRoot) "active"
}

function Get-WslTunnelLogRoot {
    return Join-Path (Get-WslTunnelRuntimeRoot) "logs"
}

function Ensure-WslTunnelDirectory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function ConvertFrom-WslTunnelJson {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content,

        [int]$Depth = 10
    )

    $command = Get-Command ConvertFrom-Json -ErrorAction Stop
    $hasDepth = $command.Parameters.ContainsKey("Depth")

    if ($hasDepth) {
        return $Content | ConvertFrom-Json -Depth $Depth
    }

    return $Content | ConvertFrom-Json
}

function Get-WslTunnelCatalog {
    param(
        [string]$Path = (Get-WslTunnelCatalogPath)
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Catalog not found: $Path"
    }

    $document = ConvertFrom-WslTunnelJson -Content (Get-Content -LiteralPath $Path -Raw) -Depth 10
    if (-not $document.services) {
        throw "Catalog '$Path' must contain a 'services' array."
    }

    $services = @($document.services)
    if ($services.Count -eq 0) {
        throw "Catalog '$Path' must declare at least one service."
    }

    $requiredFields = @("name", "description", "windowsPort", "wslPort", "protocol")
    $names = @{}
    $windowsPorts = @{}
    $wslPorts = @{}
    $validated = New-Object System.Collections.Generic.List[object]

    foreach ($service in $services) {
        foreach ($field in $requiredFields) {
            $property = $service.PSObject.Properties[$field]
            $value = if ($property) { $property.Value } else { $null }
            if ($null -eq $value -or [string]::IsNullOrWhiteSpace([string]$value)) {
                throw "Catalog service is missing required field '$field'."
            }
        }

        $name = [string]$service.name
        if ($name -notmatch "^[a-z0-9][a-z0-9-]*$") {
            throw "Catalog service name '$name' must use lowercase letters, digits, or hyphens."
        }

        $windowsPort = [int]$service.windowsPort
        $wslPort = [int]$service.wslPort
        if ($windowsPort -lt 1 -or $windowsPort -gt 65535) {
            throw "Catalog service '$name' has invalid windowsPort '$windowsPort'."
        }

        if ($wslPort -lt 1 -or $wslPort -gt 65535) {
            throw "Catalog service '$name' has invalid wslPort '$wslPort'."
        }

        if ($names.ContainsKey($name)) {
            throw "Catalog service name '$name' is duplicated."
        }

        if ($windowsPorts.ContainsKey($windowsPort)) {
            throw "Catalog windowsPort '$windowsPort' is duplicated."
        }

        if ($wslPorts.ContainsKey($wslPort)) {
            throw "Catalog wslPort '$wslPort' is duplicated."
        }

        $names[$name] = $true
        $windowsPorts[$windowsPort] = $true
        $wslPorts[$wslPort] = $true

        $note = ""
        if ($service.PSObject.Properties["note"]) {
            $note = [string]$service.note
        }

        $validated.Add([PSCustomObject]@{
            name = $name
            description = [string]$service.description
            windowsPort = $windowsPort
            wslPort = $wslPort
            protocol = ([string]$service.protocol).ToLowerInvariant()
            note = $note
        })
    }

    return $validated
}

function Resolve-WslTunnelService {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [object[]]$Catalog
    )

    $service = $Catalog | Where-Object { $_.name -eq $Name } | Select-Object -First 1
    if (-not $service) {
        $known = ($Catalog | Select-Object -ExpandProperty name) -join ", "
        throw "Unknown service '$Name'. Available services: $known"
    }

    return $service
}

function Get-WslTunnelPortFixture {
    if (-not $env:WSL_TUNNEL_PORT_FIXTURE) {
        return $null
    }

    if (-not (Test-Path -LiteralPath $env:WSL_TUNNEL_PORT_FIXTURE)) {
        throw "Port fixture not found: $($env:WSL_TUNNEL_PORT_FIXTURE)"
    }

    $fixture = ConvertFrom-WslTunnelJson -Content (Get-Content -LiteralPath $env:WSL_TUNNEL_PORT_FIXTURE -Raw) -Depth 10
    if ($fixture.PSObject.Properties["listeningPorts"]) {
        return @($fixture.listeningPorts | ForEach-Object { [int]$_ })
    }

    return @($fixture | ForEach-Object { [int]$_ })
}

function Test-WslTunnelWindowsPortListening {
    param(
        [Parameter(Mandatory = $true)]
        [int]$Port
    )

    $fixturePorts = Get-WslTunnelPortFixture
    if ($null -ne $fixturePorts) {
        return $fixturePorts -contains $Port
    }

    $listener = Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue |
        Select-Object -First 1

    return $null -ne $listener
}

function Get-WslTunnelProcessSource {
    if ($env:WSL_TUNNEL_PROCESS_FIXTURE) {
        if (-not (Test-Path -LiteralPath $env:WSL_TUNNEL_PROCESS_FIXTURE)) {
            throw "Process fixture not found: $($env:WSL_TUNNEL_PROCESS_FIXTURE)"
        }

        return ConvertFrom-WslTunnelJson -Content (Get-Content -LiteralPath $env:WSL_TUNNEL_PROCESS_FIXTURE -Raw) -Depth 10
    }

    return Get-CimInstance Win32_Process |
        Where-Object { $_.Name -in @("ssh.exe", "ssh") } |
        Select-Object ProcessId, CommandLine
}

function Get-WslTunnelParsedProcesses {
    $regex = '-R\s+"?(?<wslPort>\d+):localhost:(?<windowsPort>\d+)"?'
    $processes = New-Object System.Collections.Generic.List[object]

    foreach ($process in @(Get-WslTunnelProcessSource)) {
        $commandLine = [string]$process.CommandLine
        if ([string]::IsNullOrWhiteSpace($commandLine)) {
            continue
        }

        $match = [regex]::Match($commandLine, $regex)
        if (-not $match.Success) {
            continue
        }

        $processes.Add([PSCustomObject]@{
            ProcessId = [int]$process.ProcessId
            CommandLine = $commandLine
            WslPort = [int]$match.Groups["wslPort"].Value
            WindowsPort = [int]$match.Groups["windowsPort"].Value
        })
    }

    return $processes
}

function Get-WslTunnelMarkerPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServiceName
    )

    return Join-Path (Get-WslTunnelMarkerRoot) "$ServiceName.json"
}

function Get-WslTunnelMarkers {
    $markerRoot = Get-WslTunnelMarkerRoot
    if (-not (Test-Path -LiteralPath $markerRoot)) {
        return @()
    }

    $markers = New-Object System.Collections.Generic.List[object]
    foreach ($file in Get-ChildItem -LiteralPath $markerRoot -Filter *.json -File) {
        try {
            $marker = ConvertFrom-WslTunnelJson -Content (Get-Content -LiteralPath $file.FullName -Raw) -Depth 10
            $markers.Add([PSCustomObject]@{
                Path = $file.FullName
                serviceName = [string]$marker.serviceName
                pid = [int]$marker.pid
                windowsPort = [int]$marker.windowsPort
                wslPort = [int]$marker.wslPort
                sshHostAlias = [string]$marker.sshHostAlias
                createdAt = [string]$marker.createdAt
            })
        } catch {
            Remove-Item -LiteralPath $file.FullName -Force -ErrorAction SilentlyContinue
        }
    }

    return $markers
}

function Write-WslTunnelMarker {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Service,

        [Parameter(Mandatory = $true)]
        [int]$ProcessId,

        [Parameter(Mandatory = $true)]
        [string]$SshHostAlias
    )

    Ensure-WslTunnelDirectory -Path (Get-WslTunnelMarkerRoot)
    $payload = [PSCustomObject]@{
        version = 1
        serviceName = $Service.name
        pid = $ProcessId
        windowsPort = $Service.windowsPort
        wslPort = $Service.wslPort
        sshHostAlias = $SshHostAlias
        createdAt = (Get-Date).ToString("o")
    }

    $json = $payload | ConvertTo-Json -Depth 5
    Set-Content -LiteralPath (Get-WslTunnelMarkerPath -ServiceName $Service.name) -Value $json
}

function Remove-WslTunnelMarker {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServiceName
    )

    $path = Get-WslTunnelMarkerPath -ServiceName $ServiceName
    if (Test-Path -LiteralPath $path) {
        Remove-Item -LiteralPath $path -Force
    }
}

function Get-WslTunnelTestCommand {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Service
    )

    switch ($Service.protocol) {
        "https" { return "curl -k https://localhost:$($Service.wslPort)" }
        "http" { return "curl http://localhost:$($Service.wslPort)" }
        default { return "nc -vz localhost $($Service.wslPort)" }
    }
}

function Get-WslTunnelActionHint {
    param(
        [Parameter(Mandatory = $true)]
        [object]$State
    )

    if ($State.Active -and $State.WindowsAvailable) {
        return "Run '.\wsl-tunnel.ps1 down $($State.name)' when you are done."
    }

    if ($State.Active -and -not $State.WindowsAvailable) {
        return "Tunnel is active, but the Windows service is down. Restart the Windows service or run '.\wsl-tunnel.ps1 down $($State.name)'."
    }

    if (-not $State.WindowsAvailable) {
        return "Start the Windows service on port $($State.windowsPort), then run '.\wsl-tunnel.ps1 up $($State.name)'."
    }

    return "Run '.\wsl-tunnel.ps1 up $($State.name)' to start the tunnel."
}

function Test-WslTunnelInteractiveConsole {
    if ($env:WSL_TUNNEL_SELECTION_FIXTURE) {
        return $true
    }

    try {
        return (-not [Console]::IsInputRedirected) -and (-not [Console]::IsOutputRedirected)
    } catch {
        return $false
    }
}

function Get-WslTunnelSelectionFixture {
    if (-not $env:WSL_TUNNEL_SELECTION_FIXTURE) {
        return $null
    }

    if (-not (Test-Path -LiteralPath $env:WSL_TUNNEL_SELECTION_FIXTURE)) {
        throw "Selection fixture not found: $($env:WSL_TUNNEL_SELECTION_FIXTURE)"
    }

    $fixture = ConvertFrom-WslTunnelJson -Content (Get-Content -LiteralPath $env:WSL_TUNNEL_SELECTION_FIXTURE -Raw) -Depth 10
    if ($fixture -is [string]) {
        return @([string]$fixture)
    }

    if ($fixture.PSObject.Properties["services"]) {
        return @($fixture.services | ForEach-Object { [string]$_ })
    }

    return @($fixture | ForEach-Object { [string]$_ })
}

function Get-WslTunnelServiceStates {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Catalog,

        [string]$SshHostAlias = "wsl-localhost"
    )

    $markers = @(Get-WslTunnelMarkers)
    $processes = @(Get-WslTunnelParsedProcesses)
    $processesByService = @{}

    foreach ($process in $processes) {
        $service = $Catalog |
            Where-Object { $_.wslPort -eq $process.WslPort -and $_.windowsPort -eq $process.WindowsPort } |
            Select-Object -First 1

        if (-not $service) {
            continue
        }

        if (-not $processesByService.ContainsKey($service.name)) {
            $processesByService[$service.name] = @()
        }

        $processesByService[$service.name] += $process
    }

    $markersByService = @{}
    foreach ($marker in $markers) {
        if (-not $markersByService.ContainsKey($marker.serviceName)) {
            $markersByService[$marker.serviceName] = @()
        }

        $markersByService[$marker.serviceName] += $marker
    }

    $states = New-Object System.Collections.Generic.List[object]
    foreach ($service in $Catalog) {
        $liveProcesses = @()
        if ($processesByService.ContainsKey($service.name)) {
            $liveProcesses = @($processesByService[$service.name])
        }

        $markerEntries = @()
        if ($markersByService.ContainsKey($service.name)) {
            $markerEntries = @($markersByService[$service.name])
        }

        foreach ($marker in $markerEntries) {
            $matchingProcess = $liveProcesses | Where-Object { $_.ProcessId -eq $marker.pid } | Select-Object -First 1
            if (-not $matchingProcess) {
                Remove-WslTunnelMarker -ServiceName $service.name
            }
        }

        $primaryPid = $null
        if ($liveProcesses.Count -gt 0) {
            $primaryProcess = $liveProcesses | Select-Object -First 1
            $primaryPid = [int]$primaryProcess.ProcessId
            Write-WslTunnelMarker -Service $service -ProcessId $primaryPid -SshHostAlias $SshHostAlias
        }

        $state = [PSCustomObject]@{
            name = $service.name
            description = $service.description
            protocol = $service.protocol
            windowsPort = $service.windowsPort
            wslPort = $service.wslPort
            note = $service.note
            WindowsAvailable = (Test-WslTunnelWindowsPortListening -Port $service.windowsPort)
            Active = $liveProcesses.Count -gt 0
            ProcessIds = @($liveProcesses | Select-Object -ExpandProperty ProcessId)
            PrimaryPid = $primaryPid
            DuplicateProcessCount = [Math]::Max($liveProcesses.Count - 1, 0)
        }

        $state | Add-Member -NotePropertyName Hint -NotePropertyValue (Get-WslTunnelActionHint -State $state)
        $state | Add-Member -NotePropertyName TestCommand -NotePropertyValue (Get-WslTunnelTestCommand -Service $service)
        $states.Add($state)
    }

    return $states
}

function Resolve-WslTunnelSelectedStates {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$States,

        [Parameter(Mandatory = $true)]
        [string[]]$SelectedNames
    )

    $resolved = New-Object System.Collections.Generic.List[object]
    foreach ($selectedName in $SelectedNames) {
        $state = $States | Where-Object { $_.name -eq $selectedName } | Select-Object -First 1
        if (-not $state) {
            throw "Unknown service '$selectedName' in interactive selection."
        }

        $resolved.Add($state)
    }

    return $resolved
}

function Assert-WslTunnelCommandRequirements {
    if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) {
        throw "ssh was not found in PATH. Install OpenSSH for Windows or add ssh.exe to PATH."
    }
}

function Get-WslTunnelProcessConflict {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Service
    )

    $processes = @(Get-WslTunnelParsedProcesses)
    foreach ($process in $processes) {
        if ($process.WslPort -eq $Service.wslPort -and $process.WindowsPort -ne $Service.windowsPort) {
            return $process
        }
    }

    return $null
}

function New-WslTunnelLogs {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServiceName
    )

    Ensure-WslTunnelDirectory -Path (Get-WslTunnelLogRoot)
    $stamp = Get-Date -Format "yyyyMMdd-HHmmssfff"
    return [PSCustomObject]@{
        StdOut = Join-Path (Get-WslTunnelLogRoot) "$ServiceName-$stamp.stdout.log"
        StdErr = Join-Path (Get-WslTunnelLogRoot) "$ServiceName-$stamp.stderr.log"
    }
}

function Remove-WslTunnelLogs {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Logs
    )

    foreach ($path in @($Logs.StdOut, $Logs.StdErr)) {
        if (Test-Path -LiteralPath $path) {
            Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        }
    }
}

function Format-WslTunnelLaunchError {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServiceName,

        [Parameter(Mandatory = $true)]
        [string]$RawError
    )

    $trimmed = $RawError.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed)) {
        return "Failed to start tunnel '$ServiceName'. Verify SSH access to WSL with 'ssh wsl-localhost'."
    }

    if ($trimmed -match "Permission denied") {
        return "Failed to start tunnel '$ServiceName'. SSH authentication was rejected. Verify your Windows -> WSL SSH setup."
    }

    if ($trimmed -match "Could not resolve hostname") {
        return "Failed to start tunnel '$ServiceName'. The SSH host alias is unknown. Verify your SSH config for the WSL host."
    }

    if ($trimmed -match "remote port forwarding failed") {
        return "Failed to start tunnel '$ServiceName'. The WSL port is already in use. Stop the conflicting tunnel or choose a different catalog mapping."
    }

    return "Failed to start tunnel '$ServiceName'. SSH said: $trimmed"
}

function Start-WslTunnelService {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Service,

        [Parameter(Mandatory = $true)]
        [string]$SshHostAlias
    )

    Assert-WslTunnelCommandRequirements

    if (-not (Test-WslTunnelWindowsPortListening -Port $Service.windowsPort)) {
        throw "Service '$($Service.name)' is not available. Nothing is listening on Windows port $($Service.windowsPort)."
    }

    $states = Get-WslTunnelServiceStates -Catalog @($Service) -SshHostAlias $SshHostAlias
    if (($states | Select-Object -First 1).Active) {
        throw "Tunnel '$($Service.name)' is already active. Run '.\wsl-tunnel.ps1 status $($Service.name)' to inspect it."
    }

    $conflict = Get-WslTunnelProcessConflict -Service $Service
    if ($conflict) {
        throw "WSL port $($Service.wslPort) is already used by another tunnel process (PID $($conflict.ProcessId)). Stop the conflicting tunnel first."
    }

    $logs = New-WslTunnelLogs -ServiceName $Service.name
    $sshArgs = @(
        "-N",
        "-o", "ExitOnForwardFailure=yes",
        "-R", "$($Service.wslPort):localhost:$($Service.windowsPort)",
        $SshHostAlias
    )

    $process = Start-Process -FilePath "ssh" -ArgumentList $sshArgs -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput $logs.StdOut -RedirectStandardError $logs.StdErr

    Start-Sleep -Milliseconds 1200
    if ($process.HasExited) {
        $rawError = ""
        if (Test-Path -LiteralPath $logs.StdErr) {
            $rawError = Get-Content -LiteralPath $logs.StdErr -Raw
        }

        Remove-WslTunnelLogs -Logs $logs
        throw (Format-WslTunnelLaunchError -ServiceName $Service.name -RawError $rawError)
    }

    Write-WslTunnelMarker -Service $Service -ProcessId $process.Id -SshHostAlias $SshHostAlias
    Remove-WslTunnelLogs -Logs $logs

    return [PSCustomObject]@{
        Service = $Service
        Pid = $process.Id
        TestCommand = (Get-WslTunnelTestCommand -Service $Service)
    }
}

function Start-WslTunnelServices {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Services,

        [Parameter(Mandatory = $true)]
        [string]$SshHostAlias
    )

    $results = New-Object System.Collections.Generic.List[object]
    foreach ($service in $Services) {
        try {
            $started = Start-WslTunnelService -Service $service -SshHostAlias $SshHostAlias
            $results.Add([PSCustomObject]@{
                Service = $service
                Success = $true
                Pid = $started.Pid
                TestCommand = $started.TestCommand
                Message = "Tunnel started."
            })
        } catch {
            $results.Add([PSCustomObject]@{
                Service = $service
                Success = $false
                Pid = $null
                TestCommand = (Get-WslTunnelTestCommand -Service $service)
                Message = $_.Exception.Message
            })
        }
    }

    return $results
}

function Stop-WslTunnelService {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Service
    )

    $states = Get-WslTunnelServiceStates -Catalog @($Service)
    $state = $states | Select-Object -First 1
    if (-not $state.Active) {
        Remove-WslTunnelMarker -ServiceName $Service.name
        return [PSCustomObject]@{
            Service = $Service
            WasActive = $false
            StoppedPids = @()
        }
    }

    foreach ($processId in $state.ProcessIds) {
        Stop-Process -Id $processId -Force
    }

    Remove-WslTunnelMarker -ServiceName $Service.name
    return [PSCustomObject]@{
        Service = $Service
        WasActive = $true
        StoppedPids = @($state.ProcessIds)
    }
}

function Show-WslTunnelList {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$States
    )

    $rows = $States | ForEach-Object {
        [PSCustomObject]@{
            Service = $_.name
            Protocol = $_.protocol
            WindowsPort = $_.windowsPort
            WslPort = $_.wslPort
            Windows = if ($_.WindowsAvailable) { "available" } else { "unavailable" }
            Tunnel = if ($_.Active) { "active" } else { "inactive" }
            Hint = $_.Hint
        }
    }

    $rows | Format-Table -AutoSize | Out-Host
}

function Show-WslTunnelSelectionMenu {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$States
    )

    $fixtureSelections = Get-WslTunnelSelectionFixture
    if ($null -ne $fixtureSelections) {
        return Resolve-WslTunnelSelectedStates -States $States -SelectedNames $fixtureSelections
    }

    if (-not (Test-WslTunnelInteractiveConsole)) {
        throw "Interactive selection requires a real console. Use '.\wsl-tunnel.ps1 up <service-name>' in non-interactive shells."
    }

    $cursor = 0
    $selectedNames = New-Object System.Collections.Generic.HashSet[string]

    while ($true) {
        Clear-Host
        Write-Host "Select services to start." -ForegroundColor Cyan
        Write-Host "Use Up/Down arrows to move, Space to toggle, Enter to confirm, Esc to cancel." -ForegroundColor DarkGray
        Write-Host ""

        for ($index = 0; $index -lt $States.Count; $index++) {
            $state = $States[$index]
            $isCursor = $index -eq $cursor
            $isSelected = $selectedNames.Contains($state.name)
            $pointer = if ($isCursor) { ">" } else { " " }
            $checkbox = if ($isSelected) { "[x]" } else { "[ ]" }

            $status = if ($state.Active) {
                "active"
            } elseif ($state.WindowsAvailable) {
                "ready"
            } else {
                "unavailable"
            }

            $line = "{0} {1} {2,-10} {3,-12} win:{4,-5} wsl:{5,-5} {6}" -f `
                $pointer, $checkbox, $state.name, $status, $state.windowsPort, $state.wslPort, $state.description

            $foreground = if ($isCursor) {
                "Cyan"
            } elseif ($state.Active) {
                "Yellow"
            } elseif (-not $state.WindowsAvailable) {
                "DarkGray"
            } else {
                "Gray"
            }

            Write-Host $line -ForegroundColor $foreground

            if (-not [string]::IsNullOrWhiteSpace($state.note)) {
                Write-Host ("      note: {0}" -f $state.note) -ForegroundColor DarkGray
            }
        }

        $key = [Console]::ReadKey($true)
        switch ($key.Key) {
            ([ConsoleKey]::UpArrow) {
                if ($cursor -gt 0) {
                    $cursor--
                } else {
                    $cursor = $States.Count - 1
                }
            }
            ([ConsoleKey]::DownArrow) {
                if ($cursor -lt ($States.Count - 1)) {
                    $cursor++
                } else {
                    $cursor = 0
                }
            }
            ([ConsoleKey]::Spacebar) {
                $currentName = $States[$cursor].name
                if ($selectedNames.Contains($currentName)) {
                    $selectedNames.Remove($currentName) | Out-Null
                } else {
                    $selectedNames.Add($currentName) | Out-Null
                }
            }
            ([ConsoleKey]::Enter) {
                if ($selectedNames.Count -eq 0) {
                    return @($States[$cursor])
                }

                $orderedNames = foreach ($state in $States) {
                    if ($selectedNames.Contains($state.name)) {
                        $state.name
                    }
                }

                return Resolve-WslTunnelSelectedStates -States $States -SelectedNames @($orderedNames)
            }
            ([ConsoleKey]::Escape) {
                return @()
            }
        }
    }
}

function Show-WslTunnelStartResults {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Results
    )

    foreach ($result in $Results) {
        if ($result.Success) {
            Write-Host "[OK] $($result.Service.name)" -ForegroundColor Green
            Write-Host "     WSL localhost:$($result.Service.wslPort) -> Windows localhost:$($result.Service.windowsPort)"
            Write-Host "     PID: $($result.Pid)"
            Write-Host "     Test from WSL: $($result.TestCommand)"
        } else {
            Write-Host "[FAIL] $($result.Service.name)" -ForegroundColor Red
            Write-Host "       $($result.Message)"
        }
    }
}

function Show-WslTunnelStatus {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$States,

        [string]$ServiceName
    )

    if ($ServiceName) {
        $state = $States | Where-Object { $_.name -eq $ServiceName } | Select-Object -First 1
        if (-not $state) {
            throw "Unknown service '$ServiceName'."
        }

        [PSCustomObject]@{
            Service = $state.name
            Protocol = $state.protocol
            WindowsPort = $state.windowsPort
            WslPort = $state.wslPort
            Tunnel = if ($state.Active) { "active" } else { "inactive" }
            Windows = if ($state.WindowsAvailable) { "available" } else { "unavailable" }
            PID = if ($state.PrimaryPid) { $state.PrimaryPid } else { "-" }
            Test = $state.TestCommand
            NextAction = $state.Hint
        } | Format-List | Out-Host

        return
    }

    $activeStates = @($States | Where-Object { $_.Active })
    if ($activeStates.Count -eq 0) {
        Write-Host "No active tunnels." -ForegroundColor Yellow
        Write-Host "Run '.\wsl-tunnel.ps1 list' to see which catalog services can be started."
        return
    }

    $activeStates | ForEach-Object {
        [PSCustomObject]@{
            Service = $_.name
            PID = $_.PrimaryPid
            Mapping = "WSL:$($_.wslPort) -> Windows:$($_.windowsPort)"
            Windows = if ($_.WindowsAvailable) { "available" } else { "unavailable" }
            Test = $_.TestCommand
            NextAction = $_.Hint
        }
    } | Format-Table -AutoSize | Out-Host
}

function Invoke-WslTunnelAction {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Action,

        [string]$ServiceName,

        [Parameter(Mandatory = $true)]
        [string]$SshHostAlias
    )

    $catalog = @(Get-WslTunnelCatalog)
    $states = @(Get-WslTunnelServiceStates -Catalog $catalog -SshHostAlias $SshHostAlias)

    switch ($Action) {
        "list" {
            Show-WslTunnelList -States $states
            return
        }
        "status" {
            if ($ServiceName) {
                Resolve-WslTunnelService -Name $ServiceName -Catalog $catalog | Out-Null
            }

            Show-WslTunnelStatus -States $states -ServiceName $ServiceName
            return
        }
        "up" {
            if (-not $ServiceName) {
                $selectedStates = @(Show-WslTunnelSelectionMenu -States $states)
                if ($selectedStates.Count -eq 0) {
                    Write-Host "No services selected." -ForegroundColor Yellow
                    return
                }

                $selectedServices = @(
                    foreach ($selectedState in $selectedStates) {
                        Resolve-WslTunnelService -Name $selectedState.name -Catalog $catalog
                    }
                )

                $results = @(Start-WslTunnelServices -Services $selectedServices -SshHostAlias $SshHostAlias)
                Show-WslTunnelStartResults -Results $results

                if ((@($results | Where-Object { -not $_.Success }).Count) -gt 0) {
                    throw "Some selected services failed to start. Review the messages above."
                }

                Write-Host "All selected tunnels are active." -ForegroundColor Green
                return
            }

            $service = Resolve-WslTunnelService -Name $ServiceName -Catalog $catalog
            $result = Start-WslTunnelService -Service $service -SshHostAlias $SshHostAlias

            Write-Host "Tunnel '$($result.Service.name)' is active." -ForegroundColor Green
            Write-Host "WSL localhost:$($result.Service.wslPort) -> Windows localhost:$($result.Service.windowsPort)"
            Write-Host "PID: $($result.Pid)"
            Write-Host "Test from WSL: $($result.TestCommand)"
            Write-Host "Stop with: .\wsl-tunnel.ps1 down $($result.Service.name)"
            return
        }
        "down" {
            if (-not $ServiceName) {
                throw "Usage: .\wsl-tunnel.ps1 down <service-name>"
            }

            $service = Resolve-WslTunnelService -Name $ServiceName -Catalog $catalog
            $result = Stop-WslTunnelService -Service $service
            if ($result.WasActive) {
                $pidList = $result.StoppedPids -join ", "
                Write-Host "Tunnel '$($result.Service.name)' stopped." -ForegroundColor Green
                Write-Host "Stopped PID(s): $pidList"
            } else {
                Write-Host "Tunnel '$($result.Service.name)' is not active." -ForegroundColor Yellow
            }
            return
        }
        default {
            throw "Unsupported action '$Action'."
        }
    }
}

if ($MyInvocation.InvocationName -ne ".") {
    try {
        Invoke-WslTunnelAction -Action $Action -ServiceName $ServiceName -SshHostAlias $SshHostAlias
    } catch {
        Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}
