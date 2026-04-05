# Solution Plan

This document describes the next investigation phase:

- not just proving the limitation
- but actively trying to restore all required local-development flows

The current evidence suggests that `NAT + tunnel` is the most capable baseline so far:

- it preserves `Windows -> Docker published ports`
- it preserves `WSL2 -> Docker published ports`
- it restores `WSL2 -> Windows` through the tunnel
- but it still does not restore `container -> Windows`

So the next question is:

Why does the tunnel help native WSL2 workloads but not containers, and can that be fixed?

## Current Working Hypothesis

The current tunnel likely fails for containers because of two layers:

1. the SSH reverse forward listens only on WSL2 loopback by default
2. the container environment may add additional constraints such as proxy interception or name-resolution gaps

The first point is structural and must be addressed if containers are expected to use the tunneled endpoint.

The second point is environment-specific, but still relevant for enterprise workstations.

## Target Outcome

The target state is a configuration where all of the following are `OK`:

- `F1` Windows -> native WSL2 service
- `F2` Windows -> Docker published port
- `F3` WSL2 -> Docker published port
- `F4` WSL2 -> Windows service
- `F6` Container -> native WSL2 service
- `F7` Container -> Windows service
- `F8` WSL2 -> Windows via tunnel
- `F9` Container -> tunneled endpoint

If one configuration cannot satisfy everything, the next best outcome is:

- a documented primary mode for day-to-day work
- a documented fallback mode for specific microservices
- a precise explanation of the remaining gap

## Experiment Tracks

Run these tracks in order.

## Track 1 - Confirm the container limitation source

Goal:

- prove whether `F9` fails because the tunnel is loopback-only
- or because the enterprise environment blocks the path before it reaches WSL2

### Test 1.1 - Inspect tunnel listener scope

After `.\wsl-tunnel.ps1 up api`, run:

```powershell
wsl ss -ltn | grep 18443
```

Success criteria:

- if only `127.0.0.1:18443` and `[::1]:18443` appear, the listener is loopback-only

### Test 1.2 - Check whether a non-loopback listener fixes reachability

Keep the SSH tunnel as-is, then add a temporary bridge in WSL2 that exposes the tunnel beyond loopback.

Example with `socat`:

```bash
socat TCP-LISTEN:28443,fork,bind=0.0.0.0,reuseaddr TCP:127.0.0.1:18443
```

Then test from the container:

```bash
curl -k https://<wsl-ip>:28443
```

Success criteria:

- if this works, the core blocker was listener scope
- if this still fails, inspect proxying and routing next

### Test 1.3 - Check whether the container is traversing a proxy

From the container:

```bash
env | grep -i proxy
```

Then test both:

```bash
curl --noproxy '*' -vk https://<wsl-ip>:28443
curl -vk https://<wsl-ip>:28443
```

Success criteria:

- clearly distinguish direct failure, name-resolution failure, proxy interception, and TLS-only failure

## Track 2 - Try the simplest container-compatible runtime

Goal:

- see whether `network_mode: host` solves the problem without changing the tunnel architecture

Why this matters:

- if a container shares the WSL2 host network stack, it may be able to use `https://localhost:18443` directly

### Test 2.1 - Host-network client container

Run a one-shot client container in host mode:

```bash
docker run --rm --network host curlimages/curl:latest -k https://localhost:18443
```

Success criteria:

- if this works, then `NAT + tunnel + host-network containers` becomes a strong candidate solution

### Test 2.2 - Host-network service container

Take one representative technical microservice and run it with:

- `network_mode: host`
- no `ports:`
- dependency URL pointed to `https://localhost:18443`

Success criteria:

- the service can start and call the Windows dependency successfully
- the service does not create unacceptable port collisions

### Decision after Track 2

If host networking works reliably, the repository should document:

- `NAT + tunnel` as the baseline
- `network_mode: host` as the recommended container mode for dependency-heavy technical services

This may already be enough for a practical team solution, even if it is not a universal Docker answer.

