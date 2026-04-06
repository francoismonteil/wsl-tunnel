# Candidate Solution Validation Report

Date: 2026-04-06  
Plan: `docs/CANDIDATE-SOLUTION-VALIDATION-PLAN.md`  
Run mode: self-directed, autonomous

---

## Scope

This report records a validation campaign of the candidate solution defined in
`docs/CANDIDATE-SOLUTION-VALIDATION-PLAN.md`.

The campaign goal is to confirm that the full routing chain

```text
Container (bridge mode)
  -> <bridge-gateway-ip>:<relay-port>
  -> socat relay in WSL2
  -> 127.0.0.1:<tunnel-port>
  -> SSH reverse tunnel
  -> Windows localhost:<windows-port>
```

is repeatable across sessions and configurations, following the findings of the
`SOLUTION-PLAN-REPORT-2026-04-05.md` campaign.

This report is sanitized for public publication:

- workstation identifiers are removed
- internal IP addresses are replaced with placeholders
- internal proxy hostnames and domain lists are generalized

Placeholder values used in this report:

- `<wsl-ip>` = primary WSL2 IP during the session
- `<nat-gateway-ip>` = Windows host gateway IP seen from WSL2 in NAT mode
- `<bridge-gateway-ip>` = Docker bridge gateway reachable from bridge-mode containers
- `<corp-proxy-host>` = corporate proxy host exposed in container environment variables
- `<internal-domain-list>` = list of internal domains in NO\_PROXY

---

## Machine Snapshot

| Property | Value |
|----------|-------|
| Date | 2026-04-06 |
| Windows version | 10.0.26100.8037 |
| WSL version | 2.6.3.0 |
| WSL kernel | 6.6.87.2-1 |
| Distribution | Ubuntu (WSL2) |
| PowerShell version | 5.1.26100.7920 |
| Docker Engine in WSL2 | 27.0.1 |

### `.wslconfig` during the campaign

```ini
[wsl2]
swap = 0
autoProxy=false
networkingMode=NAT
localhostForwarding=true
```

### Network addresses

| Role | Placeholder | Notes |
|------|-------------|-------|
| WSL2 primary IP | `<wsl-ip>` | eth0 in Ubuntu |
| NAT gateway | `<nat-gateway-ip>` | Windows host gateway as seen from WSL2 |
| Docker bridge gateway | `<bridge-gateway-ip>` | Docker default bridge |

---

## Fixtures Used

| Fixture | Description |
|---------|-------------|
| Windows TCP listener on `8443` | Raw TCP listener (not real HTTPS). Sufficient to validate routing; TLS error confirms chain traversal. |
| Native WSL2 HTTP server on `4200` | `python3 -m http.server 4200 --bind 0.0.0.0` |
| Docker bridge-mode container | `nginx:alpine` published as `8080:80` |
| SSH reverse tunnel | `wsl-tunnel.ps1 up api` — WSL `18443` → Windows `8443` |
| `socat` relay | `socat TCP-LISTEN:28443,fork,bind=0.0.0.0,reuseaddr TCP:127.0.0.1:18443` |

---

## Preconditions

### P1 — Windows service on port 8443

Command:

```powershell
curl.exe -sk --connect-timeout 8 --max-time 20 https://localhost:8443 `
  -w "HTTP=%{http_code} ERR=%{errormsg}" -o NUL
