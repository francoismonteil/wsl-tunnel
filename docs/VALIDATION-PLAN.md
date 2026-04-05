# Validation Plan v2

This document defines a broader validation campaign for deciding whether the problem behind this repository is real, reproducible, and worth solving as a public project.

Use it as the planning companion to:

- `docs/VALIDATION-MATRIX.md` for already observed results
- `docs/LOCAL-PRACTICAL-TESTS.md` for step-by-step workstation checks
- `docs/LOCAL-PRACTICAL-TEST-REPORT.md` for one sanitized field report

## Why A v2 Plan Exists

The current recorded tests are useful, but they are still too narrow to support strong claims.

A representative campaign must separate:

1. native WSL2 behavior
2. container behavior inside WSL2
3. Windows -> WSL2 ingress
4. WSL2 or container -> Windows egress
5. tunnel behavior for native workloads
6. tunnel behavior for containerized workloads

Without that separation, it is too easy to confuse:

- a real WSL2 networking limitation
- a Docker configuration issue
- a service binding issue
- a TLS or certificate issue
- a tunnel exposure issue

## Validation Objectives

The campaign should answer these questions:

1. Can native WSL2 reliably consume a Windows-hosted dependency?
2. Can a container inside WSL2 reliably consume a Windows-hosted dependency?
3. Can Windows reliably consume a Docker-published service running in WSL2?
4. Does the tunnel restore the missing native WSL2 path?
5. Can the tunnel be made usable for containers too, or is it only a native WSL2 workaround?
6. Are the results specific to one workstation, or reproducible on several constrained machines?

## Test Dimensions

The matrix should vary one dimension at a time.

### 1. WSL2 networking mode

Primary modes:

- NAT + `localhostForwarding=true`
- NAT + `localhostForwarding=false`
- mirrored

Workaround modes:

- NAT + tunnel
- mirrored + tunnel

### 2. Docker networking model

Start simple, then add variants only if needed.

Primary container modes:

- default bridge + `ports:`
- client-only container with no published ports

Optional variants:

- `network_mode: host` when available in the target environment
- a second published port to confirm that a failure is not tied to one port number

### 3. Target service shape

Do not validate everything against one business service only.

Use at least:

- trivial HTTP service
- Windows-hosted HTTPS service on `8443`
- one realistic service after the trivial fixtures are stable, such as Elasticsearch

### 4. Tunnel exposure model

This dimension is critical because the current tunnel results suggest a difference between:

- a loopback-only endpoint in WSL2
- an endpoint reachable from containers

At minimum, distinguish:

- tunnel reachable only on `127.0.0.1` in WSL2
- tunnel plus an additional bridge, proxy, or listener that exposes the endpoint beyond loopback

## Core Flows

These are the flows that matter most for local development.

| Id | Flow | Why it matters |
|----|------|----------------|
| F1 | Windows -> native WSL2 service | Confirms the baseline Windows -> WSL2 path. |
| F2 | Windows -> Docker published port | Confirms whether Windows can still consume containerized services. |
| F3 | WSL2 -> Docker published port | Sanity check for workloads that stay fully inside WSL2. |
| F4 | WSL2 -> Windows service via `localhost` | Most intuitive developer expectation. |
| F5 | WSL2 -> Windows service via Windows IP | Baseline host-address fallback. |
| F6 | Container -> native WSL2 service | Important for mixed native/containerized local stacks. |
| F7 | Container -> Windows service | Core business need for many dependency setups. |
| F8 | WSL2 -> Windows service via tunnel | Proves whether the workaround closes the native gap. |
| F9 | Container -> tunneled endpoint | Proves whether the workaround helps containers or only native WSL2. |

## Recommended Fixtures

Keep the same logical roles across all workstations:

- Windows service: HTTPS on `8443`
- native WSL2 service: HTTP on `4200`
- trivial Docker service: `nginx:alpine` on `8080:80`
- optional realistic Docker service: Elasticsearch on `9200:9200`
- tunnel endpoint in WSL2: `18443 -> 8443`