## Track 3 - Make the tunnel explicitly container-facing

Goal:

- keep bridge-mode containers if possible
- expose the tunneled endpoint on a route they can actually consume

There are two sub-options.

### Option 3A - SSH-based exposure

Investigate whether the WSL2 SSH server can allow remote forwards to bind beyond loopback.

Relevant direction:

- `GatewayPorts clientspecified` or equivalent SSH server configuration
- remote forward bound to a non-loopback address in WSL2

Success criteria:

- `ss -ltn` shows a listener reachable beyond loopback
- a bridge-mode container can reach the forwarded port without additional relay processes

### Option 3B - Local relay process in WSL2

Keep the existing SSH tunnel on `127.0.0.1:18443`, then add an explicit relay such as:

- `socat`
- `rinetd`
- a minimal TCP proxy

Example target:

- relay `0.0.0.0:28443` -> `127.0.0.1:18443`

Then let containers call:

- `https://<wsl-ip>:28443`
- or `https://host.docker.internal:28443` if that is deliberately mapped

Success criteria:

- bridge-mode containers can use the Windows dependency through the relay
- the route is reproducible and understandable

## Track 4 - Improve host name and routing ergonomics

Goal:

- avoid hard-coding raw WSL2 IP addresses in application config

Experiments:

### Test 4.1 - Linux Docker host alias

Try a container with:

```yaml
extra_hosts:
  - "host.docker.internal:host-gateway"
```

Then test:

```bash
curl -k https://host.docker.internal:28443
```

Success criteria:

- the alias resolves correctly
- the routed endpoint is reachable without raw IP discovery

### Test 4.2 - Stable service naming in compose

If Test 4.1 works, document a team pattern where containers call:

- `https://host.docker.internal:<relay-port>`

instead of:

- dynamic WSL2 IPs

## Track 5 - Re-test with a real service

Goal:

- ensure the solution is not only valid for trivial curl checks

After a candidate solution works for `curl`:

1. test one representative technical service
2. test one second service with different runtime characteristics
3. only then update the repo claim

Suggested order:

- trivial client container
- one internal API-like service
- Elasticsearch or another realistic service

## Recommended Execution Order

Run the solution search in this order:

1. Track 1.1 - confirm loopback-only listener
2. Track 1.2 - temporary relay with `socat`
3. Track 1.3 - isolate proxy interference
4. Track 2.1 - host-network client container
5. Track 2.2 - host-network representative service
6. Track 3A - SSH `GatewayPorts` style exposure if you want a pure-SSH approach
7. Track 3B - explicit WSL2 relay if the SSH-only path is not viable
8. Track 4.1 - ergonomic host alias
9. Track 5 - validate with realistic services

## Success Criteria For A Practical Team Solution

The solution is good enough for team adoption if:

- developers can stay on one documented WSL2 mode for daily work
- Windows still reaches published container ports when needed
- native WSL2 workloads can reach Windows dependencies
- targeted containers can reach Windows dependencies
- the route used by containers is stable and documented
- startup can be scripted and reversed cleanly

## Candidate Outcomes

### Outcome A - `NAT + tunnel + host-network containers`

Use this if:

- host-network containers can consume `localhost:18443`
- port-collision risk remains acceptable

This is the simplest promising path.

### Outcome B - `NAT + tunnel + WSL2 relay + bridge containers`

Use this if:

- host networking is not acceptable
- a relay on `0.0.0.0:<relay-port>` works for bridge-mode containers

This is likely the cleanest path for broader Docker compatibility.

### Outcome C - Native WSL2 workaround only

Use this if:

- `F8` stays reliable
- but `F9` cannot be made reliable in the enterprise environment

If this is the result, the repository should state that honestly.

## Evidence To Capture For Every Experiment

For each step, record:

- exact config used
- exact command used
- exact output
- whether the container was bridge or host network
- whether the tunnel listener was loopback-only or non-loopback
- whether proxy variables or proxy behavior were observed
- whether the result helps `F7`, `F8`, `F9`, or all three
