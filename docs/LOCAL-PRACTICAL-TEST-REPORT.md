# Local Practical Test Report (Sanitized)

Scope: practical network behavior observed on one constrained workstation.

Method:

- one-command checks with explicit outputs
- bounded curl timeouts to keep failing paths deterministic
- raw workstation identifiers, emails, and internal IPs intentionally normalized

Placeholder values:

- `<nat-gateway-ip>` = host gateway IP seen from WSL2 in NAT mode
- `<windows-ip-a>` and `<windows-ip-b>` = tested Windows IPv4 addresses in mirrored mode
- `<wsl-ip>` = chosen WSL2 IP for container -> WSL2 checks

## Global Preconditions

### P1. Windows service on 8443

Command:

```powershell
curl.exe -vk --connect-timeout 8 --max-time 20 https://localhost:8443
```

Observed:

- HTTP `401 Unauthorized`

Status: `OK`

### P2. SSH Windows -> WSL2

Command:

```powershell
ssh wsl-localhost "echo Hello from WSL"
```

Observed:

- `Hello from WSL`

Status: `OK`

## Configuration A: NAT Baseline

Applied config:

```ini
[wsl2]
networkingMode=NAT
localhostForwarding=true
```

### Results

1. Windows -> Docker published port `8080`
- Command: `curl.exe --connect-timeout 8 --max-time 20 http://localhost:8080`
- Observed: nginx welcome page
- Status: `OK`

2. WSL2 -> Docker published port `8080`
- Command: `wsl curl --connect-timeout 8 --max-time 20 http://localhost:8080`
- Observed: nginx welcome page
- Status: `OK`

3. WSL2 -> Windows service via `localhost:8443`
- Command: `wsl curl -vk --connect-timeout 8 --max-time 20 https://localhost:8443`
- Observed: connection refused on `127.0.0.1` and `::1`
- Status: `KO`

4. WSL2 -> Windows service via `<nat-gateway-ip>:8443`
- Command: `wsl curl -vk --connect-timeout 8 --max-time 20 https://<nat-gateway-ip>:8443`
- Observed: connection timeout
- Status: `KO`

5. Container -> Windows service via `<nat-gateway-ip>:8443`
- Command: `wsl docker exec test-nginx sh -lc "curl --noproxy '*' -vk --connect-timeout 8 --max-time 20 https://<nat-gateway-ip>:8443"`
- Observed: connection timeout
- Status: `KO`

## Configuration B: NAT + Tunnel

Scope for this block:

- validate the tunnel path to the Windows service (`18443 -> 8443`)
- keep Docker `8080` behavior inherited from the NAT baseline

### Results

1. Start tunnel
- Command: `.\wsl-tunnel.ps1 up api`
- Observed: `Tunnel 'api' is active. WSL localhost:18443 -> Windows localhost:8443`
- Status: `OK`

2. WSL2 -> tunneled endpoint `localhost:18443`
- Command: `wsl curl -vk --connect-timeout 8 --max-time 20 https://localhost:18443`
- Observed: HTTP `401 Unauthorized`
- Status: `OK`

3. Tunnel listener scope
- Command: `wsl sh -lc "ss -ltn | grep 18443"`
- Observed: listeners only on `127.0.0.1:18443` and `[::1]:18443`
- Status: informational

4. Container -> tunneled endpoint via `host.docker.internal`
- Command: `wsl docker exec test-nginx sh -lc "curl --noproxy '*' -vk --connect-timeout 8 --max-time 20 https://host.docker.internal:18443"`
- Observed: name resolution failed or timed out
- Status: `KO`

5. Container -> tunneled endpoint via `<wsl-ip>:18443`
- Command: `wsl docker exec test-nginx sh -lc "curl --noproxy '*' -vk --connect-timeout 8 --max-time 20 https://<wsl-ip>:18443"`
- Observed: connection refused
- Status: `KO`

## Configuration C: Mirrored

Applied config:

