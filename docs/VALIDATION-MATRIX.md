# Validation Matrix

This document captures the test cases used to validate whether WSL2 networking modes are sufficient on their own, and where they fall short for real development workflows.

The goal is not to prove a theory in advance. The goal is to record what actually works and what does not on constrained workstations.

## What We Are Validating

We care about the concrete paths that matter for day-to-day development:

1. Windows -> native process running in WSL2
2. Windows -> Docker container running inside WSL2
3. WSL2 native process -> Docker published port inside WSL2
4. WSL2 native process -> service hosted on Windows via `localhost`
5. WSL2 native process -> service hosted on Windows via the Windows host IP
6. Docker container inside WSL2 -> native WSL2 service
7. Docker container inside WSL2 -> service hosted on Windows
8. WSL2 native process -> Windows-hosted service through the SSH tunnel workaround
9. Docker container inside WSL2 -> tunneled endpoint exposed inside WSL2

If a given WSL2 networking mode solves only some of these paths, then it does not fully solve the local development problem.

## Test Fixtures

Use simple, reproducible fixtures before testing any business application:

- Windows-hosted HTTPS service on `8443`
- Native WSL2 HTTP server on `4200`
- Docker container published as `8080:80` with `nginx:alpine`
- Guided tunnel from `18443` in WSL2 back to Windows `8443`
- Optional realistic services such as Elasticsearch after the trivial fixtures are validated

## Reference Commands

### Native WSL2 HTTP server

```bash
python3 -m http.server 4200 --bind 0.0.0.0
```

### Simple container in WSL2

```bash
docker run --rm -d --name test-nginx -p 8080:80 nginx:alpine
```

### Docker port check

```bash
docker ps
docker port test-nginx
```

Expected mapping:

```text
80/tcp -> 0.0.0.0:8080
```

### Windows access checks

```powershell
curl.exe --connect-timeout 8 --max-time 20 http://localhost:4200
curl.exe --connect-timeout 8 --max-time 20 http://localhost:8080
curl.exe -vk --connect-timeout 8 --max-time 20 https://localhost:8443
```

### WSL2 access checks

```bash
curl --connect-timeout 8 --max-time 20 http://localhost:4200
curl --connect-timeout 8 --max-time 20 http://localhost:8080
curl -vk --connect-timeout 8 --max-time 20 https://localhost:8443
curl -vk --connect-timeout 8 --max-time 20 https://<windows-host-ip>:8443
curl -vk --connect-timeout 8 --max-time 20 https://localhost:18443
```

### Container access checks

```bash
docker exec test-nginx sh -lc "apk add --no-cache curl >/dev/null 2>&1 || true; curl --noproxy '*' -vk --connect-timeout 8 --max-time 20 https://<target>"
```

## Configurations Under Test

### Configuration A

```ini
[wsl2]
networkingMode=NAT
localhostForwarding=true
```

This is the NAT baseline used to preserve Windows -> WSL2 and Windows -> Docker localhost flows where possible.

### Configuration B

```ini
[wsl2]
networkingMode=mirrored
```

This is the mirrored networking mode.

### Configuration C

```ini
[wsl2]
networkingMode=NAT
localhostForwarding=true
```

Plus the guided SSH reverse tunnel from this repository for the Windows service under test.

This is the "keep NAT working for Docker, then patch the missing Windows dependency path with an explicit tunnel" configuration.

## Observed Results

The table below records only what has already been explicitly validated.

Legend:

- `OK` = explicitly validated and works
- `KO` = explicitly validated and fails
- `NR` = not yet recorded on the constrained workstation
- `N/A` = not applicable for that configuration block

| Flow | NAT + `localhostForwarding=true` | Mirrored | NAT + tunnel workaround | Notes |
|------|----------------------------------|----------|-------------------------|-------|
| Windows -> native WSL2 service | NR | OK | N/A | Native WSL2 `4200` was explicitly recorded in mirrored mode. |
| Windows -> Docker published port | OK | KO | N/A | `nginx:alpine` published as `8080:80` is reachable from Windows in NAT, but not in mirrored mode. |
| WSL2 -> Docker published port | OK | OK | N/A | The published container remains reachable from inside WSL2 in both tested modes. |
| Windows -> Windows service on `8443` | OK | N/A | N/A | Baseline health check of the Windows-hosted dependency. |
| WSL2 -> Windows service via `localhost:8443` | KO | OK | N/A | NAT fails on localhost. Mirrored succeeds on localhost. |
| WSL2 -> Windows service via Windows host IP | KO | KO | N/A | The tested Windows host IP path failed in both recorded modes. |
| Container -> native WSL2 service | NR | OK | N/A | Recorded from the test container to the native WSL2 `4200` service in mirrored mode. |
| Container -> Windows service on `8443` | KO | KO | N/A | Direct container access to the Windows service failed in both tested modes. |
| WSL2 -> Windows service via tunnel endpoint | N/A | N/A | OK | `localhost:18443` restored the missing native WSL2 -> Windows dependency path. |
| Container -> tunneled endpoint | N/A | N/A | KO | Tested routes to `18443` from the container were unsuccessful. |

