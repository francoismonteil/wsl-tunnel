# Solution Plan - Execution Report

Date: 2026-04-05  
Scope: execution of the investigation tracks defined in `docs/SOLUTION-PLAN.md`  
Run mode: self-directed

---

## Scope

This report captures one solution-focused campaign on a constrained workstation.

It is sanitized for public publication:

- workstation identifiers are removed
- internal IP addresses are replaced with placeholders
- internal proxy hostnames and domains are generalized
- local temp paths are normalized

Placeholder values used in this report:

- `<wsl-ip>` = primary WSL2 IP used during the session
- `<nat-gateway-ip>` = Windows host gateway IP seen from WSL2 in NAT mode
- `<bridge-gateway-ip>` = Docker bridge gateway reachable from bridge-mode containers
- `<corp-proxy-host>` = proxy hostname exposed in container environment variables

---

## Context And Starting Point

The previous validation campaign in `docs/VALIDATION-REPORT-2026-04-05.md` established this baseline:

| Flow | NAT | Mirrored | NAT + tunnel |
|------|-----|----------|--------------|
| F2 - Windows -> Docker published port | `OK` | `KO` | `N/A` |
| F4 - WSL2 -> Windows localhost | `KO` | network `OK` | `N/A` |
| F8 - WSL2 -> Windows via tunnel | `N/A` | `N/A` | `OK` |
| F9 - Container -> tunneled endpoint | `N/A` | `N/A` | `KO` |

The open question was:

Can `F9` be solved, and if so, how?

---

## Machine Snapshot

| Property | Value |
|----------|-------|
| Date | 2026-04-05 |
| Windows version | 10.0.26100.8037 |
| WSL version | 2.6.3.0 |
| WSL kernel | 6.6.87.2-1 |
| Distribution | Ubuntu (WSL2) |
| PowerShell version | 5.1.26100.7920 |
| Docker Engine in WSL2 | 27.0.1 |

### Active `.wslconfig` at session start

```ini
[wsl2]
swap = 0
autoProxy=false
networkingMode=NAT
localhostForwarding=true
```

### Network addresses discovered

| Role | Value |
|------|-------|
| WSL2 primary IP | `<wsl-ip>` |
| NAT gateway | `<nat-gateway-ip>` |
| Docker bridge gateway | `<bridge-gateway-ip>` |

---

## Preconditions

### Windows service on 8443

The Windows HTTPS service was absent at campaign start.

Command:

```powershell
curl.exe -sk --connect-timeout 8 --max-time 15 https://localhost:8443 `
  -w "HTTP=%{http_code} ERR=%{errormsg}" -o NUL
```

Observed:

```text
HTTP=000 ERR=Failed to connect to localhost port 8443
```

To satisfy the tunnel guardrail without requiring administrator rights, a minimal raw TCP listener was created on Windows for the campaign.

Verification:

```powershell
Get-NetTCPConnection -State Listen -LocalPort 8443
```

Observed:

```text
LocalAddress  LocalPort  State
0.0.0.0       8443       Listen
```

This fixture was enough to validate routing and tunnel behavior. Because it was not a real HTTPS server, successful TCP routing later appeared as TLS handshake errors rather than HTTP responses.

### SSH Windows -> WSL2

Command:

```powershell
ssh wsl-localhost "echo Hello from WSL"
```

Observed:

```text
Hello from WSL
```

Status: `OK`

### Docker test container

Command:

```powershell
wsl docker run --rm -d --name test-nginx -p 8080:80 nginx:alpine
```

Observed:

```text
0.0.0.0:8080->80/tcp
```

Status: `OK`

---

## Track 1 - Confirm The Container Limitation Source

Goal:

- determine whether `F9` failed because the tunnel listened only on WSL2 loopback
- determine whether the enterprise environment added a second blocker

### Test 1.1 - Inspect tunnel listener scope

After starting the tunnel:

```powershell
.\wsl-tunnel.ps1 up api
```

Observed:

```text
Tunnel 'api' is active.
WSL localhost:18443 -> Windows localhost:8443
PID: <ssh-pid>
```

Listener inspection:

```powershell
wsl ss -ltn
```

Observed:

```text
LISTEN  0  128  127.0.0.1:18443  0.0.0.0:*
LISTEN  0  128      [::1]:18443     [::]:*
```

Finding:

The SSH reverse forward bound only to loopback inside WSL2.

Status: confirmed

This is the first structural blocker for `F9`.

### Test 1.2 - Add a non-loopback relay in WSL2

A `socat` relay was started in WSL2 to expose the tunnel beyond loopback:

```bash
socat TCP-LISTEN:28443,fork,bind=0.0.0.0,reuseaddr TCP:127.0.0.1:18443
```

Listener confirmation:

```text
LISTEN  0  5    0.0.0.0:28443  0.0.0.0:*   # socat relay
LISTEN  0  128  127.0.0.1:18443  0.0.0.0:* # SSH tunnel
```

Test from the bridge-mode container through the Docker bridge gateway:

```bash
wsl docker exec test-nginx curl --noproxy '*' -sk --connect-timeout 8 --max-time 12 \
  https://<bridge-gateway-ip>:28443 -w 'CODE=%{http_code} EXIT=%{exitcode} ERR=%{errormsg}' -o /dev/null
