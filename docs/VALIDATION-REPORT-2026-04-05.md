# Validation Report - Campaign A

Date: 2026-04-05  
Run mode: self-directed, based on `docs/VALIDATION-PLAN.md`

---

## Scope

This report records one representative validation campaign on a constrained workstation.

It is intentionally sanitized for public publication:

- workstation names are removed
- internal IP addresses are replaced with placeholders
- corporate domains are generalized
- temporary local paths are normalized

Placeholder values used in this report:

- `<nat-gateway-ip>` = Windows host gateway IP as seen from WSL2 in NAT mode
- `<wsl-ip>` = primary WSL2 IP used for container -> WSL2 checks
- `<mirrored-ip-a>` and `<mirrored-ip-b>` = Windows or mirrored IPs tested in mirrored mode
- `<corp-proxy-host>` = corporate proxy host exposed inside the container environment

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

### `.wslconfig` at the start of the campaign

```ini
[wsl2]
swap = 0
autoProxy=false
networkingMode=NAT
localhostForwarding=true
```

---

## Global Preconditions

### P1 - Windows service on port 8443

Command:

```powershell
curl.exe -vk --connect-timeout 8 --max-time 20 https://localhost:8443
```

Observed:

```text
connect to ::1 port 8443 failed: Connection refused
connect to 127.0.0.1 port 8443 failed: Connection refused
curl: (7) Failed to connect to localhost port 8443
```

Status: `KO`

The Windows HTTPS service on `8443` was not running at the beginning of the campaign.

Impact:

- flows `F4`, `F5`, and `F7` cannot be interpreted purely as service-health checks
- configuration `B` later creates a temporary Windows HTTPS service so the tunnel can be tested end to end

### P2 - SSH Windows -> WSL2

Command:

```powershell
ssh wsl-localhost "echo Hello from WSL"
```

Observed:

```text
Hello from WSL
```

Status: `OK`

---

## Configuration A - NAT Baseline

`.wslconfig` during this phase:

```ini
[wsl2]
networkingMode=NAT
localhostForwarding=true
```

### Fixtures

| Fixture | Command | Verification | Status |
|---------|---------|--------------|--------|
| nginx container | `wsl docker run --rm -d --name test-nginx -p 8080:80 nginx:alpine` | `0.0.0.0:8080->80/tcp` visible in `docker ps` | `OK` |
| native WSL2 HTTP server | `wsl -e python3 -m http.server 4200 --bind 0.0.0.0` | `ss -ltn` shows `0.0.0.0:4200 LISTEN` | `OK` |

### Network discovery in NAT

| Item | Value |
|------|-------|
| NAT gateway seen from WSL2 | `<nat-gateway-ip>` |
| primary WSL2 IP | `<wsl-ip>` |

Reference commands:

```bash
ip route show default
hostname -I
```

### Results

#### F1 - Windows -> native WSL2 service on `localhost:4200`

Command:

```powershell
curl.exe --connect-timeout 8 --max-time 20 http://localhost:4200
```

Observed:

```html
<title>Directory listing for /</title>
```

Status: `OK`

`localhostForwarding=true` correctly exposes the native WSL2 service to Windows.

#### F2 - Windows -> Docker published port on `localhost:8080`

Command:

```powershell
curl.exe --connect-timeout 8 --max-time 20 http://localhost:8080
```

Observed:

```html
<title>Welcome to nginx!</title>
```

Status: `OK`

Windows reaches the Docker-published service in NAT mode.

#### F3 - WSL2 -> Docker published port on `localhost:8080`

Command:

```powershell
wsl curl -s --connect-timeout 8 --max-time 20 http://localhost:8080 -o /dev/null -w "HTTP=%{http_code}"
```

Observed:

```text
HTTP=200
```

Status: `OK`

#### F4 - WSL2 -> Windows service via `localhost:8443`

Command:

```powershell
wsl curl -vk --connect-timeout 8 --max-time 20 https://localhost:8443
```

Observed:

```text
* Trying 127.0.0.1:8443...
* connect to 127.0.0.1 port 8443 failed: Connection refused
* Trying ::1:8443...
* connect to ::1 port 8443 failed: Connection refused
curl: (7) Connection refused
```

Status: `KO`

In NAT mode, `localhost` inside WSL2 still resolves to WSL2 loopback, not the Windows host.

The immediate refusal is consistent with a local WSL2 loopback failure, not a successful route to Windows.

#### F5 - WSL2 -> Windows service via `<nat-gateway-ip>:8443`

Command:

```powershell
wsl curl -vk --connect-timeout 8 --max-time 20 https://<nat-gateway-ip>:8443
```

Observed:

```text
* connect to <nat-gateway-ip> port 8443 failed: Connection timed out
curl: (28) Connection timeout
```

Status: `KO`

The host-IP path timed out in NAT mode.

