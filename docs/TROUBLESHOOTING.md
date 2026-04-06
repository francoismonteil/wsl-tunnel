# Troubleshooting

This guide is only for the targeted tunnel component.

If you have not already qualified the workstation and selected the tunnel as the
response path, go back to the diagnostic and validation documents first.

## Common Problems

### `up <service>` says the Windows service is not available

Symptom:

```text
ERROR: Service 'api' is not available. Nothing is listening on Windows port 8443.
```

What it means:

- the catalog entry exists
- the tunnel command is valid
- but the Windows service itself is not currently running

What to do:

```powershell
Get-NetTCPConnection -State Listen -LocalPort 8443
.\wsl-tunnel.ps1 list
```

Start the Windows service, then retry:

```powershell
.\wsl-tunnel.ps1 up api
```

### SSH access to WSL is broken

Symptom:

```text
ERROR: Failed to start tunnel 'api'. SSH authentication was rejected.
```

or:

```text
ERROR: Failed to start tunnel 'api'. The SSH host alias is unknown.
```

What to do:

```powershell
ssh wsl-localhost "echo Hello from WSL"
```

If that fails, repair SSH first. The guided tool depends on working Windows -> WSL SSH.

### The tunnel is already active

Symptom:

```text
ERROR: Tunnel 'api' is already active.
```

What to do:

```powershell
.\wsl-tunnel.ps1 status api
.\wsl-tunnel.ps1 down api
```

### WSL port conflict

Symptom:

```text
ERROR: WSL port 18443 is already used by another tunnel process.
```

What it means:

- another managed tunnel already occupies the same remote WSL port
- or a conflicting SSH process is already running

What to do:

```powershell
.\wsl-tunnel.ps1 status
```

Stop the conflicting tunnel, then retry.

### Tunnel is active but the service stopped later

Symptom from `status`:

- tunnel shows as `active`
- Windows shows as `unavailable`

What it means:

The SSH process is still alive, but the Windows service behind it stopped.

What to do:

- restart the Windows service
- or stop the tunnel if you no longer need it

### HTTPS certificate issues in WSL

Symptom:

```text
curl: (60) SSL certificate problem: self signed certificate
```

What to do for local development:

```bash
curl -k https://localhost:18443
```

### Script execution is blocked

Symptom:

```text
File cannot be loaded because running scripts is disabled on this system.
```

What to do:

```powershell
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process
```

Then rerun the tunnel command.

### Interactive picker does not open

Symptom:

```text
ERROR: Interactive selection requires a real console.
```

What it means:

- `.\wsl-tunnel.ps1 up` was launched from a non-interactive shell or redirected context

What to do:

- run it directly in a PowerShell console window
- or start a service explicitly with `.\wsl-tunnel.ps1 up <service>`

## Recommended Diagnostic Flow

1. Run `.\wsl-tunnel.ps1 list`
2. Confirm the target service is `available`
3. Run `.\wsl-tunnel.ps1 up <service>`
4. If it fails, verify `ssh wsl-localhost`
5. Run `.\wsl-tunnel.ps1 status <service>`
6. Test from WSL with the command shown by the tool

This flow helps only after the tunnel path has already been selected. It does
not determine whether the tunnel should have been selected in the first place.

## Deep Checks

### Check Windows listening ports

```powershell
Get-NetTCPConnection -State Listen | Select-Object LocalAddress, LocalPort
```

### Check WSL health

```powershell
wsl --version
wsl --list -v
```

### Check SSH daemon inside WSL

```bash
sudo service ssh status
sudo service ssh restart
```

## Still Stuck?

Collect:

- `.\wsl-tunnel.ps1 list`
- `.\wsl-tunnel.ps1 status`
- the exact error message
- `ssh wsl-localhost "echo Hello from WSL"`
- Windows version and WSL version

Then share that information with the team or in an issue.