```

Observed:

```text
CODE=000 EXIT=35 ERR=TLS connect error: wrong version number
```

Verbose run showed:

```text
* Trying <bridge-gateway-ip>:28443...
* TLS handshake started
* TLS connect error: wrong version number
```

Interpretation:

- exit code `35` is an SSL handshake error, not a TCP routing failure
- the container successfully reached the relay
- the relay successfully reached the SSH tunnel
- the SSH tunnel successfully reached the Windows raw TCP listener

The TLS error is expected because the Windows-side fixture was not a real HTTPS service.

The same result was reproduced through the WSL2 primary IP:

```bash
wsl docker exec test-nginx curl --noproxy '*' -sk --connect-timeout 8 --max-time 12 \
  https://<wsl-ip>:28443 -w 'CODE=%{http_code} EXIT=%{exitcode} ERR=%{errormsg}' -o /dev/null
```

Observed:

```text
CODE=000 EXIT=35 ERR=TLS connect error: wrong version number
```

Finding:

The relay fixed the routing problem for bridge-mode containers.

### Test 1.3 - Inspect proxy behavior inside the container

Command:

```bash
wsl docker exec test-nginx sh -c "env | grep -i proxy"
```

Observed:

```text
HTTPS_PROXY=http://<corp-proxy-host>:<proxy-port>
HTTP_PROXY=http://<corp-proxy-host>:<proxy-port>
https_proxy=http://<corp-proxy-host>:<proxy-port>
http_proxy=http://<corp-proxy-host>:<proxy-port>
NO_PROXY=localhost,<internal-domain-list>
no_proxy=localhost,<internal-domain-list>
```

Key observations:

- proxy variables were present inside the container
- `NO_PROXY` did not cover the RFC1918 addresses used in the successful relay tests
- `curl --noproxy '*'` bypassed the configured proxy variables for direct-IP tests

Track 4 below showed a related but separate issue:

- hostname-based HTTPS was still intercepted in this environment
- direct RFC1918 IP access was not

### Track 1 Summary

| Question | Answer |
|----------|--------|
| Was the original tunnel listener loopback-only? | `Yes` |
| Did a non-loopback relay fix container reachability? | `Yes` |
| Was there also a proxy-related constraint? | `Yes` |

Conclusion:

The original `F9` failure had a structural cause that could be fixed.
The enterprise environment added a second constraint, but it did not prevent direct-IP relay access.

---

## Track 2 - Host-Network Container

Goal:

- see whether `network_mode: host` solves `F9` without any relay

### Test 2.1 - Host-network container via `localhost:18443`

Command:

```powershell
wsl docker run --rm --network host curlimages/curl:latest \
  --noproxy "*" -sk --connect-timeout 8 --max-time 12 \
  https://localhost:18443 -w "CODE=%{http_code} EXIT=%{exitcode} ERR=%{errormsg}" -o /dev/null
```

Observed:

```text
CODE=502 EXIT=0 ERR=<proxy interception page>
```

Interpretation:

- curl received an HTTP response
- but the response came from a proxy layer, not from the tunnel

### Test 2.2 - Host-network container via `<bridge-gateway-ip>:28443`

Command:

```powershell
wsl docker run --rm --network host curlimages/curl:latest \
  --noproxy "*" -sk --connect-timeout 8 --max-time 12 \
  https://<bridge-gateway-ip>:28443 -w "CODE=%{http_code} EXIT=%{exitcode} ERR=%{errormsg}" -o /dev/null
```

Observed:

```text
CODE=502 EXIT=0 ERR=<proxy interception page>
```

Conclusion:

`network_mode: host` did not solve the problem in this environment.

Status: `KO`

Bridge mode with an explicit relay was more reliable than host mode here.

---

## Track 3 - Make The Tunnel Container-Facing

Goal:

- expose the tunneled endpoint on a route bridge-mode containers can actually use

This track was effectively validated by the `socat` relay from Track 1.

### Effective architecture

```text
Container (bridge mode)
  -> <bridge-gateway-ip>:28443
  -> socat relay in WSL2
  -> 127.0.0.1:18443
  -> SSH reverse tunnel
  -> Windows localhost:8443
```

### Validated routes

| Route from the container | Result |
|--------------------------|--------|
| `https://<bridge-gateway-ip>:28443` | routing `OK` |
| `https://<wsl-ip>:28443` | routing `OK` |

Why `<bridge-gateway-ip>` is the better choice:

- it is tied to the Docker bridge
- it is more stable than the main WSL2 IP across sessions
- it avoids hostname-based proxy interception in this environment

### GatewayPorts path