## Sanitized Field Record

The block below summarizes one constrained workstation without publishing raw machine identifiers, organization-specific data, or internal IP addresses.

Placeholder values:

- `<nat-gateway-ip>` = the host gateway IP seen from WSL2 in NAT mode
- `<windows-ip-a>` and `<windows-ip-b>` = Windows IPv4 addresses tested in mirrored mode
- `<wsl-ip>` = the WSL2 address chosen for container -> WSL2 checks

### Configuration A: NAT baseline

```text
Flows:
- Windows -> Docker published port: OK
- WSL -> Docker published port: OK
- WSL -> Windows localhost service: KO
- WSL -> Windows host IP service: KO
- Container -> Windows service: KO

Evidence:
- Windows service health check: curl.exe -vk --connect-timeout 8 --max-time 20 https://localhost:8443
- Observed response: HTTP 401 Unauthorized
- Docker test container start: wsl docker run --rm -d --name test-nginx -p 8080:80 nginx:alpine
- Windows -> Docker published port: curl.exe --connect-timeout 8 --max-time 20 http://localhost:8080
- Observed response: default nginx welcome page
- WSL -> Docker published port: wsl curl --connect-timeout 8 --max-time 20 http://localhost:8080
- Observed response: default nginx welcome page
- WSL localhost path: wsl curl -vk --connect-timeout 8 --max-time 20 https://localhost:8443
- Observed response: connection refused to 127.0.0.1 and ::1
- WSL host IP path: wsl curl -vk --connect-timeout 8 --max-time 20 https://<nat-gateway-ip>:8443
- Observed response: connection timeout
- Container -> Windows service path: wsl docker exec test-nginx sh -lc "curl --noproxy '*' -vk --connect-timeout 8 --max-time 20 https://<nat-gateway-ip>:8443"
- Observed response: connection timeout
```

### Configuration B: NAT + tunnel workaround

```text
Flows:
- WSL -> Windows service via tunnel endpoint: OK
- Container -> tunneled endpoint: KO

Evidence:
- SSH prerequisite: ssh wsl-localhost "echo Hello from WSL"
- Observed response: Hello from WSL
- Tunnel start: .\wsl-tunnel.ps1 up api
- Observed response: Tunnel 'api' is active. WSL localhost:18443 -> Windows localhost:8443
- WSL tunneled path: wsl curl -vk --connect-timeout 8 --max-time 20 https://localhost:18443
- Observed response: HTTP 401 Unauthorized
- Listener check in WSL: wsl sh -lc "ss -ltn | grep 18443"
- Observed response: listeners only on 127.0.0.1:18443 and [::1]:18443
- Container -> tunneled endpoint via host.docker.internal: name resolution failed or timed out
- Container -> tunneled endpoint via <wsl-ip>:18443: connection refused
```

### Configuration C: mirrored

```text
Flows:
- Windows -> native WSL2 service: OK
- Windows -> Docker published port: KO
- WSL -> Docker published port: OK
- WSL -> Windows localhost service: OK
- WSL -> Windows host IP service: KO
- Container -> native WSL2 service: OK
- Container -> Windows service: KO

Evidence:
- Native WSL2 HTTP server during test: wsl sh -lc "python3 -m http.server 4200 --bind 0.0.0.0"
- Windows -> WSL native: curl.exe --connect-timeout 8 --max-time 20 http://localhost:4200
- Observed response: Python directory listing page
- Windows -> Docker published port: curl.exe --connect-timeout 8 --max-time 20 http://localhost:8080
- Observed response: connection timeout or failure
- WSL -> Docker published port: wsl curl --connect-timeout 8 --max-time 20 http://localhost:8080
- Observed response: default nginx welcome page
- WSL -> Windows localhost service: wsl curl -vk --connect-timeout 8 --max-time 20 https://localhost:8443
- Observed response: HTTP 401 Unauthorized
- WSL -> Windows service via <windows-ip-a>:8443
- Observed response: connection refused
- Container -> WSL native via <wsl-ip>:4200
- Observed response: HTTP 200 OK from the Python server
- Container -> Windows service via <windows-ip-a>:8443
- Observed response: connection refused
- Container -> Windows service via <windows-ip-b>:8443
- Observed response: connection refused
- Container -> host.docker.internal:8443
- Observed response: host resolution failed or timed out
```

