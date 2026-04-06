# Validation Matrix

This document consolidates the validated behavior recorded in:

- `public/docs/CANDIDATE-SOLUTION-VALIDATION-REPORT-2026-04-06.md`
- `public/docs/MIRRORED-MODE-VALIDATION-REPORT-2026-04-06.md`

The goal is to answer one practical question for constrained enterprise workstations:

> Which mechanism allows which concrete development flow, exactly?

## Reading Guide

Legend:

- `OK` = explicitly validated and works
- `KO` = explicitly validated and fails
- `Partial` = transport works but application constraints still block the end result
- `Conditional` = works only with explicit additional constraints
- `N/A` = not relevant for that configuration

Enterprise constraints observed during the campaigns:

- Docker runs as Linux Docker Engine inside WSL2, not Docker Desktop
- corporate proxy variables are injected into containers
- private IPs are not covered by default `NO_PROXY`
- some Windows listeners are restricted to `localhost` only

## Executive Matrix

| Configuration / Mechanism | Windows -> native WSL2 service | Windows -> Docker published port | WSL2 -> Windows via `localhost` | Bridge container -> Windows service | What it is good for | Main blocking constraint |
|---|---|---|---|---|---|---|
| NAT + `localhostForwarding=true` | `OK` | `OK` | `KO` | `KO` | Standard local dev where Windows must reach Docker in WSL2 | Windows dependency remains unreachable from WSL2 and containers |
| NAT + SSH tunnel | `OK` | `OK` | `OK` via `localhost:18443` | `KO` | Native WSL2 workloads that must consume a Windows-local service | Tunnel listener stays loopback-only in WSL2 |
| NAT + SSH tunnel + `socat` relay + proxy bypass | `OK` | `OK` | `OK` via `localhost:18443` | `OK` | Full bridge-container access to a Windows dependency in constrained enterprise setup | Requires relay and explicit proxy management |
| Mirrored | `OK` | `KO` | `OK` | `KO` | Native Windows <-> WSL2 workflows over shared loopback | Windows -> Docker published ports break structurally |
| Mirrored + container `--network host` | `OK` | `KO` | `OK` | `OK` via container `localhost` | Single-container cases where a container must consume Windows as if it were native WSL2 | Loses bridge isolation and published-port ergonomics |
| Mirrored + direct `socat` relay to Windows loopback | `OK` | `KO` | `OK` | `Partial` | Proof that container -> Windows transport can exist without SSH tunnel | Windows service must accept non-`localhost` hostnames / wildcard binding |

## Capability Table By Flow

| Flow | NAT | NAT + tunnel | NAT + tunnel + relay | Mirrored | Mirrored + host-network container | Mirrored + direct relay |
|---|---|---|---|---|---|---|
| Windows -> native WSL2 service | `OK` | `OK` | `OK` | `OK` | `OK` | `OK` |
| Windows -> Docker published port | `OK` | `OK` | `OK` | `KO` | `KO` | `KO` |
| WSL2 -> Docker published port | `OK` | `OK` | `OK` | `OK` | `OK` | `OK` |
| WSL2 -> Windows service via `localhost` | `KO` | `OK` | `OK` | `OK` | `OK` | `OK` |
| WSL2 -> Windows service via Windows IP | `KO` | `NR` | `NR` | `KO` | `KO` | `KO` |
| Bridge container -> native WSL2 service | `OK` | `OK` | `OK` | `OK` | `N/A` | `OK` |
| Bridge container -> Windows service | `KO` | `KO` | `OK` | `KO` | `N/A` | `Partial` |
| Bridge container -> tunneled endpoint | `N/A` | `KO` | `OK` | `KO` | `N/A` | `N/A` |
| Host-network container -> Windows via `localhost` | `OK` | `OK` | `OK` | `OK` | `OK` | `OK` |

Notes:

- `NAT + tunnel + relay` means:
  `container -> <bridge-gateway-ip>:28443 -> socat -> 127.0.0.1:18443 -> SSH reverse tunnel -> Windows localhost:8443`
- `Mirrored + direct relay` means:
  `container -> <docker-bridge-ip>:28443 -> socat in WSL2 -> 127.0.0.1:8443 -> Windows localhost:8443`
- In mirrored mode, the direct relay proved TCP connectivity, but HTTP failed with `400 Bad Request - Invalid Hostname` because the Windows test service was bound to `http://localhost:8443/`

## What Each Mechanism Really Enables