```ini
[wsl2]
networkingMode=mirrored
```

### Results

1. Windows -> Docker published port `8080`
- Command: `curl.exe --connect-timeout 8 --max-time 20 http://localhost:8080`
- Observed: connection timeout or failure
- Status: `KO`

2. WSL2 -> Docker published port `8080`
- Command: `wsl curl --connect-timeout 8 --max-time 20 http://localhost:8080`
- Observed: nginx welcome page
- Status: `OK`

3. WSL2 -> Windows service via `localhost:8443`
- Command: `wsl curl -vk --connect-timeout 8 --max-time 20 https://localhost:8443`
- Observed: HTTP `401 Unauthorized`
- Status: `OK`

4. WSL2 -> Windows service via `<windows-ip-a>:8443`
- Command: `wsl curl -vk --connect-timeout 8 --max-time 20 https://<windows-ip-a>:8443`
- Observed: connection refused
- Status: `KO`

5. Windows -> native WSL2 service `4200`
- Server command: `wsl sh -lc "python3 -m http.server 4200 --bind 0.0.0.0"`
- Check command: `curl.exe --connect-timeout 8 --max-time 20 http://localhost:4200`
- Observed: Python directory listing
- Status: `OK`

6. WSL2 -> native WSL2 service `4200`
- Command: `wsl curl --connect-timeout 8 --max-time 20 http://localhost:4200`
- Observed: Python directory listing
- Status: `OK`

7. Container -> native WSL2 service `4200`
- Command: `wsl docker exec test-nginx sh -lc "curl --noproxy '*' -v --connect-timeout 8 --max-time 20 http://<wsl-ip>:4200"`
- Observed: HTTP `200 OK`
- Status: `OK`

8. Container -> Windows service via `<windows-ip-a>:8443`
- Command: `wsl docker exec test-nginx sh -lc "curl --noproxy '*' -vk --connect-timeout 8 --max-time 20 https://<windows-ip-a>:8443"`
- Observed: connection refused
- Status: `KO`

9. Container -> Windows service via `<windows-ip-b>:8443`
- Command: `wsl docker exec test-nginx sh -lc "curl --noproxy '*' -vk --connect-timeout 8 --max-time 20 https://<windows-ip-b>:8443"`
- Observed: connection refused
- Status: `KO`

10. Container -> `host.docker.internal:8443`
- Command: `wsl docker exec test-nginx sh -lc "curl --noproxy '*' -vk --connect-timeout 8 --max-time 20 https://host.docker.internal:8443"`
- Observed: name resolution failed or timed out
- Status: `KO`

## Consolidated Matrix

### NAT baseline

- Windows -> Windows service `8443`: `OK`
- Windows -> Docker `8080`: `OK`
- WSL2 -> Docker `8080`: `OK`
- WSL2 -> Windows `localhost:8443`: `KO`
- WSL2 -> Windows `<nat-gateway-ip>:8443`: `KO`
- Container -> Windows service `8443`: `KO`

### NAT + tunnel

- WSL2 -> tunneled endpoint `18443`: `OK`
- Container -> tunneled endpoint `18443`: `KO`

### Mirrored

- Windows -> Docker `8080`: `KO`
- WSL2 -> Docker `8080`: `OK`
- WSL2 -> Windows `localhost:8443`: `OK`
- WSL2 -> Windows `<windows-ip-a>:8443`: `KO`
- Windows -> WSL2 native `4200`: `OK`
- Container -> WSL2 native `4200`: `OK`
- Container -> Windows service `8443`: `KO`

## Practical Decision For This Workstation

- If priority is `Windows -> Docker published ports`, NAT remained the stable daily mode.
- If priority is native `WSL2 -> Windows service on 8443`, mirrored worked via `localhost`, and NAT + tunnel also worked.
- For containerized access to the Windows `8443` service, both tested native modes remained failing in this campaign.
- The tunnel restored the native WSL2 dependency path, but not the tested container path on this workstation.