```

Observed:

```text
HTTP=000 ERR=Failed to connect to localhost port 8443 after 2220 ms: Could not connect to server
```

Status: `KO` — no real Windows HTTPS service was running at campaign start.

Impact:

- routing can still be validated at the TCP level using a raw TCP listener on Windows
- TLS handshake failure (exit 35 from curl) becomes the indicator of successful routing
- a full application-layer confirmation (real HTTP response) requires a real HTTPS service
  and remains pending for a future session (same limitation as `SOLUTION-PLAN-REPORT-2026-04-05`)

Mitigation:

A raw TCP listener was created using PowerShell's `TcpListener`:

```powershell
$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, 8443)
$listener.Start()
```

Verification:

```powershell
Get-NetTCPConnection -State Listen -LocalPort 8443
```

Observed:

```text
LocalAddress  LocalPort
0.0.0.0       8443
```

Status after mitigation: `OK (fixture)` — routing validation feasible.

### P2 — SSH Windows → WSL2

Observation:

At the start of the session, `wsl --list -v` showed `Ubuntu Stopped`. WSL2 was not running.

The first SSH test therefore failed:

```powershell
ssh wsl-localhost "echo Hello from WSL"
```

Error:

```text
ssh: connect to host localhost port 22: Connection refused
```

Resolution:

```powershell
wsl -e bash -c "sudo service ssh start"
```

Then WSL2 was confirmed running (`Ubuntu Running`) and localhost:22 was reachable via `localhostForwarding`.

Verification after resolution:

```powershell
$r = ssh.exe wsl-localhost "echo Hello from WSL"; Write-Host "EXIT=$LASTEXITCODE OUTPUT=$r"
```

Observed:

```text
EXIT=0 OUTPUT=Hello from WSL
```

Status: `OK`

Important operational note:

WSL2 shuts down when no active session is open. For all subsequent tests, WSL2 was kept alive
via a persistent background process (`sleep infinity`) in a long-running session. This is a
prerequisite for the tunnel workflow — WSL2 must be running for the SSH connection to succeed.

### P3 — Docker Engine in WSL2

Command:

```powershell
wsl -e bash -c "docker ps"
```

Observed:

```text
CONTAINER ID   IMAGE   COMMAND   CREATED   STATUS   PORTS   NAMES
```

Status: `OK` — Docker Engine running, no containers initially.

---

## Step 1 — Confirm NAT Baseline Flows

Goal: verify that the useful flows in NAT mode are still `OK` before adding the tunnel and relay.

### F1 — Windows → native WSL2 service `4200`

Fixture:

```bash
python3 -m http.server 4200 --bind 0.0.0.0
```

Test:

```powershell
curl.exe --connect-timeout 8 --max-time 20 "http://localhost:4200" -s -w "HTTP=%{http_code}"
```

Observed:

```text
<!DOCTYPE HTML PUBLIC ...>
<title>Directory listing for /</title>
...
HTTP=200
```

Status: **`OK`**

### F2 — Windows → Docker published port `8080`

Fixture:

```bash
docker run --rm -d --name test-nginx -p 8080:80 nginx:alpine
```

Test:

```powershell
curl.exe --connect-timeout 8 --max-time 20 "http://localhost:8080" -s -w "`nHTTP=%{http_code}"
```

Observed:

```text
HTTP=200
```

Status: **`OK`**

### F3 — WSL2 → Docker published port `8080`

Test:

```bash
curl --connect-timeout 8 --max-time 20 http://localhost:8080 -s -o /dev/null -w 'HTTP=%{http_code}'
```

Observed:

```text
HTTP=200
```

Status: **`OK`**

### F4 — WSL2 → Windows `localhost:8443` without tunnel

Test:

```bash
curl --noproxy '*' --connect-timeout 8 --max-time 12 https://localhost:8443 \
  -sk -o /dev/null -w 'CODE=%{http_code} EXIT=%{exitcode} ERR=%{errormsg}'
```

Observed:

```text
CODE=000 EXIT=7 ERR=Failed to connect to localhost port 8443 after 0 ms: Connection refused
```

Status: **`KO` — expected** in NAT mode. The tunnel replaces this direct path.

### F6 — Container → native WSL2 service `4200`

Test (via Docker bridge gateway):

```bash
docker exec test-nginx curl --noproxy '*' --connect-timeout 8 --max-time 12 \
  http://<bridge-gateway-ip>:4200 -s -o /dev/null \
  -w 'HTTP=%{http_code} EXIT=%{exitcode} ERR=%{errormsg}'