Because the Windows service was absent at the start of the campaign, this timeout should be interpreted carefully. It still matches the previously recorded behavior from another session where the service existed.

#### F6 - Container -> native WSL2 service on `<wsl-ip>:4200`

Command:

```bash
wsl docker exec test-nginx curl --noproxy '*' -s --connect-timeout 8 --max-time 20 \
  http://<wsl-ip>:4200 -o /dev/null -w 'HTTP=%{http_code} ERR=%{errormsg}'
```

Observed:

```text
HTTP=200 ERR=
```

Status: `OK`

The container can consume the native WSL2 service through the WSL2 IP.

#### F7 - Container -> Windows service via `<nat-gateway-ip>:8443`

Command:

```bash
wsl docker exec test-nginx sh -c "curl --noproxy '*' -sk --connect-timeout 8 --max-time 20 \
  https://<nat-gateway-ip>:8443 -o /dev/null -w '%{http_code} %{exitcode} %{errormsg}'"
```

Observed:

```text
000 28 Connection timed out
```

Status: `KO`

The container could not reach the Windows service through the NAT gateway path.

### Configuration A Summary

| Flow | Description | Status |
|------|-------------|--------|
| F1 | Windows -> native WSL2 `4200` | `OK` |
| F2 | Windows -> Docker `8080` | `OK` |
| F3 | WSL2 -> Docker `8080` | `OK` |
| F4 | WSL2 -> Windows `localhost:8443` | `KO` |
| F5 | WSL2 -> Windows `<nat-gateway-ip>:8443` | `KO` |
| F6 | Container -> native WSL2 `4200` | `OK` |
| F7 | Container -> Windows `8443` | `KO` |

---

## Configuration B - NAT + Tunnel

Goal: validate whether the tunnel restores the missing `WSL2 -> Windows 8443` path.

### Temporary Windows HTTPS service created for the campaign

Because no Windows HTTPS service was listening on `8443` at the start of the run, a minimal HTTPS service was created temporarily for the tunnel test.

Method:

1. generate a short-lived self-signed certificate inside WSL2
2. copy the certificate and key to a temporary Windows directory
3. start a minimal Python HTTPS server on Windows

Verification:

```powershell
curl.exe -sk https://localhost:8443 -w "HTTP=%{http_code}"
```

Observed:

```text
Unauthorized HTTP=401
```

Status: `OK`

This temporary service is only a test fixture. It was created to validate the network path, not to represent a business service.

### B1 - Tunnel state before startup

Command:

```powershell
.\wsl-tunnel.ps1 down api
```

Observed:

```text
Tunnel 'api' is not active.
```

Status: clean initial state

### B2 - Start the tunnel

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
```

Status: `OK`

### B3 - Listener scope inside WSL2

Command:

```bash
wsl ss -ltn | grep 18443
```

Observed:

```text
LISTEN 0 128 127.0.0.1:18443 0.0.0.0:*
LISTEN 0 128     [::1]:18443    [::]:*
```

Status: informational

The SSH reverse forward is loopback-only inside WSL2 by default.

This matters because a container running on the bridge network cannot directly reach a listener that only exists on `127.0.0.1` inside WSL2.

### F8 - WSL2 -> tunnel on `localhost:18443`

Command:

```bash
wsl curl -sk --connect-timeout 8 --max-time 20 https://localhost:18443 -w "HTTP=%{http_code}"
```

Observed:

```text
Unauthorized
HTTP=401
```

Status: `OK`

This is the key result of configuration B.

The tunnel restored the missing `WSL2 -> Windows localhost:8443` path that was `KO` in NAT without the workaround.

### F9 - Container -> tunnel on `18443`

Three routes were attempted.

#### F9a - via `host.docker.internal:18443`

Command:

```bash
wsl docker exec test-nginx curl -sk --noproxy "*" --connect-timeout 8 --max-time 12 \
  https://host.docker.internal:18443 -w "CODE=%{http_code} ERR=%{errormsg}" -o /dev/null
```

Observed:

```text
HTTP=000 ERR=Resolving timed out
```

Status: `KO`

#### F9b - via `<wsl-ip>:18443`

Command:

```bash
wsl docker exec test-nginx curl -sk --noproxy "*" --connect-timeout 8 --max-time 12 \
  https://<wsl-ip>:18443 -w "CODE=%{http_code} ERR=%{errormsg}" -o /dev/null
```

Observed:

```text
CODE=407 ERR=<proxy authentication page>
CODE=000 ERR=CONNECT tunnel failed, response 403
```

Status: `KO`

#### F9c - via the Docker bridge gateway on `:18443`

Command:

```bash
wsl docker exec test-nginx curl -sk --noproxy "*" --connect-timeout 8 --max-time 12 \
  https://<docker-bridge-ip>:18443 -w "CODE=%{http_code} ERR=%{errormsg}" -o /dev/null
