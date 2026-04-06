# Architecture

## High-Level Role

This document describes the targeted tunnel component inside the repository's
broader mixed-mode Windows + WSL2 + Docker investigation.

It is not the architecture of every supported workstation shape in this
repository. It only describes the internal model of the tunnel component when
that response path is selected.

The tool sits above the raw SSH command line and provides a guided way to expose
Windows-hosted services inside WSL2 when that specific flow remains unsupported
by the chosen native mode.

It is designed for a specific local-development gap:

- WSL2 networking mode is not enough on its own
- developers still need a stable path from WSL2 to Windows-hosted services

## CLI Contract

The developer-facing contract is a single CLI:

```powershell
.\wsl-tunnel.ps1 list
.\wsl-tunnel.ps1 up api
.\wsl-tunnel.ps1 up
.\wsl-tunnel.ps1 down api
.\wsl-tunnel.ps1 status
```

The CLI is backed by a versioned catalog in `catalog/tunnels.json`.

## Tunnel Model

The underlying mechanism is SSH remote port forwarding:

```text
Windows                              WSL2
   |                                  |
   +---- ssh -N -R 18443:localhost:8443 ---->

Result:
WSL2 localhost:18443 -> Windows localhost:8443
```

So a Windows-hosted service becomes reachable inside WSL2 through a stable local port.

## Why The Direction Matters

This project is intentionally built around:

- Windows initiating the SSH connection
- WSL2 receiving the forwarded port

That direction matters because the missing path in the target environment is usually:

- WSL2 -> Windows service

The tunnel gives WSL2 a local endpoint that forwards back to Windows.

## Runtime State

The tool keeps lightweight runtime markers outside the repository:

```text
%LOCALAPPDATA%\wsl-tunnel\active\<service>.json
```

Markers store:

- service name
- current PID
- Windows port
- WSL port
- SSH host alias
- creation timestamp

They are convenience state, not the source of truth.

## Source of Truth

Live `ssh` processes are the source of truth.

The tool inspects process command lines and parses:

```text
-R <wslPort>:localhost:<windowsPort>
```

That allows it to:

- map a running tunnel back to a catalog entry
- detect stale markers
- rebuild missing markers
- prevent accidental duplicates

## Command Behavior

### `list`

Shows every known service and computes:

- whether the Windows service is listening now
- whether a tunnel is already active
- what action the developer should take next

### `up <service>`

Validates:

- the service exists in the catalog
- the Windows port is listening
- the service is not already active
- the target WSL port is not already used by another tunnel

Then it launches:

```text
ssh -N -o ExitOnForwardFailure=yes -R <wslPort>:localhost:<windowsPort> <sshHostAlias>
```

### `up`

Opens the interactive selector:

- arrow keys move
- `Space` toggles checkboxes
- `Enter` confirms
- `Esc` cancels

### `down <service>`

Stops only the tunnel for the named service.

### `status`

Shows active tunnels globally or details for one service.

## Why This Design Helps Teams

- the workaround stays explicit
- the hard networking details stay hidden
- multiple tunnels stay distinguishable by service name
- the state is easy to inspect and easy to reverse
