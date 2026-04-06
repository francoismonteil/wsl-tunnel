# Candidate Solution Validation Plan

This document defines the next validation phase for the current candidate solution.

The goal is no longer to prove the problem exists.

The goal is to decide whether the repository has a practical, end-to-end solution that can be recommended to a team.

## Candidate Solution Under Test

The current candidate solution is:

1. WSL2 in `NAT` mode with `localhostForwarding=true`
2. Windows-hosted dependency exposed through the guided SSH tunnel
3. WSL2 relay process exposing the tunnel beyond loopback
4. containers reaching the relay through a direct RFC1918 IP

In compact form:

```text
container
  -> <bridge-gateway-ip>:<relay-port>
  -> relay inside WSL2
  -> 127.0.0.1:<tunnel-port>
  -> SSH reverse tunnel
  -> Windows localhost:<windows-port>
```

This plan is about confirming that this candidate works with a real service and under realistic proxy conditions.

## Primary Question

Can we make all required flows work together in one documented setup?

## Required Flows

The final solution should aim to satisfy all of these:

- `F1` Windows -> native WSL2 service
- `F2` Windows -> Docker published port
- `F3` WSL2 -> Docker published port
- `F4` WSL2 -> Windows service
- `F6` Container -> native WSL2 service
- `F7` Container -> Windows service
- `F8` WSL2 -> Windows via tunnel
- `F9` Container -> tunneled endpoint

## Preconditions

Before starting, confirm:

1. a real HTTPS service is listening on Windows `8443`
2. `ssh wsl-localhost` works from Windows
3. Docker Engine is running in WSL2
4. the test container image can run both with and without proxy overrides

## Test Fixtures

Use these fixtures for the final pass:

- Windows HTTPS service on `8443`
  - must be a real HTTPS service, not a raw TCP listener
  - expected successful response should be explicit, for example HTTP `200`, `401`, or a small JSON payload
- native WSL2 HTTP service on `4200`
- Docker bridge-mode test container on `8080:80`
- tunnel endpoint on `18443`
- relay endpoint on `28443`

## Validation Profiles

Run the final validation in two profiles.

### Profile A - Proxy unmanaged

This profile captures behavior with the workstation’s normal proxy conditions.

Purpose:

- verify whether the solution already works in the raw enterprise environment

### Profile B - Proxy managed

This profile captures behavior after you deliberately apply the proxy strategy you believe is correct.

Examples:

- explicit `NO_PROXY` values
- adjusted container environment variables
- relay access through direct IP only
- any Docker-side proxy configuration you intentionally control

Purpose:

- verify whether proxy control turns the candidate into a reliable solution

## Final Matrix

Run the same matrix for both profiles when possible.

| Flow | What to test | Expected result for acceptance |
|------|---------------|--------------------------------|
| F1 | Windows -> native WSL2 `4200` | `OK` |
| F2 | Windows -> Docker `8080` | `OK` |
| F3 | WSL2 -> Docker `8080` | `OK` |
| F4 | WSL2 -> Windows `8443` without tunnel | `KO` in NAT is acceptable, because the tunnel replaces it |
| F6 | Container -> native WSL2 `4200` | `OK` |
| F7 | Container -> Windows `8443` without relay/tunnel | `KO` is acceptable if the documented route is `F9` |
| F8 | WSL2 -> tunnel `18443` | `OK` |
| F9 | Container -> relay or tunneled endpoint | `OK` |

Important interpretation rule:

- `F4` and `F7` may remain `KO` in raw NAT if the documented supported route is the tunnel path
- the candidate solution is acceptable if the documented path is reliable and repeatable

## Execution Steps

Run in this order.

### Step 1 - Confirm baseline NAT still preserves the useful flows

Check:

- `F1`
- `F2`
- `F3`
- `F6`

Success criteria:

- these remain `OK`

If they fail, stop. The baseline is no longer stable enough.

### Step 2 - Start the real Windows service and confirm health

From Windows:

```powershell
curl.exe -vk --connect-timeout 8 --max-time 20 https://localhost:8443
```

Success criteria:

- real HTTPS response received
- no ambiguity about whether the target service exists

### Step 3 - Start the tunnel and validate native WSL2 path

Commands:

```powershell
.\wsl-tunnel.ps1 up api
.\wsl-tunnel.ps1 status api
wsl curl -vk --connect-timeout 8 --max-time 20 https://localhost:18443
```

Success criteria:

- tunnel starts cleanly
- `F8` is `OK`
- returned data clearly comes from the real Windows HTTPS service

### Step 4 - Start the relay and confirm listener scope

Example:

```bash
socat TCP-LISTEN:28443,fork,bind=0.0.0.0,reuseaddr TCP:127.0.0.1:18443
```

Check:

```bash
ss -ltn | grep 28443
```

Success criteria:

- relay listens on a non-loopback address

### Step 5 - Validate `F9` from a bridge-mode container

Primary route:

```bash
curl -vk https://<bridge-gateway-ip>:28443
```

Optional secondary route:

```bash
curl -vk https://<wsl-ip>:28443
```

Success criteria:

- the container reaches the real HTTPS service through the relay and tunnel
- the result is an actual service response, not just a TCP or TLS fixture signal

### Step 6 - Compare unmanaged vs managed proxy

Run Step 5 twice:

- once with the default environment
- once with the proxy strategy you intentionally apply

Capture:

- env proxy variables inside the container
- exact curl output
- whether the path succeeds only with direct IPs
- whether hostname-based access remains blocked

Success criteria:

- determine whether proxy control is required for the final documented setup

### Step 7 - Validate with one representative application container

Use one real service container, not just curl.

Requirements:

- it runs in bridge mode
- it points to the documented relay endpoint
- it successfully calls the Windows dependency in startup or runtime behavior

Success criteria:

- the app works without manual debugging or ad hoc shell intervention

## Acceptance Levels

Use these decision levels at the end.

### Level 1 - Native-only solution

Conditions:

- `F8 = OK`
- `F9 = KO`

Meaning:

- useful workaround for native WSL2 workloads only

### Level 2 - Container-capable solution with constraints

Conditions:

- `F8 = OK`
- `F9 = OK`
- but only through direct IP and/or proxy management

Meaning:

- acceptable team solution if the constraints are clearly documented

### Level 3 - Recommended team solution

Conditions:

- `F1`, `F2`, `F3`, `F6`, `F8`, `F9` all `OK`
- a real application container works
- startup and teardown can be scripted

Meaning:

- the repo can confidently describe the solution as practical and repeatable

## Evidence To Capture

For each final run, record:

- `.wslconfig`
- whether profile A or B was used
- exact Windows service response on `8443`
- exact tunnel output
- exact relay command
- `ss -ltn` output proving listener scope
- container proxy environment
- exact container curl output
- exact application-container behavior

## Decision Questions At The End

After running the plan, answer these:

1. Does the relay + tunnel + direct-IP route work against a real HTTPS service?
2. Is proxy management required, optional, or irrelevant?
3. Is the route stable enough to document for a team?
4. Can the relay be automated in `wsl-tunnel.ps1` without making the tool confusing?
5. Does the repository now have a full solution, or a constrained but useful one?
