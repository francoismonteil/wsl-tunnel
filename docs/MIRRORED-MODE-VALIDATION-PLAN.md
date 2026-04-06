# Mirrored Mode Validation Plan

This document defines a dedicated validation campaign for `networkingMode=mirrored`.

The goal is not to compare every WSL2 mode again.

The goal is to close the open questions around mirrored mode and decide, with confidence, whether mirrored can be a practical daily mode for this repository.

## Scope

This plan assumes:

- Docker is `Docker Engine` running inside the WSL2 distribution
- not Docker Desktop on Windows
- the workstation may be constrained by enterprise proxy and firewall policies

This distinction matters because mirrored-mode behavior must be validated against the Linux Docker engine that the repository actually targets.

## Why A Dedicated Mirrored Plan Exists

The current repository evidence shows a partial mirrored picture:

- native `Windows -> WSL2` looked good
- native `WSL2 -> Windows localhost` looked good
- `WSL2 -> Docker published port` looked good
- `Windows -> Docker published port` looked bad
- `container -> Windows` looked bad

That is useful, but still incomplete.

It does not yet prove whether mirrored itself is fundamentally unsuitable, or whether the remaining failures come from:

- a narrow set of tested routes
- one container shape only
- one published port only
- missing mirrored-specific settings
- Hyper-V firewall behavior
- proxy interception inside containers

## Primary Questions

This campaign should answer these questions:

1. Is the mirrored `Windows -> Docker published port` failure reproducible across more than one trivial container and more than one port?
2. Does mirrored work better with some container networking models than others?
3. Are mirrored-specific settings such as `hostAddressLoopback` or `ignoredPorts` relevant to the observed failures?
4. Is the remaining `container -> Windows` failure caused by mirrored itself, by routing, by proxy interception, or by the Windows-side listener scope?
5. Is `mirrored` alone enough for the repository goal, or does it still need the tunnel and/or a relay?

## Preconditions

Before running the campaign, confirm all of the following:

1. WSL is actually running in mirrored mode.
2. Docker Engine is running inside WSL2.
3. A real Windows HTTPS service is available on `8443`.
4. A native WSL2 HTTP fixture can run on `4200`.
5. At least two trivial container fixtures can run in WSL2.

## Configuration Under Test

Base `.wslconfig`:

```ini
[wsl2]
networkingMode=mirrored
```

Optional mirrored variants to test later in the campaign:

```ini
[wsl2]
networkingMode=mirrored
hostAddressLoopback=true
```

```ini
[wsl2]
networkingMode=mirrored
ignoredPorts=8080,8081,18443,28443
```

Notes:

- `hostAddressLoopback=true` matters when testing host IP reachability beyond `127.0.0.1`
- `ignoredPorts` matters only if a Windows-side port conflict may be interfering with Linux-side listeners
- do not combine optional mirrored settings in the first pass

## Fixtures

Use simple fixtures first.

- Windows HTTPS service on `8443`
- native WSL2 HTTP service on `4200`
- container A: `nginx:alpine` published as `8080:80`
- container B: second trivial HTTP container published as `8081:80`
- client-only container: `curlimages/curl:latest`
- optional host-network client container: `curlimages/curl:latest --network host`
- tunnel endpoint: `18443`
- optional relay endpoint: `28443`

## Verification Of Mode And Environment

Record these first:

- `wsl --status`
- `wsl -e sh -lc "ip addr && ip route"`
- `wsl -e docker version`
- `wsl -e docker info`
- `wsl -e docker network inspect bridge`
- `Get-Content $env:USERPROFILE\.wslconfig`

Success criteria:

- mirrored mode is explicitly configured
- Docker Engine is reachable from inside WSL2
- the Docker bridge gateway is known before container routing tests start

## Core Flows For Mirrored

These are the mirrored-mode flows that matter most.