```

Observed:

```text
HTTP=200 EXIT=0 ERR=
```

Status: **`OK`**

### Step 1 Summary

| Flow | Status | Notes |
|------|--------|-------|
| F1 Windows → WSL2 native `4200` | `OK` | HTTP 200 |
| F2 Windows → Docker `8080` | `OK` | HTTP 200 |
| F3 WSL2 → Docker `8080` | `OK` | HTTP 200 |
| F4 WSL2 → Windows `localhost:8443` | `KO` expected | Connection refused, NAT behavior |
| F6 Container → WSL2 native `4200` | `OK` | HTTP 200 via bridge gateway |

Conclusion: baseline NAT flows are stable. Proceed to tunnel.

---

## Step 2 — Windows Service Health

The Windows HTTPS service on `8443` was absent (see precondition P1).

A raw TCP listener was used as a fixture. This fixture:

- satisfies the CLI guardrail (`Test-WslTunnelWindowsPortListening`)
- allows routing validation at the TCP level
- produces a TLS handshake failure (exit 35) that confirms end-to-end routing

Step is recorded as: **`OK (fixture)`** — routing validation feasible, but not a real HTTPS response.

---

## Step 3 — Tunnel Start and F8 Validation

### Tunnel start

Command:

```powershell
.\wsl-tunnel.ps1 up api
```

Observed:

```text
Tunnel 'api' is active.
WSL localhost:18443 -> Windows localhost:8443
PID: <ssh-pid>
Test from WSL: curl -k https://localhost:18443
Stop with: .\wsl-tunnel.ps1 down api
```

Status: `OK`

### Tunnel status

Command:

```powershell
.\wsl-tunnel.ps1 status api
```

Observed:

```text
Service     : api
Protocol    : https
WindowsPort : 8443
WslPort     : 18443
Tunnel      : active
Windows     : available
PID         : <ssh-pid>
Test        : curl -k https://localhost:18443
NextAction  : Run '.\wsl-tunnel.ps1 down api' when you are done.
```

### Tunnel listener scope inspection

This revalidates the structural finding from `SOLUTION-PLAN-REPORT-2026-04-05`:

Command:

```bash
ss -ltn | grep 18443
```

Observed:

```text
LISTEN 0  128  127.0.0.1:18443  0.0.0.0:*
LISTEN 0  128      [::1]:18443     [::]:*
```

Finding: **the SSH reverse forward binds only to loopback inside WSL2.** This is reproduced
consistently. Bridge-mode containers cannot reach this endpoint directly.

### F8 — WSL2 → tunnel `18443`

Test:

```bash
curl -vk --connect-timeout 8 --max-time 12 https://localhost:18443 \
  -w 'CODE=%{http_code} EXIT=%{exitcode} ERR=%{errormsg}' -o /dev/null
```

Observed:

```text
CODE=000 EXIT=35 ERR=error:0A000126:SSL routines::unexpected eof while reading
```

Interpretation:

- exit 35 is a TLS handshake error, not a TCP routing failure
- the curl client successfully connected to the tunnel endpoint `localhost:18443`
- the SSH reverse tunnel relayed the connection to Windows `8443`
- the Windows fixture (raw TCP listener) accepted the connection but sent no TLS response
- the TLS error is expected from a raw TCP listener and confirms the full routing chain

Status: **`OK` (routing confirmed)**

---

## Step 4 — Relay Start and Listener Scope

### Relay start

Command (in WSL2):

```bash
socat TCP-LISTEN:28443,fork,bind=0.0.0.0,reuseaddr TCP:127.0.0.1:18443
```

### Relay listener scope

Command:

```bash
ss -ltn | grep 28443
```

Observed:

```text
LISTEN 0  5  0.0.0.0:28443  0.0.0.0:*
```

Status: `OK` — relay listens on all interfaces, including those reachable from bridge-mode containers.

### Combined listener state

After both tunnel and relay were running:

```text
LISTEN 0  128  127.0.0.1:18443  0.0.0.0:*   # SSH reverse forward (loopback only)
LISTEN 0  128      [::1]:18443     [::]:*    # SSH reverse forward (loopback only)
LISTEN 0    5        0.0.0.0:28443  0.0.0.0:*   # socat relay (all interfaces)
```

---

## Step 5 — F9 Validation From Bridge-Mode Container

### Proxy environment in the container

Before running F9 tests, proxy variables inside the container were recorded:

```bash
docker exec test-nginx sh -c 'env | grep -i proxy'
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

- corporate proxy variables are injected into containers
- `NO_PROXY` covers only `localhost` and internal corporate domains
- RFC1918 addresses are **not** in `NO_PROXY`
- without explicit proxy bypass, curl inside the container will attempt CONNECT tunneling
  through the corporate proxy for any HTTPS request

