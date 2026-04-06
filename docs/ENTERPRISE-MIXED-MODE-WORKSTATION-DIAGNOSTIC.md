# Enterprise Mixed-Mode Workstation Diagnostic

Date: 2026-04-06  
Status: analysis and qualification document  
Related sources:

- [MIRRORED-MODE-VALIDATION-REPORT-2026-04-06.md](MIRRORED-MODE-VALIDATION-REPORT-2026-04-06.md)
- [CANDIDATE-SOLUTION-VALIDATION-REPORT-2026-04-06.md](CANDIDATE-SOLUTION-VALIDATION-REPORT-2026-04-06.md)
- [VALIDATION-MATRIX.md](VALIDATION-MATRIX.md)

---

## 1. Why This Document Exists

This document does not exist to "sell" `wsl-tunnel` as the default solution.

Its purpose is simpler:

- explain why some enterprise Windows workstations naturally lead teams to explore
  tunnel, relay, or workaround mechanisms
- describe the constraints observed on a real workstation
- provide a method to verify whether another workstation appears to match the same
  hypothesized constraint profile

In other words, this document addresses workstation context first.  
Solution design comes afterward.

It should let a reader answer three questions quickly:

1. am I in the right repository
2. does my workstation resemble the studied profile
3. if yes, which response category is worth exploring next

---

## 2. Working Hypothesis

The starting point is not:

> "The workstation is misconfigured, so we need a tool."

The starting point is closer to:

> "An enterprise Windows workstation can combine WSL2, Linux Docker Engine,
> corporate proxying, VPNs, network policy, and Windows-local services in a way
> that makes mixed-mode development incomplete or unstable."

In that situation, the question is no longer only "how do we make Docker work,"
but:

- which development flows must work
- which flows actually work on this workstation
- which flows fail repeatedly and under what conditions
- which workarounds are acceptable and which are not

---

## 3. What This Document Does Not Claim

This document does not claim any of the following:

- that every enterprise workstation has these constraints
- that `wsl-tunnel` is the best solution
- that workstation-specific misconfiguration is impossible
- that the observed failures come from a single root cause

It only provides a diagnostic frame for identifying a recurring constraint
profile in mixed `Windows + WSL2 + Docker Engine` development.

It does not provide proof that prevalence claims are justified beyond the
workstations actually compared with the same grid.

---

## 4. Target Workstation Profile

The profile addressed by this document looks like this:

- enterprise-managed Windows workstation
- WSL2 used to run the Linux development environment
- Docker Engine running inside WSL2
- no assumption that Docker Desktop is the primary reference model
- some tools or services still hosted on Windows
- some Windows services listening only on `localhost`
- containers may inherit a corporate proxy configuration
- the workstation may be subject to network, firewall, VPN, or filtering constraints

This profile matters because it creates several distinct execution zones:

- Windows
- native WSL2
- Docker bridge containers inside WSL2

The problem is not that these zones exist.  
The problem is that there may be no simple and reliable path between them for all
development use cases.

---

## 5. Conditions That Lead Teams to Explore Tunnel or Relay Solutions

Teams usually begin exploring this kind of solution when several observations
happen at the same time.

### 5.1 Windows Must Keep Reaching Docker

In many local workflows, Windows tools still need to call:

- a native WSL2 service published on `localhost`
- a Docker container published on `localhost:8080`, `localhost:3000`, and similar ports

In this repository's validation work, `NAT + localhostForwarding=true` is the mode
that best preserves this daily requirement.

### 5.2 WSL2 Sometimes Needs to Consume a Service That Still Lives on Windows

Typical examples:

- a local API hosted on Windows
- an enterprise proxy or Windows-only component
- a security tool or internal service available only on the Windows side

In `NAT` mode, `localhost` inside WSL2 does not point to Windows.  
That path can therefore be broken even when Windows still reaches WSL2 correctly.

### 5.3 Bridge Containers Do Not Behave Like Native WSL2 Processes

A bridge container:

- does not automatically share Windows `localhost`
- does not automatically share WSL2 `localhost`
- may be subject to different proxy rules
- may treat private IP traffic as something that should be routed through a
  corporate proxy