| Mechanism | Concrete capability enabled | What it does not solve | Enterprise-specific condition |
|---|---|---|---|
| NAT + `localhostForwarding` | Lets Windows tools access WSL2 native services and Docker published ports on `localhost` | Does not let WSL2 or bridge containers consume a Windows-local dependency | None beyond standard WSL NAT behavior |
| SSH reverse tunnel (`wsl-tunnel.ps1`) | Recreates a WSL2-local endpoint for a Windows-local service | Does not expose that endpoint to bridge containers by itself | WSL2 must stay alive; sshd/tunnel stability matters |
| `socat` relay in WSL2 | Exposes a loopback-only endpoint to bridge containers on `0.0.0.0:<relay-port>` | Does not fix proxy interception or Windows app-layer hostname restrictions | Must bypass proxy for RFC1918 / relay IPs |
| Mirrored networking | Gives shared-loopback ergonomics between native Windows and native WSL2 processes | Does not preserve Windows -> Docker published ports with Linux Docker Engine in WSL2 | Structural limitation with Docker published-port path |
| Docker `--network host` in WSL2 | Makes a container behave like a native WSL2 process for `localhost` access | Does not help Windows reach Docker published ports; reduces isolation | Only suitable when host-network tradeoffs are acceptable |
| Windows service wildcard bind (`http://+:8443/` or equivalent) | Makes mirrored relay and non-`localhost` access viable at application level | Does not itself create the container routing path | Often requires admin rights or server reconfiguration |
| Proxy bypass (`--noproxy '*'` or extended `NO_PROXY`) | Prevents enterprise proxy from hijacking private-IP container traffic | Does not fix routing by itself | Mandatory for container -> relay/private-IP access |

## Decision Table

| Need | Best validated option | Why |
|---|---|---|
| Keep Windows -> Docker on `localhost` working | NAT | This is the only fully validated mode where Windows still reaches Docker published ports reliably |
| Let native WSL2 processes consume a Windows-local service | Mirrored or NAT + tunnel | Mirrored is simpler for native flows; NAT + tunnel preserves Docker ergonomics |
| Let bridge-mode containers consume a Windows-local service on a constrained workstation | NAT + tunnel + relay + proxy bypass | This is the only fully validated end-to-end bridge-container solution in the recorded enterprise setup |
| Let a single container consume Windows quickly, without relay | Mirrored + `--network host` | Validated and simple, but only if host-network constraints are acceptable |
| Use mirrored as the primary mode for this repository | Not recommended | It breaks Windows -> Docker published ports, which is a core daily workflow |

## Practical Conclusions

| Question | Answer |
|---|---|
| What solves native Windows <-> WSL2 communication best? | `mirrored`, as long as Docker published ports are not part of the requirement |
| What solves Windows -> Docker in WSL2 best? | `NAT + localhostForwarding=true` |
| What solves bridge container -> Windows service in an enterprise-constrained setup? | `NAT + tunnel + socat relay + proxy bypass` |
| What is the main blocker in mirrored for this repository? | Windows can no longer reach Docker published ports |
| What is the main blocker for containers in enterprise environments? | Corporate proxy interception plus loopback-only listeners |

## Recommended Positioning For This Repository

| Option | Recommendation | Rationale |
|---|---|---|
| NAT | Primary mode | Best overall compatibility with Docker published ports and validated tunnel/relay workaround |
| NAT + tunnel + relay | Supported enterprise workaround | Only validated bridge-container path to Windows dependency under corporate restrictions |
| Mirrored | Documented limitation / niche mode | Good for native flows, but not for the repository's main containerized use case |
| Mirrored + host-network container | Tactical workaround | Useful for isolated cases, not a general repository-wide operating mode |

## Detailed Directional Matrix

This section answers the question in the most literal way: who can reach whom, through which form of address, and in which validated configuration.

