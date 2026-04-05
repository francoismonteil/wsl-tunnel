# Example: Basic HTTPS API

This example shows how to expose an HTTPS API running on Windows:8443 to WSL as localhost:18443 through the guided catalog-based CLI.

## Setup

1. Ensure your Windows service is running on port 8443
2. Confirm the catalog contains `api`
3. Run the guided command:

```powershell
cd C:\path\to\wsl-windows-lab
.\wsl-tunnel.ps1 up api
```

## Test from WSL

```bash
# Basic connectivity
curl -k https://localhost:18443

# With auth header (example)
curl -k -H "Authorization: Bearer TOKEN" https://localhost:18443/api/v1

# POST with JSON
curl -k -X POST https://localhost:18443/api/users \
  -H "Content-Type: application/json" \
  -d '{"username":"test","role":"admin"}'
```

## Stop

```powershell
.\wsl-tunnel.ps1 down api
```

The developer still decides when the tunnel exists, but the catalog removes the manual SSH and port work.