### F9 — Container → relay via bridge gateway (Profile A: proxy unmanaged)

Command:

```bash
docker exec test-nginx curl -sk --connect-timeout 8 --max-time 12 \
  https://<bridge-gateway-ip>:28443 \
  -w 'CODE=%{http_code} EXIT=%{exitcode} ERR=%{errormsg}' -o /dev/null
```

Observed:

```text
CODE=000 EXIT=56 ERR=CONNECT tunnel failed, response 403
```

Interpretation:

- curl attempted to reach `<bridge-gateway-ip>:28443` through the corporate proxy
- the proxy refused the CONNECT request with HTTP 403
- the container never reached the relay

Status: **`KO`** in Profile A (proxy unmanaged)

### F9 — Container → relay via bridge gateway (Profile B: proxy managed)

Command (with explicit noproxy override):

```bash
docker exec test-nginx curl --noproxy '*' -sk --connect-timeout 8 --max-time 12 \
  https://<bridge-gateway-ip>:28443 \
  -w 'CODE=%{http_code} EXIT=%{exitcode} ERR=%{errormsg}' -o /dev/null
```

Observed:

```text
CODE=000 EXIT=35 ERR=TLS connect error: error:0A000126:SSL routines::unexpected eof while reading
```

Interpretation:

- exit 35 is a TLS handshake error, not a TCP routing failure
- `--noproxy '*'` bypassed the corporate proxy and made curl connect directly to the relay IP
- the container successfully reached the relay at `<bridge-gateway-ip>:28443`
- the relay forwarded the connection to `127.0.0.1:18443`
- the SSH tunnel forwarded the connection to Windows `8443`
- the Windows raw TCP fixture accepted the connection, producing the expected TLS error

Status: **`OK` (routing confirmed)** in Profile B (proxy managed)

### F9 — Container → relay via WSL2 primary IP (Profile B)

Command:

```bash
docker exec test-nginx curl --noproxy '*' -sk --connect-timeout 8 --max-time 12 \
  https://<wsl-ip>:28443 \
  -w 'CODE=%{http_code} EXIT=%{exitcode} ERR=%{errormsg}' -o /dev/null
```

Observed:

```text
CODE=000 EXIT=35 ERR=TLS connect error: error:0A000126:SSL routines::unexpected eof while reading
```

Status: **`OK` (routing confirmed)** — WSL2 primary IP is a valid secondary route.

---

## Final Validation Matrix

| Flow | Profile A (proxy unmanaged) | Profile B (proxy managed) | Notes |
|------|-----------------------------|---------------------------|-------|
| F1 Windows → WSL2 native `4200` | `OK` | `N/A` | HTTP 200 |
| F2 Windows → Docker `8080` | `OK` | `N/A` | HTTP 200 |
| F3 WSL2 → Docker `8080` | `OK` | `N/A` | HTTP 200 |
| F4 WSL2 → Windows `localhost:8443` | `KO` expected | `N/A` | Connection refused, NAT — tunnel replaces |
| F6 Container → WSL2 native `4200` | `OK` | `N/A` | HTTP 200 via bridge gateway |
| F8 WSL2 → tunnel `18443` | `OK` (routing) | `N/A` | Exit 35, TLS fixture error confirms chain |
| F9 Container → relay `<bridge-gateway-ip>:28443` | `KO` | `OK` (routing) | Profile A: proxy 403; Profile B: exit 35 |
| F9 Container → relay `<wsl-ip>:28443` | not tested | `OK` (routing) | Exit 35 |

Acceptance criteria review (from plan):

- `F1`, `F2`, `F3`, `F6`: expected `OK` → all confirmed `OK` ✓
- `F4`: `KO` acceptable because the tunnel replaces it → confirmed `KO` as expected ✓
- `F8`: expected `OK` → confirmed routing `OK` ✓
- `F9`: expected `OK` → routing `OK` in Profile B (proxy managed) ✓

**The candidate solution meets its acceptance criteria when proxy is explicitly managed.**

---

## Key Findings

### 1. Solution routing is repeatable

The full chain

```text
Container (bridge mode)
  -> <bridge-gateway-ip>:28443  (--noproxy '*')
  -> socat relay in WSL2
  -> 127.0.0.1:18443
  -> SSH reverse tunnel
  -> Windows localhost:8443
```