| Source -> Target | Address / Route Tested | NAT | NAT + tunnel | NAT + tunnel + relay | Mirrored | Mirrored + host-network container | Notes |
|---|---|---|---|---|---|---|---|
| Windows -> WSL2 native service | `localhost:4200` | `OK` | `OK` | `OK` | `OK` | `OK` | Validated with Python HTTP server in WSL2 |
| Windows -> WSL2 native service | WSL2 IP | `NR` | `NR` | `NR` | `NR` | `NR` | No explicit validation recorded |
| Windows -> containerized app in WSL2 | `localhost:8080` / `localhost:8081` published port | `OK` | `OK` | `OK` | `KO` | `KO` | Core mirrored regression validated on two ports |
| Windows -> containerized app in WSL2 | Container IP directly | `NR` | `NR` | `NR` | `NR` | `NR` | Not part of the recorded campaigns |
| WSL2 native -> Windows service | `localhost:8443` | `KO` | `OK` via `localhost:18443` | `OK` via `localhost:18443` | `OK` | `OK` | In mirrored, shared loopback works natively |
| WSL2 native -> Windows service | Windows host IP | `KO` | `NR` | `NR` | `KO` | `KO` | Explicit IP path failed in recorded tests |
| WSL2 native -> containerized app in WSL2 | `localhost:8080` published port | `OK` | `OK` | `OK` | `OK` | `OK` | Container health remained good in every mode |
| WSL2 native -> native WSL2 service | `localhost:4200` | `OK` | `OK` | `OK` | `OK` | `OK` | Trivial but validated in mirrored report |
| Bridge container -> native WSL2 service | WSL2 IP / bridge-visible endpoint | `OK` | `OK` | `OK` | `OK` | `N/A` | Validated on `4200` |
| Bridge container -> Windows service | Windows/NAT/mirrored host IP | `KO` | `KO` | `NR` | `KO` | `N/A` | Direct route fails in both native modes |
| Bridge container -> Windows service | `host.docker.internal` | `KO` | `KO` | `NR` | `KO` | `N/A` | Docker Engine in WSL2 did not provide a usable route here |
| Bridge container -> Windows service | Tunnel endpoint `:18443` | `N/A` | `KO` | `NR` | `KO` | `N/A` | Tunnel listener is loopback-only in WSL2 |
| Bridge container -> Windows service | Relay endpoint `:28443` | `N/A` | `N/A` | `OK` | `Partial` | `N/A` | In mirrored, TCP succeeded but HTTP failed on Windows hostname restriction |
| Host-network container -> Windows service | `localhost:8443` | `OK` | `OK` | `OK` | `OK` | `OK` | Behaves like native WSL2 networking |
| Host-network container -> Windows service | Windows host IP | `NR` | `NR` | `NR` | `KO` | `KO` | Explicit-IP mirrored test failed |

## Enterprise And Egress Matrix

These rows separate generic reachability from enterprise-policy side effects such as proxies, private IP filtering, and hostname restrictions.

| Flow | NAT | NAT + tunnel | NAT + tunnel + relay | Mirrored | What is actually known |
|---|---|---|---|---|---|
| WSL2 native -> Internet | `NR` | `NR` | `NR` | `NR` | Not directly validated in the published reports |
| WSL2 native -> enterprise network by private IP | `NR` | `NR` | `NR` | `NR` | Not directly validated as a standalone flow |
| WSL2 native -> Windows-local enterprise dependency | `KO` | `OK` | `OK` | `OK` | This is the central validated business case |
| Bridge container -> Internet | `NR` | `NR` | `NR` | `NR` | No explicit generic internet probe was recorded |
| Bridge container -> enterprise proxy | `Conditional` | `Conditional` | `Conditional` | `Conditional` | Proxy variables were injected into containers and traffic attempted to use them |
| Bridge container -> private RFC1918 address without proxy bypass | `KO` | `KO` | `KO` | `KO` | Observed proxy refusal / 403 on private-IP CONNECT attempts |
| Bridge container -> private RFC1918 address with proxy bypass | `Conditional` | `Conditional` | `OK` | `Conditional` | Works only when routing exists and `NO_PROXY` / `--noproxy` is managed |
| Bridge container -> enterprise Windows dependency on `localhost` only | `KO` | `KO` | `OK` | `Partial` | Mirrored direct relay needs Windows service to accept non-`localhost` hostnames |

## Interpretation Notes For Enterprise Context

| Constraint | Effect |
|---|---|
| Corporate proxy injected into containers | Private-IP requests may be sent to the proxy instead of directly to WSL2/Windows |
| `NO_PROXY` missing RFC1918 ranges | Container access to relay or host private IPs fails even when routing is otherwise correct |
| Windows service bound only to `localhost` | Relay can prove TCP reachability but still fail at HTTP or TLS hostname handling |
| Linux Docker Engine inside WSL2 | `host.docker.internal` behavior is not the same as Docker Desktop and cannot be assumed |
| Mirrored loopback path | Great for native Windows <-> WSL2, but it does not preserve Windows -> Docker published ports |

## What Is Still Not Validated

The reports do not yet provide publishable proof for these rows:

- `WSL2 native -> Internet`
- `WSL2 native -> enterprise network` as a general capability outside the tested Windows-local service
- `Bridge container -> Internet`
- `Windows -> WSL2 by explicit WSL IP`
- `Windows -> container by direct container IP`

Those should stay marked `NR` until a dedicated test report records exact commands and outputs.