The SSH `GatewayPorts` approach was not tested in this campaign.

It was considered less attractive because:

- it requires changing SSH server configuration
- the `socat` relay already provided a working proof of concept

Conclusion:

Option `relay in WSL2` was the best result of the campaign.

---

## Track 4 - Ergonomics: Hostname Resolution

Goal:

- avoid hard-coding raw IP addresses if possible

### Test 4.1 - `host.docker.internal` mapped to the host gateway

Command:

```powershell
wsl docker run --rm --add-host "host.docker.internal:host-gateway" curlimages/curl:latest \
  --noproxy "*" -sk --connect-timeout 8 --max-time 12 \
  https://host.docker.internal:28443 -w "CODE=%{http_code} EXIT=%{exitcode} ERR=%{errormsg}" -o /dev/null
```

Inside that container, the alias resolved to the Docker bridge gateway.

Observed result:

```text
CODE=502 EXIT=0 ERR=<proxy interception page>
```

Interpretation:

- the hostname resolved correctly
- but the HTTPS request was still intercepted because the CONNECT target remained hostname-based

### Track 4 Summary

| Approach | Works in this environment |
|----------|---------------------------|
| `https://<bridge-gateway-ip>:28443` | `Yes` |
| `https://<wsl-ip>:28443` | `Yes` |
| `https://host.docker.internal:28443` | `No` |
| `https://localhost:18443` from host-mode container | `No` |

Conclusion:

In this enterprise environment, hostname-based container-to-host HTTPS should not be treated as a supported path.

Direct RFC1918 IP addresses were the reliable option.

---

## Track 5 - Re-Test With A Real Service

This track was not executed in this campaign.

Reason:

- the routing chain was already validated at the TCP level
- the Windows fixture was deliberately minimal
- the next meaningful step is to repeat the solved path with a real HTTPS service and one representative application container

Status: pending

---

## Consolidated Results

### Flow table

| Flow | NAT baseline | NAT + tunnel only | NAT + tunnel + relay |
|------|--------------|-------------------|----------------------|
| F1 - Windows -> native WSL2 `4200` | `OK` | `N/A` | `N/A` |
| F2 - Windows -> Docker `8080` | `OK` | `N/A` | `N/A` |
| F3 - WSL2 -> Docker `8080` | `OK` | `N/A` | `N/A` |
| F4 - WSL2 -> Windows `localhost:8443` | `KO` | `N/A` | `N/A` |
| F7 - Container -> Windows `8443` | `KO` | `N/A` | `N/A` |
| F8 - WSL2 -> tunnel `18443` | `N/A` | `OK` | `OK` |
| F9 - Container -> tunneled endpoint | `N/A` | `KO` | routing `OK` |

Notes:

- `routing OK` for `F9` means the container successfully traversed the full TCP path
- the remaining TLS failure came from the raw Windows fixture, not from routing

### Container routing decision

```text
Need container -> Windows dependency?
|
|-- Use hostname? -> No, blocked by proxy interception in this environment
|
`-- Use direct IP?
    |
    |-- <bridge-gateway-ip>:28443 -> Works with relay
    `-- <wsl-ip>:28443 -> Works with relay, but less stable
```

---

## Key Findings

### 1. Listener scope was the first and solvable blocker

The SSH reverse forward was loopback-only in WSL2.

Adding a relay on `0.0.0.0:28443` was sufficient to make the tunneled endpoint reachable from bridge-mode containers.

### 2. Hostname-based HTTPS remained a bad fit in this environment

`host.docker.internal` and `localhost` from containers were not reliable because hostname-based HTTPS was intercepted by the enterprise proxy layer.

### 3. Bridge mode was better than host mode here

Counterintuitively, bridge-mode containers with direct IP access were more reliable than host-network containers on this workstation.

### 4. `<bridge-gateway-ip>` was the best relay target

It offered the most stable and predictable route for bridge containers.

### 5. The tunnel guardrail remained valuable

The CLI still correctly refused to start when nothing was listening on Windows `8443`.

---

## Updated Decision Outcome

Based on this campaign, the repository can move from:

`Keep as native WSL2 workaround`

to:

`Keep and document relay extension for bridge containers`

This claim should still be qualified:

- it is validated as a routing solution
- it still needs confirmation with a real HTTPS service behind the relay
- hostname-based access remains unsupported in this environment

---

## Recommended Next Steps

1. Add optional relay support to `wsl-tunnel.ps1`.
2. Document the hostname/proxy limitation in `docs/TROUBLESHOOTING.md`.
3. Re-run the solved path with a real HTTPS Windows service.
4. Validate the relay approach on a second constrained workstation.

---

## Environment Restoration

The campaign ended by:

1. stopping the `api` tunnel
2. stopping the `socat` relay
3. stopping the temporary Windows-side listener
4. removing the test nginx container
5. keeping `.wslconfig` on NAT + `localhostForwarding=true`
6. leaving no required persistent changes to WSL2 or Docker configuration