## Minimum Representative Campaign

If time is limited, run this smaller matrix first.

### Campaign A: core WSL2 modes

| Configuration | F1 | F2 | F3 | F4 | F5 | F6 | F7 | F8 | F9 |
|---------------|----|----|----|----|----|----|----|----|----|
| NAT + `localhostForwarding=true` | required | required | required | required | required | required | required | N/A | N/A |
| mirrored | required | required | required | required | required | required | required | N/A | N/A |
| NAT + tunnel | optional reuse for F1-F7 | optional reuse for F1-F7 | optional reuse for F1-F7 | N/A | N/A | optional reuse for F1-F7 | required | required | required |

This is the smallest campaign that can justify keeping the project alive.

### Campaign B: confidence boosters

Run these after Campaign A:

- repeat mirrored `F2` with a second trivial container and a second published port
- repeat `F7` with a client-only container instead of only the published nginx container
- repeat `F8` and `F9` with a container-facing exposure method for the tunnel, not just loopback
- run the decisive configurations on a second workstation

## Acceptance Criteria By Objective

### Objective O1: prove the problem is real

The problem is legitimate if you can show all of the following on at least one constrained workstation:

- one built-in WSL2 mode preserves `F2` but fails `F4` or `F7`
- another built-in WSL2 mode fixes `F4` but breaks `F2`
- the same Docker container remains healthy and reachable from WSL2 while Windows loses access to it

### Objective O2: prove the tunnel has value

The tunnel is valuable if:

- `F8` is `OK` in a configuration where `F4` and `F5` are `KO`

### Objective O3: prove the tunnel helps containers

Container support should only be claimed if:

- `F9` is `OK`
- the route used by the container is explicit and reproducible
- the endpoint is not relying on accidental workstation-specific behavior

If `F9` remains `KO`, the project should describe itself as a native WSL2 workaround first, not a full container solution.

### Objective O4: prove the findings are not workstation-specific

The public claim becomes much stronger if:

- the decisive failures and wins are reproduced on at least two constrained workstations

## Execution Order

Run the campaign in this order:

1. Validate the Windows service itself.
2. Validate the native WSL2 service itself.
3. Validate the trivial Docker container in NAT.
4. Validate the same trivial Docker container in mirrored.
5. Validate native WSL2 -> Windows in NAT.
6. Validate native WSL2 -> Windows in mirrored.
7. Validate container -> Windows in NAT.
8. Validate container -> Windows in mirrored.
9. Validate NAT + tunnel for native WSL2.
10. Validate NAT + tunnel for containers with a clearly documented exposure method.
11. Repeat the decisive subset on a second workstation.

## Logging Rules

For every line in the matrix, capture:

- the exact command
- the exact response or exact error
- whether the target service was verified healthy independently
- the Docker port mapping when a container was involved
- the WSL2 mode and relevant `.wslconfig` snippet
- if tunnel used: the exact tunnel command and listener scope

## Common False Positives To Avoid

Do not turn these into repository claims without isolating them first:

- one service only works because it binds to `0.0.0.0`
- one service only fails because it binds to `127.0.0.1`
- one path fails because of TLS or certificate trust, not because of routing
- one container succeeds because of a cached DNS or proxy setting
- one tunnel test fails only because the listener is loopback-only inside WSL2

## Decision Outcomes

At the end of the campaign, classify the project into one of these outcomes:

1. `Keep as native WSL2 workaround`
The tunnel consistently restores `F8`, but container support remains unresolved.

2. `Keep and extend to container support`
Both `F8` and `F9` are reproducibly solved.

3. `Reposition as diagnostic/documentation project`
The tunnel is not consistently the right fix, but the validation framework still provides value.

4. `Archive or narrow the claim`
The failures turn out to be too workstation-specific or too dependent on local configuration mistakes.
