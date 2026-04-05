# Local Practical Tests

Purpose: run practical, reproducible network checks on one workstation and record raw facts only.

Rules:

- Run one step at a time.
- Record the exact command and the exact output or error.
- Mark status only as `OK`, `KO`, `NR`, or `N/A`.
- Do not infer beyond observed evidence.
- Replace placeholder IPs with the values discovered on the machine under test.

## Machine Snapshot

Fill once at session start.

```text
Date:
Windows version:
WSL version:
Distribution:
PowerShell version:
Docker engine version in WSL:
```

Commands:

```powershell
wsl --version
wsl --list -v
$PSVersionTable.PSVersion.ToString()
wsl docker version
```

## Status Legend

- `OK` = explicitly validated and works
- `KO` = explicitly validated and fails
- `NR` = not run yet
- `N/A` = intentionally out of scope

## Compact Matrix Log

```text
Configuration | Flow | Status | Command | Observed output
```

Use this compact list of flows:

1. Windows -> Windows service `8443`
2. Windows -> Docker published port `8080`
3. Windows -> native WSL2 service `4200`
4. WSL2 -> Docker published port `8080`
5. WSL2 -> Windows service via `localhost:8443`
6. WSL2 -> Windows service via Windows host IP `:8443`
7. Container -> native WSL2 service `:4200`
8. Container -> Windows service `:8443`
9. WSL2 -> Windows service via tunnel endpoint `localhost:18443`
10. Container -> tunneled endpoint `:18443`

## Pre-checks

### P1. Windows service health on 8443

```powershell
curl.exe -vk --connect-timeout 8 --max-time 20 https://localhost:8443
```

Record:

```text
Status:
Observed output:
```

### P2. Windows -> WSL SSH prerequisite

```powershell
ssh wsl-localhost "echo Hello from WSL"
```

Record:

```text
Status:
Observed output:
```

## Configuration A: NAT Baseline

Expected `.wslconfig` block:

```ini
[wsl2]
networkingMode=NAT
localhostForwarding=true
```

Apply and restart:

```powershell
wsl --shutdown
wsl --list -v
```

### A1. Start Docker test container

```powershell
wsl docker rm -f test-nginx 2>$null
wsl docker run --rm -d --name test-nginx -p 8080:80 nginx:alpine
wsl docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

### A2. Windows -> Docker published port

```powershell
curl.exe --connect-timeout 8 --max-time 20 http://localhost:8080
```

### A3. WSL -> Docker published port

```powershell
wsl curl --connect-timeout 8 --max-time 20 http://localhost:8080
```

### A4. WSL -> Windows service via localhost

```powershell
wsl curl -vk --connect-timeout 8 --max-time 20 https://localhost:8443
```

### A5. Discover the NAT gateway IP seen from WSL and test it

```powershell
wsl sh -lc "ip route show default | awk '{print `$3}'"
wsl curl -vk --connect-timeout 8 --max-time 20 https://<nat-gateway-ip>:8443
```

### A6. Container -> Windows service via NAT gateway IP

```powershell
wsl docker exec test-nginx sh -lc "apk add --no-cache curl >/dev/null 2>&1 || true; HTTPS_PROXY= HTTP_PROXY= https_proxy= http_proxy= ALL_PROXY= all_proxy= NO_PROXY='*' no_proxy='*' curl --noproxy '*' -vk --connect-timeout 8 --max-time 20 https://<nat-gateway-ip>:8443"
```

## Configuration B: NAT + Tunnel

Scope: validate the missing `8443` dependency path while keeping NAT behavior for Docker.

### B1. Ensure a clean tunnel state

```powershell
.\wsl-tunnel.ps1 down api
```

### B2. Start the tunnel

```powershell
.\wsl-tunnel.ps1 up api
.\wsl-tunnel.ps1 status api
```

### B3. Validate the tunneled endpoint from WSL2

```powershell
wsl curl -vk --connect-timeout 8 --max-time 20 https://localhost:18443
```

### B4. Check listener scope in WSL2

```powershell
wsl sh -lc "ss -ltn | grep 18443"
```

### B5. Container -> tunneled endpoint via `host.docker.internal`

```powershell
wsl docker exec test-nginx sh -lc "apk add --no-cache curl >/dev/null 2>&1 || true; HTTPS_PROXY= HTTP_PROXY= https_proxy= http_proxy= ALL_PROXY= all_proxy= NO_PROXY='*' no_proxy='*' curl --noproxy '*' -vk --connect-timeout 8 --max-time 20 https://host.docker.internal:18443"
```

### B6. Container -> tunneled endpoint via WSL2 IP

```powershell
wsl hostname -I
wsl docker exec test-nginx sh -lc "apk add --no-cache curl >/dev/null 2>&1 || true; HTTPS_PROXY= HTTP_PROXY= https_proxy= http_proxy= ALL_PROXY= all_proxy= NO_PROXY='*' no_proxy='*' curl --noproxy '*' -vk --connect-timeout 8 --max-time 20 https://<wsl-ip>:18443"
```

### B7. Stop the tunnel

```powershell
.\wsl-tunnel.ps1 down api
```

## Configuration C: Mirrored

Expected `.wslconfig` block:

```ini
[wsl2]
networkingMode=mirrored
```

Apply and restart:

```powershell
wsl --shutdown
wsl --list -v
```

### C1. Start Docker test container

```powershell
wsl docker rm -f test-nginx 2>$null
wsl docker run --rm -d --name test-nginx -p 8080:80 nginx:alpine
wsl docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