That means a flow such as `container -> Windows service` can fail for several
reasons at once:

- missing route
- Windows listener scoped only to `localhost`
- proxy interception
- firewall filtering
- differences between Linux Docker Engine and Docker Desktop behavior

### 5.4 Mirrored Mode Does Not Solve Everything

`networkingMode=mirrored` significantly improves native `Windows <-> WSL2` flows,
but the repository validation campaigns show that it can break an essential daily
workflow:

- `Windows -> Docker published ports`

So it is not enough to say "let's move everyone to mirrored mode."  
A gain on one path can break another path that matters just as much.

### 5.5 The Enterprise Workstation Adds Real Secondary Constraints

The validation work showed behavior consistent with a corporate environment:

- proxy variables injected into containers
- incomplete `NO_PROXY` coverage for private IP ranges
- `403` responses or proxy-auth behavior on traffic that should have stayed local
- network behavior that differs between `localhost`, private IPs, Docker bridge
  addresses, and host IPs

These observations are consistent with environment-level constraints, although
workstation-specific setup issues may still contribute.

---

## 6. Possible Causes Behind Observed Failures

Observed failures in this repository should not be attributed to one cause by
default.

They may result from one category or from a combination of categories.

### 6.1 Workstation Policy Constraints

Examples:

- corporate proxy injection into containers
- incomplete `NO_PROXY` coverage for private IP ranges
- firewall restrictions
- VPN routing side effects
- host policy that limits what can bind or listen outside `localhost`

These constraints come from the managed workstation environment rather than from
the application stack itself.

### 6.2 Mixed-Mode Architecture Tradeoffs

Examples:

- `NAT` preserving `Windows -> Docker published port` while not restoring
  `WSL2 -> Windows localhost`
- `mirrored` improving native Windows/WSL2 connectivity while degrading
  `Windows -> Docker published port`
- Docker bridge containers not sharing native loopback semantics
- listener scope differences between `localhost`, host IPs, and bridge-visible IPs

These are not necessarily workstation defects.  
They may be the result of real tradeoffs between networking models.

### 6.3 Local Misconfiguration or Incomplete Setup

Examples:

- incorrect `.wslconfig`
- WSL2 not actually running in the expected mode
- SSH to WSL2 not configured
- test fixtures not listening where expected
- Docker or container proxy settings incomplete or inconsistent

This category must remain on the table.  
The existence of a recurring constraint profile does not rule out simpler local
setup issues on a given workstation.

### 6.4 Practical Interpretation

For any given failed flow, the correct interpretation is usually:

- policy constraints may be involved
- mixed-mode architecture tradeoffs may be involved
- local misconfiguration may still be involved

This document therefore argues for explicit diagnosis, not automatic blame
assignment.

---

## 7. Typical Signatures of a Constrained Workstation

A workstation resembles this repository's profile when several of the following
signatures are observed.

| Signature | Meaning |
|----------|---------|
| `Windows -> WSL2 localhost` works | `localhostForwarding` or an equivalent mechanism is in place |
| `Windows -> Docker published port` works in NAT | the daily Windows -> Docker flow is preserved |
| `WSL2 -> Windows localhost` fails in NAT | WSL2 does not share Windows loopback |
| `WSL2 -> Windows localhost` works in mirrored | mirrored restores native loopback sharing |
| `Windows -> Docker published port` breaks in mirrored | mirrored is not an acceptable primary mode for this workflow |
| `container -> WSL2 native service` works | the Docker bridge can reach a correctly exposed WSL2 endpoint |
| `container -> Windows private IP` fails or times out | the direct container -> Windows path is not reliable |
| `container -> private IP` returns a proxy `403` | a corporate proxy is intercepting local private traffic |
| `host.docker.internal` does not help | this is not a Docker Desktop-like behavior model |

When those signatures accumulate, it becomes reasonable to investigate whether a
supported cross-zone mechanism is needed.

That investigation might lead to very different responses, for example:

- simplifying the development doctrine
- reducing the number of inter-zone flows
- relocating Windows-hosted components
- clarifying supported `NAT` and `mirrored` usage
- evaluating a targeted relay or tunnel only if a specific unsupported flow remains