```

Observed:

```text
CODE=407 ERR=<proxy authentication page>
CODE=000 ERR=CONNECT tunnel failed, response 403
```

Status: `KO`

#### F9 analysis

The container environment exposed proxy variables pointing to `<corp-proxy-host>`.

In practice, the campaign observed behavior consistent with a transparent corporate proxy:

- HTTPS requests to private addresses were intercepted
- `curl --noproxy "*"` did not bypass the interception
- the container never reached the WSL2 listener on `127.0.0.1:18443`

So `F9` was blocked by two separate factors:

1. the tunnel listener was loopback-only inside WSL2
2. the container environment behaved as if a transparent proxy still intercepted HTTPS egress

### Configuration B Summary

| Flow | Description | Status |
|------|-------------|--------|
| F8 | WSL2 -> Windows via tunnel `18443` | `OK` |
| F9 | Container -> tunnel `18443` | `KO` |

---

## Configuration C - Mirrored

`.wslconfig` used for this phase:

```ini
[wsl2]
swap = 0
autoProxy=false
networkingMode=mirrored
```

### Confirmation of mirrored mode

Reference command:

```bash
wsl ip addr show
```

Observed behavior:

- multiple Windows-backed interfaces appeared inside WSL2
- no NAT-style single `172.x.x.x` host gateway path was used as the primary model

This was treated as confirmation that mirrored mode was active.

### Fixtures

| Fixture | Command | Status |
|---------|---------|--------|
| nginx container | `wsl docker run --rm -d --name test-nginx -p 8080:80 nginx:alpine` | `OK` |
| native WSL2 HTTP server | `wsl -e python3 -m http.server 4200 --bind 0.0.0.0` | `OK` |

### Results

#### F1 - Windows -> native WSL2 service on `localhost:4200`

Command:

```powershell
curl.exe --connect-timeout 8 --max-time 20 http://localhost:4200
```

Observed:

```html
<title>Directory listing for /</title>
```

Status: `OK`

#### F2 - Windows -> Docker published port on `localhost:8080`

Command:

```powershell
curl.exe --connect-timeout 8 --max-time 20 http://localhost:8080
```

Observed:

```text
curl: (28) Connection timed out
```

Status: `KO`

This is the key mirrored-mode regression for local development.

#### F3 - WSL2 -> Docker published port on `localhost:8080`

Command:

```powershell
wsl curl -s --connect-timeout 8 --max-time 20 http://localhost:8080 -o /dev/null -w "HTTP=%{http_code}"
```

Observed:

```text
HTTP=200
```

Status: `OK`

The container stayed healthy and reachable from inside WSL2 while Windows lost access to it.

#### F4 - WSL2 -> Windows service via `localhost:8443`

Command:

```powershell
wsl curl -vk --connect-timeout 8 --max-time 20 https://localhost:8443
```

Observed:

```text
curl: (7) Connection refused
```

Status: network path `OK`, service health `KO`

Interpretation:

- in mirrored mode, WSL2 and Windows share the `localhost` path
- the refusal here reflects the missing service, not a broken WSL2 -> Windows route
- this interpretation is consistent with the earlier report where the same path returned HTTP `401` when the service existed

#### F5 - WSL2 -> Windows service via mirrored Windows IP

This path was not treated as a separate requirement in this campaign because `F4` already proved the shared-localhost route, which is the more important developer-facing path in mirrored mode.

Status: `N/A`

#### F6 - Container -> native WSL2 service on `<mirrored-ip-a>:4200`

Command:

```bash
wsl docker exec test-nginx curl -s --noproxy '*' --connect-timeout 8 --max-time 20 \
  http://<mirrored-ip-a>:4200 -o /dev/null -w 'HTTP=%{http_code} ERR=%{errormsg}'
```

Observed:

```text
HTTP=200 ERR=
```

Status: `OK`

#### F7 - Container -> Windows service on `8443`

Command:

```bash
wsl docker exec test-nginx curl -sk --noproxy '*' --connect-timeout 8 --max-time 12 \
  https://<mirrored-ip-a>:8443 -w "HTTP=%{http_code} ERR=%{errormsg}" -o /dev/null
```

Observed:

```text
HTTP=000 ERR=Connection timed out
```

Variant through `host.docker.internal`:

```bash
wsl docker exec test-nginx curl -sk --noproxy '*' --connect-timeout 8 --max-time 12 \
  https://host.docker.internal:8443 -w "HTTP=%{http_code} ERR=%{errormsg}" -o /dev/null