## Current Conclusions

### What NAT solves

- Windows can reach published Docker ports in WSL2
- WSL2 can reach published Docker ports in WSL2

### What NAT does not solve in the constrained setup

- WSL2 cannot reach the Windows-hosted service on `8443` using `localhost`
- WSL2 also cannot reach the same Windows-hosted service through the tested Windows host IP path
- Containers inside WSL2 also fail to reach that Windows-hosted service

### What mirrored solves

- Windows can reach native WSL2 services
- WSL2 can reach the Windows-hosted `8443` service through `localhost`
- Containers can reach a native WSL2 service through a tested WSL2 IP

### What mirrored breaks in the currently observed setup

- Windows can no longer reach published Docker ports in WSL2, even though:
  - the container is healthy
  - the port mapping is visible
  - the service remains reachable from inside WSL2
- Direct container -> Windows service access still failed on the tested Windows IP paths

### What the tunnel workaround currently solves

- It restores a working native WSL2 -> Windows service path on `localhost:18443` while staying in NAT mode

### What the tunnel workaround does not yet solve

- The tested container -> tunneled endpoint routes were not successful on the recorded workstation

## Why This Matters

These observations suggest that no tested configuration currently solves the full local development problem:

- NAT keeps Windows -> Docker working, but leaves WSL2 and containers unable to consume the Windows-hosted dependency
- Mirrored fixes the native WSL2 -> Windows localhost path, but breaks Windows -> Docker published ports
- NAT + tunnel restores the native WSL2 dependency path, but the tested container -> tunnel routes remain unresolved

That gap is the reason this project still exists as a possible workaround.

## Highest-Value Remaining Checks

If the goal is to decide whether this project is worth keeping, the missing validations are not all equal. The checks below have the highest decision value:

1. Repeat the mirrored Windows -> Docker published-port failure with a second trivial container and a second port.
2. Re-run the NAT + tunnel container path with an intentionally reachable container-facing endpoint instead of only loopback-bound listeners.
3. Repeat the decisive cases on a second constrained workstation.
4. Add one realistic service after the trivial fixtures, such as Elasticsearch, only after the simple matrix is stable.

## Suggested Execution Order

Run the remaining checks in this order so each new result meaningfully narrows the decision:

1. NAT baseline: confirm again that `WSL2 -> Windows service` is still `KO` on both `localhost` and host IP.
2. NAT + tunnel: start `.\wsl-tunnel.ps1 up api` and validate `curl -k https://localhost:18443` from WSL2.
3. NAT + tunnel: test the container path again, but document exactly which address was used and whether the tunnel listener is reachable outside loopback.
4. Mirrored: repeat Windows -> Docker published-port tests with a second trivial container and a second port.
5. Re-run the decisive checks on a second workstation.

## Workstation Record Template

Create one record block per workstation and keep the evidence close to the result.

```text
Workstation:
- Name: sanitized workstation label
- Windows version:
- WSL version:
- Docker engine version in WSL:
- Date:

Configuration:
- NAT + localhostForwarding=true
- or mirrored
- or NAT + tunnel workaround

Flows:
- Windows -> WSL native: OK / KO / NR / N/A
- Windows -> Docker published port: OK / KO / NR / N/A
- WSL -> Docker published port: OK / KO / NR / N/A
- WSL -> Windows localhost service: OK / KO / NR / N/A
- WSL -> Windows host IP service: OK / KO / NR / N/A
- Container -> WSL native: OK / KO / NR / N/A
- Container -> Windows service: OK / KO / NR / N/A
- WSL -> Windows service via tunnel endpoint: OK / KO / NR / N/A
- Container -> tunneled endpoint: OK / KO / NR / N/A

Evidence:
- command used
- exact response or exact error
- Docker port mapping shown
- if tunnel used: command used to start it and endpoint tested
```

## Reporting Format

When recording a new workstation or a new configuration, use this format:

```text
Configuration:
- NAT + localhostForwarding=true
- or mirrored
- or NAT + tunnel workaround

Flows:
- Windows -> WSL native: OK / KO / NR / N/A
- Windows -> Docker published port: OK / KO / NR / N/A
- WSL -> Docker published port: OK / KO / NR / N/A
- WSL -> Windows localhost service: OK / KO / NR / N/A
- WSL -> Windows host IP service: OK / KO / NR / N/A
- Container -> WSL native: OK / KO / NR / N/A
- Container -> Windows service: OK / KO / NR / N/A
- WSL -> Windows service via tunnel endpoint: OK / KO / NR / N/A
- Container -> tunneled endpoint: OK / KO / NR / N/A

Evidence:
- command used
- exact error or response
- port mapping shown by Docker
- if tunnel used: command used to start it and endpoint tested
```
