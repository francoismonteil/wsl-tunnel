# Mixed-Mode Windows + WSL2 + Docker Engine Connectivity

Repository of investigation and qualification for mixed-mode Windows + WSL2 +
Docker Engine development, including a targeted workaround when a specific flow
remains unsupported.

## Three Fast Reader Questions

### 1. Am I In The Right Place?

You are in the right place if your local development setup mixes:

- Windows-hosted tools or dependencies
- WSL2 for the Linux development environment
- Linux Docker Engine running inside WSL2
- uncertainty about which flows should stay supported across Windows, native
  WSL2, and bridge containers

You are probably not in the right place if native WSL2 networking already covers
your required flows without special handling.

### 2. Does My Workstation Look Like The Studied Profile?

The studied profile is not "all WSL2 problems."

It is a narrower mixed-mode workstation shape where:

- `NAT` and `mirrored` do not fail in the same place
- Windows may still need to reach Docker-published ports in WSL2
- native WSL2 may still need to consume a Windows-hosted dependency
- bridge containers may add proxy and routing constraints on top

Use the diagnostic and validation matrix before reading the tunnel docs:

- [docs/ENTERPRISE-MIXED-MODE-WORKSTATION-DIAGNOSTIC.md](docs/ENTERPRISE-MIXED-MODE-WORKSTATION-DIAGNOSTIC.md)
- [docs/VALIDATION-MATRIX.md](docs/VALIDATION-MATRIX.md)
- [docs/README.md](docs/README.md)

### 3. If So, Which Response Is Worth Exploring?

This repository compares several response paths, for example:

- keep `NAT` as the primary mode
- use `mirrored` for native-only cases where its tradeoffs are acceptable
- reduce mixed Windows/WSL2 dependencies through doctrine simplification
- relocate Windows-hosted components when that is the cleaner answer
- use relay or proxy strategy where container reachability is the actual issue
- use `wsl-tunnel.ps1` only for a specific unsupported `WSL2 -> Windows` path

The repository is therefore about qualification first and response comparison
second. The tunnel is one conditional response path, not the repository's
identity.

## Problem This Repository Addresses

On some constrained workstations, `NAT` and `mirrored` do not fail in the same
place.

The validated problem in this repository is that:

- `NAT` can preserve `Windows -> Docker published port`
- but `NAT` may still leave `WSL2 -> Windows localhost` unavailable
- `mirrored` can improve native `Windows <-> WSL2` communication
- but `mirrored` can also break `Windows -> Docker published port`

That creates a mixed-mode gap where:

- Windows can still reach some WSL2 or Docker workloads
- native WSL2 can still reach some local services
- but one required dependency path remains uncovered

## When To Stop Reading

Stop here if your environment already gives you:

- stable `Windows -> Docker published port`
- stable `WSL2 -> Windows` access for the dependencies you need
- no bridge-container gap that matters to your workflow

In that case, this repository is probably not the right starting point and you
do not need the tunnel component.

## Minimal Repository Doctrine

This repository helps qualify:

- a mixed Windows + WSL2 + Docker Engine workstation where `NAT` and `mirrored`
  cover different flows
- the tradeoffs between Windows flows, native WSL2 flows, and bridge-container
  flows
- candidate responses for one remaining unsupported path

This repository does not claim to provide:

- a fix for every WSL2 problem
- a universal team doctrine
- proof that one tool is always the right answer
- proof that local misconfiguration is absent

`wsl-tunnel.ps1` enters the picture only when all of the following are true:

- the workstation has already been qualified against the studied profile
- a specific `WSL2 -> Windows` dependency path remains uncovered
- an explicit, reversible, developer-operated workaround is acceptable

## Start Here: Qualify The Workstation First

If you are here because `NAT` and `mirrored` each solve only part of your flows,
start with qualification before adopting any workaround.

- [docs/ENTERPRISE-MIXED-MODE-WORKSTATION-DIAGNOSTIC.md](docs/ENTERPRISE-MIXED-MODE-WORKSTATION-DIAGNOSTIC.md) — diagnostic frame for deciding whether your workstation appears to match the studied mixed-mode profile
- [docs/VALIDATION-MATRIX.md](docs/VALIDATION-MATRIX.md) — concrete view of which mechanisms enable which flows
- [docs/README.md](docs/README.md) — documentation index grouped by intent

The repository should be read as a conditional solution with qualification
required, not as a universal tunnel recipe.

## Responses Explored In This Repository

This repository does not assume that one answer fits every workstation.

The response space explored here includes:

- `NAT` as the primary mode when Windows must keep reaching Docker published ports
- `mirrored` when native Windows/WSL2 loopback ergonomics matter more than Docker published-port behavior
- host-network containers for narrow single-container cases
- relay exposure from WSL2 to bridge containers
- SSH reverse tunnels for specific `WSL2 -> Windows` gaps
- proxy handling and `NO_PROXY` strategy for private-IP traffic
- doctrine simplification or component relocation when reducing inter-zone flows is the better answer

These responses are documented so they can be compared, not because they should
all be adopted.

## Targeted Workaround Under Evaluation

One targeted workaround in this repository is `wsl-tunnel.ps1`.

It is relevant only when:

- a specific Windows-hosted dependency still cannot be consumed from WSL2
- native networking mode selection alone does not cover the required flow
- an explicit, reversible, developer-operated workaround is acceptable

`wsl-tunnel.ps1` is therefore a compatible response for a narrow unsupported
path, not the identity of the repository as a whole.

## Quickstart For The Targeted Tunnel Component

If your workstation appears to match the studied profile and you need the
targeted workaround under evaluation:

1. Verify Windows can reach WSL over SSH:

   ```powershell
   ssh wsl-localhost "echo Hello from WSL"
   ```

2. Review the shared service catalog:

   ```powershell
   .\wsl-tunnel.ps1 list
   ```

3. Start a tunnel by service name:

   ```powershell
   .\wsl-tunnel.ps1 up api
   ```

   Or open the interactive selector:

   ```powershell
   .\wsl-tunnel.ps1 up
   ```

4. Inspect active tunnels:

   ```powershell
   .\wsl-tunnel.ps1 status
   .\wsl-tunnel.ps1 status api
   ```

5. Stop a tunnel when you are done:

   ```powershell
   .\wsl-tunnel.ps1 down api
   ```

## What The Targeted Tool Component Does

The tunnel component:

- reads `catalog/tunnels.json`
- validates that the Windows service is actually listening
- starts the matching SSH reverse tunnel
- discovers live tunnels from `ssh` processes
- keeps lightweight runtime markers outside the repo
- gives clear next-step messages for developers

## Repository Layout

- `docs/README.md` — documentation index by intent
- `docs/ENTERPRISE-MIXED-MODE-WORKSTATION-DIAGNOSTIC.md` — qualification frame for mixed-mode enterprise workstations
- `docs/VALIDATION-MATRIX.md` — validated flows, mechanisms, and limits
- `docs/MULTI-WORKSTATION-COMPARISON-KIT.md` — reusable packet for comparing a second workstation with the same grid
- `docs/CONCEPT.md` — explored response space and tradeoffs
- `docs/SETUP.md` — setup for the targeted tunnel component
- `docs/ARCHITECTURE.md` — internal model of the targeted tunnel component
- `docs/TROUBLESHOOTING.md` — recovery for the targeted tunnel component
- `wsl-tunnel.ps1` — guided PowerShell CLI for the targeted SSH reverse-tunnel workflow
- `catalog/tunnels.json` — versioned service catalog

## License

MIT — see [LICENSE](LICENSE)
