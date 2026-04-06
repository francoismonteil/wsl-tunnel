# Setup Guide

This guide covers the targeted tunnel component included in the repository's
broader mixed-mode Windows + WSL2 + Docker investigation.

It is not the repository-wide starting point. Use the diagnostic and validation
matrix first to decide whether this component applies to your workstation.

## Prerequisites

### Windows
- Windows 10 build 19041+ or Windows 11
- WSL2 installed and running
- OpenSSH client available in `PATH`

### WSL
- Any modern Linux distribution
- SSH daemon reachable from Windows

### Team Files
- `wsl-tunnel.ps1`
- `catalog/tunnels.json`

## Step 1: Verify Windows -> WSL SSH

From Windows PowerShell:

```powershell
ssh wsl-localhost "echo Hello from WSL"
```

Expected output:

```text
Hello from WSL
```

If this fails, fix SSH first. The tunnel tool expects WSL SSH access to already work.

## Step 2: Review the Catalog

List every team-supported service:

```powershell
.\wsl-tunnel.ps1 list
```

Expected behavior:

- every known service is shown
- the tool tells you whether the Windows port is available now
- the tool tells you whether a tunnel is already active
- the tool tells you the next useful action

## Step 3: Start a Named Tunnel

Example for the `api` service:

```powershell
.\wsl-tunnel.ps1 up api
```

Or open the interactive selector:

```powershell
.\wsl-tunnel.ps1 up
```

Interactive controls:

- arrow keys to move
- `Space` to check or uncheck a service
- `Enter` to confirm
- `Esc` to cancel

Expected output:

```text
Tunnel 'api' is active.
WSL localhost:18443 -> Windows localhost:8443
PID: 12345
Test from WSL: curl -k https://localhost:18443
Stop with: .\wsl-tunnel.ps1 down api
```

The developer chooses the service name. The catalog provides the ports.

## Step 4: Verify from WSL

The tool prints the right test command for each protocol. Typical examples:

```bash
curl -k https://localhost:18443
curl http://localhost:18080
redis-cli -h localhost -p 16379
psql -h localhost -p 15432 -U user -d mydb
```

## Step 5: Inspect Active Tunnels

See all active tunnels:

```powershell
.\wsl-tunnel.ps1 status
```

Inspect one named tunnel:

```powershell
.\wsl-tunnel.ps1 status api
```

## Step 6: Stop a Tunnel

```powershell
.\wsl-tunnel.ps1 down api
```

Expected output:

```text
Tunnel 'api' stopped.
Stopped PID(s): 12345
```

## Multi-Tunnel Workflow

Different catalog services can run at the same time:

```powershell
.\wsl-tunnel.ps1 up api
.\wsl-tunnel.ps1 up jobs
.\wsl-tunnel.ps1 status
```

You can also select several services in one pass from the interactive picker by checking multiple rows before pressing `Enter`.

Each service has one managed active tunnel at a time, identified by its catalog name.

## Catalog Ownership

The team owns `catalog/tunnels.json`. Developers should not invent ports locally. Add or change mappings in the catalog so everyone uses the same names and ports.

---

Next: read [ARCHITECTURE.md](ARCHITECTURE.md) for the runtime model and [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for failure recovery.