### C2. Windows -> Docker published port

```powershell
curl.exe --connect-timeout 8 --max-time 20 http://localhost:8080
```

### C3. WSL -> Docker published port

```powershell
wsl curl --connect-timeout 8 --max-time 20 http://localhost:8080
```

### C4. WSL -> Windows service via localhost

```powershell
wsl curl -vk --connect-timeout 8 --max-time 20 https://localhost:8443
```

### C5. Discover candidate Windows IPs and test one

```powershell
Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notmatch '^(127|169\.254)\.' -and $_.PrefixOrigin -ne 'WellKnown' } | Sort-Object InterfaceMetric | Select-Object -First 10 InterfaceAlias,IPAddress
wsl curl -vk --connect-timeout 8 --max-time 20 https://<windows-ip-a>:8443
```

### C6. Start a native WSL2 HTTP server on 4200

```powershell
wsl sh -lc "python3 -m http.server 4200 --bind 0.0.0.0"
```

### C7. Windows -> native WSL2 service

```powershell
curl.exe --connect-timeout 8 --max-time 20 http://localhost:4200
```

### C8. Container -> native WSL2 service

```powershell
wsl hostname -I
wsl docker exec test-nginx sh -lc "apk add --no-cache curl >/dev/null 2>&1 || true; HTTPS_PROXY= HTTP_PROXY= https_proxy= http_proxy= ALL_PROXY= all_proxy= NO_PROXY='*' no_proxy='*' curl --noproxy '*' -v --connect-timeout 8 --max-time 20 http://<wsl-ip>:4200"
```

### C9. Container -> Windows service via chosen Windows IP

```powershell
wsl docker exec test-nginx sh -lc "apk add --no-cache curl >/dev/null 2>&1 || true; HTTPS_PROXY= HTTP_PROXY= https_proxy= http_proxy= ALL_PROXY= all_proxy= NO_PROXY='*' no_proxy='*' curl --noproxy '*' -vk --connect-timeout 8 --max-time 20 https://<windows-ip-a>:8443"
```

### C10. Optional fallback name test from the container

```powershell
wsl docker exec test-nginx sh -lc "apk add --no-cache curl >/dev/null 2>&1 || true; HTTPS_PROXY= HTTP_PROXY= https_proxy= http_proxy= ALL_PROXY= all_proxy= NO_PROXY='*' no_proxy='*' curl --noproxy '*' -vk --connect-timeout 8 --max-time 20 https://host.docker.internal:8443"
```

## Final Summary Block

```text
NAT baseline:
- Key wins:
- Key failures:

NAT + tunnel:
- Key wins:
- Key failures:

Mirrored:
- Key wins:
- Key failures:

Decision for this workstation:
- Recommended daily mode:
- Need tunnel script: Yes / No / Partial
- Known limitations:
```