was reproduced successfully in this session, confirming the findings of `SOLUTION-PLAN-REPORT-2026-04-05`.

Exit code 35 (TLS handshake failure from a raw TCP fixture) is the reliable signal for routing success
when no real HTTPS service is available on the Windows side.

### 2. SSH tunnel listener scope is a confirmed structural constraint

The SSH reverse forward consistently binds only to loopback inside WSL2:

```text
127.0.0.1:18443  and  [::1]:18443
```

This is not a misconfiguration. It is the default SSH behavior with `-R`.
The `socat` relay is the correct and validated way to expose the tunneled endpoint beyond loopback.

### 3. Corporate proxy is a mandatory secondary constraint

Profile A (no proxy bypass) fails because the corporate proxy:

- is injected into containers as `HTTPS_PROXY` / `HTTP_PROXY`
- does not cover RFC1918 addresses in `NO_PROXY`
- refuses CONNECT to RFC1918 endpoints with HTTP 403

Profile B (explicit `--noproxy '*'` or equivalent Docker NO_PROXY extension) resolves this.

This constraint is application-managed, not infrastructural. Teams using this solution must
configure `NO_PROXY` to include the relay IP range (RFC1918) or use `--noproxy '*'` explicitly.

### 4. `<bridge-gateway-ip>` remains the recommended relay target

- it is consistent across Docker bridge subnetworks
- it does not change between WSL2 session restarts (the Docker bridge is stable)
- it avoids any hostname-based proxy interception

The WSL2 primary IP is a valid fallback but is less predictable across sessions.

### 5. WSL2 lifecycle is an operational constraint

WSL2 shuts down when no active process is running. The SSH service (and therefore the tunnel)
requires WSL2 to be running. Teams using `wsl-tunnel` must ensure WSL2 is started before
attempting any tunnel operation. A startup probe or early `wsl -e bash -c "echo keepalive"` check
before `wsl-tunnel.ps1 up` may be a worthwhile addition to the workflow.

### 6. Real HTTPS service validation remains pending

This campaign validated routing only. The Windows-side fixture was a raw TCP listener.
The complete candidate solution confirmation — an actual HTTPS application response traversing
the full chain — requires a real Windows HTTPS service and remains pending for a future session.
This is Track 5 in `SOLUTION-PLAN-REPORT-2026-04-05` and was not completed in either campaign.

---

## Environment Restoration

At end of session:

1. Tunnel `api` stopped (`.\wsl-tunnel.ps1 down api` — confirmed `inactive`)
2. Container `test-nginx` stopped (`docker stop test-nginx`)
3. `socat` relay stopped (background process ended with WSL2 session)
4. Windows TCP listener on `8443` stopped (`$listener.Stop()`)
5. `.wslconfig` remains unchanged: `NAT + localhostForwarding=true`
6. No persistent changes to WSL2, Docker, or SSH configuration

---

## Recommended Next Steps

These recommendations extend those from `SOLUTION-PLAN-REPORT-2026-04-05`:

1. **Re-run with a real Windows HTTPS service.**
   Validate that an actual HTTP response (200, 401, or a recognizable payload) traverses the
   full chain. This closes the last open gap between routing proof and application-layer proof.

2. **Document the proxy bypass requirement in `docs/TROUBLESHOOTING.md`.**
   The NO_PROXY / `--noproxy` requirement must be explicit in the consumer documentation.
   Recommend extending `NO_PROXY` to include `172.16.0.0/12` (RFC1918 Docker range).

3. **Document the WSL2 lifecycle dependency.**
   The tunnel workflow depends on WSL2 being active. This should be noted in `docs/SETUP.md`
   and optionally guarded by a preflight check in `wsl-tunnel.ps1`.

4. **Add optional relay support to `wsl-tunnel.ps1`.**
   The relay (socat) step is manual. A `relay` subcommand or an extended `up` flag would
   improve the daily developer experience and is the highest-priority ergonomics improvement
   identified across both campaigns.

5. **Validate on a second workstation.**
   Both campaigns ran on the same constrained machine. A second workstation validation
   would confirm whether the proxy and firewall constraints are universal across the team.