```

Observed:

```text
HTTP=000 ERR=Connection timed out
```

Status: `KO`

### Configuration C Summary

| Flow | Description | Status |
|------|-------------|--------|
| F1 | Windows -> native WSL2 `4200` | `OK` |
| F2 | Windows -> Docker `8080` | `KO` |
| F3 | WSL2 -> Docker `8080` | `OK` |
| F4 | WSL2 -> Windows `localhost:8443` | network `OK`, service `KO` |
| F5 | WSL2 -> Windows via direct IP | `N/A` |
| F6 | Container -> native WSL2 `4200` | `OK` |
| F7 | Container -> Windows `8443` | `KO` |

---

## Consolidated Matrix

| Flow | NAT + `localhostForwarding=true` | Mirrored | NAT + tunnel |
|------|----------------------------------|----------|--------------|
| F1 - Windows -> native WSL2 `4200` | `OK` | `OK` | `N/A` |
| F2 - Windows -> Docker `8080` | `OK` | `KO` | `N/A` |
| F3 - WSL2 -> Docker `8080` | `OK` | `OK` | `N/A` |
| F4 - WSL2 -> Windows `localhost:8443` | `KO` | network `OK` | `N/A` |
| F5 - WSL2 -> Windows host IP `:8443` | `KO` | `N/A` | `N/A` |
| F6 - Container -> native WSL2 `4200` | `OK` | `OK` | `N/A` |
| F7 - Container -> Windows `8443` | `KO` | `KO` | `N/A` |
| F8 - WSL2 -> Windows via tunnel `18443` | `N/A` | `N/A` | `OK` |
| F9 - Container -> tunnel `18443` | `N/A` | `N/A` | `KO` |

Legend:

- `OK` = validated and working
- `KO` = validated and failing
- `N/A` = not part of that configuration block

---

## Analysis Against The Validation Plan

### O1 - Prove the problem is real

Result: achieved

- NAT preserved `F2` but failed `F4` and `F7`
- mirrored fixed the native `localhost` route behind `F4`, but broke `F2`

No built-in WSL2 mode solved both `F2` and `F4` at the same time on this workstation.

### O2 - Prove the tunnel has value

Result: achieved

- `F8 = OK`
- in NAT without the workaround, `F4 = KO` and `F5 = KO`

The tunnel restored exactly the missing native `WSL2 -> Windows` path.

### O3 - Prove the tunnel helps containers

Result: not achieved

`F9 = KO` because of two independent obstructions:

1. the SSH reverse-forward listener stayed loopback-only inside WSL2
2. the container environment behaved as if a transparent corporate proxy still intercepted HTTPS egress

This means the project cannot yet claim container support as a solved outcome.

### O4 - Prove the findings are not workstation-specific

Result: partially strengthened

This report remained consistent with the previously sanitized field report on the decisive points:

- NAT preserved Windows -> Docker
- NAT failed native WSL2 -> Windows
- mirrored broke Windows -> Docker
- mirrored preserved WSL2 -> Docker
- NAT + tunnel restored native WSL2 -> Windows
- container -> tunnel remained unresolved

A second constrained workstation is still needed for a stronger public claim.

---

## New Observations Added By This Campaign

### 1. Preconditions matter for interpretation

This campaign began with no Windows HTTPS service on `8443`.

That forced a distinction between:

- service absence
- route failure

This distinction is valuable and should remain explicit in future reports.

### 2. Tunnel guardrails are useful

The CLI correctly refused to start a tunnel until something really listened on Windows port `8443`.

That behavior should be treated as a reliability feature, not just an implementation detail.

### 3. Forwarded Windows-visible ports can still be deceptive

When `localhostForwarding=true` is active, Windows-visible listeners may be implemented by WSL relay processes rather than by native Windows applications.

So a listening port on Windows does not always prove that a Windows-native service exists behind it.

### 4. Transparent proxy behavior is a real enterprise constraint

The container behavior in `F9` showed that a corporate environment can add another layer of failure on top of the core networking issue.

That does not invalidate the networking findings, but it does complicate the container story.

---

## Decision Outcome

At the end of this campaign, the repository fits this outcome from `docs/VALIDATION-PLAN.md`:

`Keep as native WSL2 workaround`

Why:

- the tunnel consistently restores `F8`
- the built-in WSL2 modes still leave an important gap
- container support remains unresolved and should not be overclaimed

---

## Environment Restoration

The campaign ended by:

1. stopping the `api` tunnel
2. removing the test nginx container
3. stopping the temporary Windows HTTPS server
4. restoring `.wslconfig` to NAT + `localhostForwarding=true`
5. shutting down WSL2 so the original mode was active again
6. leaving temporary test artifacts under a generic user temp directory, safe to delete

---

## Recommended Next Steps

1. Repeat the decisive subset `F4`, `F7`, `F8`, and `F9` on a second constrained workstation.
2. Re-test `F9` in an environment without a transparent proxy so the loopback-only listener problem can be isolated cleanly.
3. Document transparent-proxy interference in the troubleshooting guide.
4. Add one realistic service such as Elasticsearch only after the two-workstation baseline is stable.