This document does not attempt to rank those responses.  
It only explains why a mixed-mode workstation may need explicit diagnosis rather
than default assumptions.

---

## 8. Minimal Workstation Diagnostic

This section lets another developer verify whether their workstation has the same
constraints.

If the workstation does not resemble the studied profile after this section, the
reader should stop here rather than continue into tool implementation docs.

### 8.1 Basic Inventory

From Windows PowerShell:

```powershell
wsl --status
wsl -l -v
Get-Content $env:USERPROFILE\.wslconfig
```

Inside WSL2:

```bash
uname -a
ip addr
ip route
docker version
docker info
docker network inspect bridge
```

What should be recorded:

- WSL2 mode (`NAT` or `mirrored`)
- whether `localhostForwarding=true` is present
- whether a Linux Docker Engine is running inside WSL2
- the Docker bridge gateway
- the visible WSL2 addresses

### 8.2 Check Proxy Behavior Inside Containers

Inside WSL2:

```bash
docker run --rm alpine sh -lc 'env | grep -i proxy || true'
```

Interpretation:

- if no proxy variables appear, the workstation is less constrained on this axis
- if `HTTP_PROXY`, `HTTPS_PROXY`, and `NO_PROXY` appear, proxy handling must be
  treated as a real constraint
- if `NO_PROXY` does not include private IP ranges or the bridge subnet, local
  `container -> private IP` flows may be degraded

### 8.3 Minimal Test Fixtures

To classify a workstation, four fixtures are enough:

1. a native WSL2 service on `4200`
2. a container published on `8080`
3. a Windows service on `8443`
4. an HTTP client container for network tests

Example inside WSL2:

```bash
python3 -m http.server 4200 --bind 0.0.0.0
docker run --rm -d --name test-nginx -p 8080:80 nginx:alpine
```

For container connectivity tests, prefer a dedicated client image:

```bash
docker run --rm --network bridge curlimages/curl:latest --version
```

The Windows service can be:

- a real existing local service
- or a simple test service if the workstation allows it

### 8.4 Test Matrix

#### T1 - Windows -> native WSL2 service

From Windows:

```powershell
curl.exe --connect-timeout 8 --max-time 20 http://localhost:4200
```

If this is `OK`, Windows reaches native WSL2 correctly.

#### T2 - Windows -> Docker published port

From Windows:

```powershell
curl.exe --connect-timeout 8 --max-time 20 http://localhost:8080
```

If this is `OK` in NAT but `KO` in mirrored, the workstation shows the same
mirrored regression already observed in this repository.

#### T3 - WSL2 -> Docker published port

Inside WSL2:

```bash
curl --connect-timeout 8 --max-time 20 http://localhost:8080
```

If this is `OK`, the container is healthy on the Linux side even if Windows
cannot reach it.

#### T4 - WSL2 -> Windows service via localhost

Inside WSL2:

```bash
curl --noproxy '*' -vk --connect-timeout 8 --max-time 12 https://localhost:8443
```

Interpretation:

- `KO` in NAT: expected for this profile
- `OK` in mirrored: strong signature of shared Windows/WSL2 loopback

#### T5 - Container -> native WSL2 service

Inside WSL2, replacing `<bridge-gateway-ip>` with the observed Docker gateway:

```bash
docker run --rm --network bridge curlimages/curl:latest \
  --noproxy '*' --connect-timeout 8 --max-time 12 \
  http://<bridge-gateway-ip>:4200 -s -o /dev/null -w 'HTTP=%{http_code} ERR=%{errormsg}'
```

If this is `OK`, a bridge container can reach a correctly exposed WSL2 endpoint.

#### T6 - Container -> Windows service via private IP

First test with explicit proxy bypass:

```bash
docker run --rm --network bridge curlimages/curl:latest \
  --noproxy '*' -vk --connect-timeout 8 --max-time 12 \
  https://<windows-or-relay-ip>:8443
```

Then test without bypass if needed to observe default behavior:

```bash
docker run --rm --network bridge curlimages/curl:latest \
  -vk --connect-timeout 8 --max-time 12 \
  https://<windows-or-relay-ip>:8443
```

Interpretation:

- `403`, `407`, or a proxy-auth page: explicit proxy constraint
- timeout or `connection refused`: routing or listener-scope constraint
- success only with `--noproxy '*'`: the proxy is part of the problem

---

## 9. How To Recognize "The Same Problem"

Another workstation may be treated as a candidate for the same hypothesized
constraint profile if most of the following are true:

1. `Windows -> WSL2 localhost` works
2. `Windows -> Docker published port` works in NAT
3. `WSL2 -> Windows localhost` fails in NAT
4. `WSL2 -> Windows localhost` works in mirrored
5. `Windows -> Docker published port` stops working in mirrored
6. containers expose corporate proxy variables
7. `container -> private IP` fails without proxy bypass
8. a Windows service bound to `localhost` cannot be consumed directly from a
   bridge container

If that profile is confirmed, the workstation should be treated as a serious
candidate for this same hypothesized profile.  
That still does not prove that local misconfiguration is absent, but it does mean
the workstation should not be dismissed as a simple one-off developer error by
default. Additional workstation comparisons would still be needed before making
stronger empirical claims about prevalence.

---

## 10. What This Diagnostic Allows Us To Conclude

If a workstation appears to fall into this profile, the following conclusions may
be reasonable:

- the need for some explicit and supported way of handling certain flows may be real
- the problem should not automatically be reduced to "just use Docker better"
- WSL2 mode selection may involve tradeoffs between competing flows
- a corporate proxy may turn a local networking issue into an additional
  application-layer issue
- a tunnel or relay may be worth evaluating for a specific unsupported flow

At the same time, these conclusions remain diagnostic rather than absolute:

- they do not prove a universal enterprise pattern
- they do not prove a single root cause
- they do not prove that one tool should become the team standard
- they do not eliminate the possibility of workstation-specific setup issues

This document therefore supports explicit classification and comparison of mixed
workstation behavior.  
It is not intended to close the solution debate on its own.

Its credibility also depends on comparative evidence.  
If the goal is to show that this is not just one workstation behaving badly, the
next step is additional multi-workstation comparison rather than further wording
changes alone.

Use [MULTI-WORKSTATION-COMPARISON-KIT.md](MULTI-WORKSTATION-COMPARISON-KIT.md)
to keep that next step consistent.

---

## 11. What The Document Recommends Next

This is still a diagnostic document, not a response-prioritization document.

Its purpose is to justify explicit diagnosis and comparison of mixed-mode
workstations, not to argue that tunnels should be explored before doctrine
simplification, component relocation, or stricter support boundaries.

Before standardizing a tool, the team should define a simple doctrine:

- which components are allowed to run on Windows during development
- which components must run in WSL2 or Docker
- which inter-zone flows are officially supported
- which standard mechanism covers each supported flow
- which cases are explicitly forbidden because they are too fragile

For this repository, the minimal doctrine can be stated more concretely:

- the repository helps qualify a mixed-mode workstation where `NAT` and
  `mirrored` do not cover the same development flows
- the repository compares responses for Windows flows, native WSL2 flows, and
  bridge-container flows
- the repository does not claim to solve every WSL2 issue or establish a
  universal team standard
- a tool such as `wsl-tunnel` is relevant only after qualification, and only if
  a specific `WSL2 -> Windows` dependency path remains uncovered
- stronger language about prevalence or typicality should wait for at least one
  additional workstation compared with the same packet

If that doctrine makes the problem disappear, that is a good outcome.  
If it confirms a targeted need, then a tool such as `wsl-tunnel` can become
acceptable as a localized component rather than a general-purpose patch.

---

## 12. One-Sentence Summary

If an enterprise workstation repeatedly preserves `Windows -> Docker` in NAT,
breaks `WSL2 -> Windows localhost` in NAT, degrades `Windows -> Docker` in
mirrored, and exposes proxy interference on local container traffic, then the
workstation should be treated as a mixed-mode architecture problem to diagnose
explicitly, not as a simple developer error by default.