| Id | Flow | Why it matters |
|----|------|----------------|
| M1 | Windows -> native WSL2 service | Confirms that mirrored native ingress is really active. |
| M2 | Windows -> Docker published port | The main suspected mirrored regression. |
| M3 | WSL2 -> Docker published port | Confirms the container is healthy inside WSL2 even if Windows cannot reach it. |
| M4 | WSL2 -> Windows via `localhost` | The main mirrored advantage for native workloads. |
| M5 | WSL2 -> Windows via host IP | Tests whether mirrored host-address routing is broader than `localhost`. |
| M6 | Container -> native WSL2 service | Confirms container -> WSL2 routing under mirrored. |
| M7 | Container -> Windows service | Core missing dependency path. |
| M8 | Windows -> Docker published port on second container and port | Confirms the regression is not tied to one image or port. |
| M9 | Container -> Windows via `host.docker.internal` | Tests hostname ergonomics separately from direct IP routing. |
| M10 | Mirrored + tunnel native path | Tests whether mirrored still benefits from the tunnel. |
| M11 | Mirrored + tunnel container path | Tests whether mirrored plus tunnel or relay helps containers. |

## Track 1 - Confirm Baseline Mirrored Behavior

Goal:

- revalidate the currently claimed mirrored wins
- revalidate the currently claimed mirrored losses

### Test 1.1 - Windows -> native WSL2 service

Start:

```bash
python3 -m http.server 4200 --bind 0.0.0.0
```

Then from Windows:

```powershell
curl.exe --connect-timeout 8 --max-time 20 http://localhost:4200
```

Success criteria:

- response body is returned
- proves mirrored native ingress is functioning

### Test 1.2 - Published container A

Run:

```bash
docker run --rm -d --name test-nginx-a -p 8080:80 nginx:alpine
```

Test from Windows:

```powershell
curl.exe --connect-timeout 8 --max-time 20 http://localhost:8080
curl.exe --connect-timeout 8 --max-time 20 http://127.0.0.1:8080
```

Test from WSL2:

```bash
curl --connect-timeout 8 --max-time 20 http://localhost:8080
```

Success criteria:

- record whether Windows fails while WSL2 succeeds
- record whether `localhost` and `127.0.0.1` differ

### Test 1.3 - Published container B on a second port

Run:

```bash
docker run --rm -d --name test-nginx-b -p 8081:80 nginx:alpine
```

Test:

```powershell
curl.exe --connect-timeout 8 --max-time 20 http://localhost:8081
curl.exe --connect-timeout 8 --max-time 20 http://127.0.0.1:8081
```

```bash
curl --connect-timeout 8 --max-time 20 http://localhost:8081
```

Success criteria:

- confirm whether mirrored breaks both published ports
- rule out an image-specific or port-specific failure

### Test 1.4 - Record container publishing state

Capture:

```bash
docker ps
docker port test-nginx-a
docker port test-nginx-b
ss -ltnp
```

Success criteria:

- container publish state is visible and explicit in the evidence

## Track 2 - Test Host Address Variants In Mirrored

Goal:

- determine whether the issue is limited to `localhost`
- determine whether host IP routing differs from loopback routing

### Test 2.1 - WSL2 -> Windows service via `localhost`

```bash
curl -vk --connect-timeout 8 --max-time 20 https://localhost:8443
```

### Test 2.2 - WSL2 -> Windows service via each Windows IPv4 address

From Windows, record the host IPv4 addresses. Then test from WSL2:

```bash
curl -vk --connect-timeout 8 --max-time 20 https://<windows-ip-a>:8443
curl -vk --connect-timeout 8 --max-time 20 https://<windows-ip-b>:8443
```

Success criteria:

- distinguish `localhost-only` success from true host-address success

### Test 2.3 - Repeat Track 2 with `hostAddressLoopback=true`

After updating `.wslconfig` and restarting WSL:

- re-run Test 2.2
- re-run Windows -> published-container checks if needed

Success criteria:

- determine whether host IP routing changes materially with this setting

## Track 3 - Container -> Windows In Mirrored

Goal:

- determine whether containers can consume Windows dependencies in mirrored mode
- separate direct-IP routing from hostname and proxy issues

### Test 3.1 - Direct IP path from a bridge-mode container

From the container:

```bash
docker exec test-nginx-a sh -lc "apk add --no-cache curl >/dev/null 2>&1 || true; curl --noproxy '*' -vk --connect-timeout 8 --max-time 20 https://<windows-ip-a>:8443"
docker exec test-nginx-a sh -lc "apk add --no-cache curl >/dev/null 2>&1 || true; curl --noproxy '*' -vk --connect-timeout 8 --max-time 20 https://<windows-ip-b>:8443"
```

Success criteria:

- classify the result as `timeout`, `refused`, `proxy`, `TLS`, or success

### Test 3.2 - Hostname path from a bridge-mode container

```bash
docker exec test-nginx-a sh -lc "apk add --no-cache curl >/dev/null 2>&1 || true; curl --noproxy '*' -vk --connect-timeout 8 --max-time 20 https://host.docker.internal:8443"
```

Success criteria:

- distinguish hostname-resolution problems from routing problems

### Test 3.3 - Proxy inspection inside the container

```bash
docker exec test-nginx-a sh -lc "env | grep -i proxy"
```

Then test both:

```bash
docker exec test-nginx-a sh -lc "curl --noproxy '*' -vk --connect-timeout 8 --max-time 20 https://<windows-ip-a>:8443"
docker exec test-nginx-a sh -lc "curl -vk --connect-timeout 8 --max-time 20 https://<windows-ip-a>:8443"
```

Success criteria:

- determine whether proxy variables materially change the result

### Test 3.4 - Client-only container instead of the published nginx container

```bash
docker run --rm curlimages/curl:latest --noproxy "*" -vk --connect-timeout 8 --max-time 20 https://<windows-ip-a>:8443
```

Success criteria:

- confirm whether the result depends on the published test container shape

## Track 4 - Mirrored And Docker Networking Variants

Goal:

- determine whether the default bridge model is the only failing model

### Test 4.1 - Host-network client container

```bash
docker run --rm --network host curlimages/curl:latest --noproxy "*" -vk --connect-timeout 8 --max-time 20 https://localhost:8443
```

Then:

```bash
docker run --rm --network host curlimages/curl:latest --noproxy "*" -vk --connect-timeout 8 --max-time 20 https://<windows-ip-a>:8443
```

Success criteria:

- determine whether host networking changes the mirrored result

### Test 4.2 - Published container checks after `ignoredPorts`

If Track 1 still shows `Windows -> Docker` failing:

1. set `ignoredPorts=8080,8081`
2. restart WSL
3. repeat Track 1.2 and Track 1.3

Success criteria:

- confirm whether port-listener conflicts were involved

Important interpretation:

- if `ignoredPorts` changes nothing, the regression is probably not a simple listener collision

## Track 5 - Hyper-V Firewall And Windows-Side Inspection

Goal:

- rule out Windows-side filtering that may look like a mirrored limitation

Capture from Windows:

```powershell
Get-NetFirewallProfile
Get-NetTCPConnection -State Listen | Where-Object { $_.LocalPort -in 4200,8080,8081,8443,18443,28443 }
```

If available in the environment, also capture Hyper-V firewall state relevant to mirrored networking.

Success criteria:

- evidence is sufficient to say whether packets are being refused, timed out, or never exposed

## Track 6 - Mirrored + Tunnel

Goal:

- determine whether mirrored should still be combined with the repository tunnel

### Test 6.1 - Native mirrored + tunnel

Start:

```powershell
.\wsl-tunnel.ps1 up api
```

Then from WSL2:

```bash
curl -vk --connect-timeout 8 --max-time 20 https://localhost:18443
```

Success criteria:

- determine whether mirrored gains anything beyond native `localhost:8443`

### Test 6.2 - Container -> tunnel endpoint in mirrored

From a bridge-mode container, try:

```bash
docker exec test-nginx-a sh -lc "curl --noproxy '*' -vk --connect-timeout 8 --max-time 20 https://host.docker.internal:18443"
```

Then direct WSL-side addresses if needed:

```bash
docker exec test-nginx-a sh -lc "curl --noproxy '*' -vk --connect-timeout 8 --max-time 20 https://<wsl-ip>:18443"
```

Success criteria:

- determine whether mirrored changes the old NAT+tunnel container outcome

### Test 6.3 - Mirrored + tunnel + relay

If Test 6.2 fails and the tunnel is loopback-only:

```bash
socat TCP-LISTEN:28443,fork,bind=0.0.0.0,reuseaddr TCP:127.0.0.1:18443
```

Then:

```bash
docker exec test-nginx-a sh -lc "curl --noproxy '*' -vk --connect-timeout 8 --max-time 20 https://<bridge-gateway-ip>:28443"
docker exec test-nginx-a sh -lc "curl --noproxy '*' -vk --connect-timeout 8 --max-time 20 https://<wsl-ip>:28443"
```

Success criteria:

- determine whether mirrored plus relay solves container access better than mirrored alone

## Track 7 - Realistic Service Recheck

Goal:

- prove the conclusion is not tied to curl-only trivial fixtures

After the best mirrored variant is identified:

1. run one representative application container
2. point it at the documented Windows dependency route
3. confirm the app actually starts and consumes the dependency

Success criteria:

- the chosen mirrored strategy works with at least one real application flow

## Evidence To Capture For Every Test

For each test, record:

- exact `.wslconfig`
- whether WSL was restarted after the config change
- exact command
- exact output
- whether the target service was independently healthy
- whether the container was bridge or host network
- whether proxy variables were present
- whether the result was `timeout`, `connection refused`, `proxy response`, `TLS failure`, or success

## Decision Outcomes

At the end of the campaign, classify mirrored into one of these outcomes.

### Outcome A - Mirrored is not acceptable for this repository

Use this if:

- `M2` stays `KO` across multiple ports and containers
- and the required container dependency path still stays `KO`

### Outcome B - Mirrored is acceptable for native-only workflows

Use this if:

- native `Windows <-> WSL2` flows are consistently `OK`
- but `Windows -> Docker published ports` or `container -> Windows` remain unreliable

### Outcome C - Mirrored is acceptable with explicit constraints

Use this if:

- the required flows work only with specific mirrored settings, host network, tunnel, relay, or direct-IP rules
- and those constraints are scriptable and documentable

### Outcome D - Mirrored can be a primary mode

Use this only if:

- `Windows -> WSL2` is `OK`
- `Windows -> Docker published ports` is `OK`
- `WSL2 -> Windows` is `OK`
- `container -> Windows` is `OK`
- the chosen route works with a real application container

## Recommended Execution Order

Run the mirrored investigation in this order:

1. verify mirrored mode and Docker Engine in WSL2
2. revalidate native mirrored wins
3. revalidate published-port failures with a second container and second port
4. test host IP variants with and without `hostAddressLoopback=true`
5. inspect proxy behavior inside containers
6. test bridge-mode and host-network containers
7. test `ignoredPorts` only if published-port behavior still looks suspicious
8. test mirrored + tunnel
9. test mirrored + tunnel + relay if needed
10. re-test the best candidate with a real service

## Final Questions

After the campaign, answer these explicitly:

1. Is mirrored alone enough for the repository goal?
2. If not, does mirrored plus tunnel or relay become worthwhile?
3. Is the `Windows -> Docker published port` failure a real mirrored regression on this workstation, or a narrower side effect?
4. Which mirrored settings, if any, materially changed the result?
5. Should mirrored remain in scope as a primary mode, a fallback mode, or only as a documented limitation?
