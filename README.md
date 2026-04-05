# WSL Tunnel

Guided SSH reverse tunnels for development environments where standard WSL2 networking modes do not cover every required flow.

## Problem Statement

On constrained workstations, there may be no single WSL2 networking mode that makes all local development paths work at the same time.

Based on the validation matrix in this repository:

- NAT can preserve Windows -> Docker published ports
- but NAT may still leave WSL2 and its containers unable to reach Windows-hosted services
- mirrored mode can improve native Windows <-> WSL2 communication
- but mirrored mode can also break Windows -> Docker published ports

That means teams can end up in an uncomfortable middle ground:

- native WSL2 services work
- some container flows work
- but a critical dependency hosted on Windows still remains unreachable from WSL2 or from containers

This project exists as a practical workaround for that gap.

## What This Tool Is

`wsl-tunnel.ps1` is a guided PowerShell CLI that opens explicit SSH reverse tunnels from Windows to WSL2 so a Windows-hosted service can be consumed from WSL2 or from workloads running inside WSL2.

Instead of asking developers to remember raw SSH syntax and port mappings, the tool uses a versioned catalog of named services.

## When This Is Useful

Use this project when:

- WSL2 cannot reliably reach a Windows-hosted dependency
- containers inside WSL2 cannot reliably reach a Windows-hosted dependency
- switching between NAT and mirrored mode only moves the breakage around
- you want a visible, reversible workaround that developers can operate safely

Do not use this as the first answer if your environment already works with native WSL2 networking.

## Evidence First

Before adopting the workaround, validate your workstation behavior with:

- [docs/VALIDATION-PLAN.md](docs/VALIDATION-PLAN.md)
- [docs/SOLUTION-PLAN.md](docs/SOLUTION-PLAN.md)
- [docs/VALIDATION-MATRIX.md](docs/VALIDATION-MATRIX.md)
- [docs/LOCAL-PRACTICAL-TESTS.md](docs/LOCAL-PRACTICAL-TESTS.md)
- [docs/LOCAL-PRACTICAL-TEST-REPORT.md](docs/LOCAL-PRACTICAL-TEST-REPORT.md)
- [docs/VALIDATION-REPORT-2026-04-05.md](docs/VALIDATION-REPORT-2026-04-05.md)

That document captures:

- the broader test campaign
- the current solution search
- tested configurations
- communication paths
- observed limitations
- remaining checks

## Quickstart

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

## Interactive Mode

When you run `.\wsl-tunnel.ps1 up` in a real PowerShell console:

- `Up` / `Down` moves the cursor
- `Space` toggles a checkbox
- `Enter` confirms the current selection
- `Esc` cancels

You can select several services and start them in one pass.

## What the Tool Does

- reads `catalog/tunnels.json`
- validates that the Windows service is actually listening
- starts the matching SSH reverse tunnel
- discovers live tunnels from `ssh` processes
- keeps lightweight runtime markers outside the repo
- gives clear next-step messages for developers

## Repository Layout

- `wsl-tunnel.ps1` — guided CLI entrypoint
- `catalog/tunnels.json` — versioned service catalog
- `docs/` — setup, architecture, concept, troubleshooting, and validation matrix
- `examples/` — usage examples
- `tests/test-tunnel.ps1` — fixture-based validation for the CLI

## Documentation

- [docs/SETUP.md](docs/SETUP.md) — installation and day-1 usage
- [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) — failure diagnosis and recovery
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — runtime model and state discovery
- [docs/CONCEPT.md](docs/CONCEPT.md) — network rationale and tradeoffs
- [docs/VALIDATION-PLAN.md](docs/VALIDATION-PLAN.md) — broader validation campaign for representative workstation testing
- [docs/SOLUTION-PLAN.md](docs/SOLUTION-PLAN.md) — experiment plan for turning the validated limitation into a practical solution
- [docs/VALIDATION-MATRIX.md](docs/VALIDATION-MATRIX.md) — tested configurations, flows, and observed limitations
- [docs/LOCAL-PRACTICAL-TESTS.md](docs/LOCAL-PRACTICAL-TESTS.md) — step-by-step validation protocol for a real workstation
- [docs/LOCAL-PRACTICAL-TEST-REPORT.md](docs/LOCAL-PRACTICAL-TEST-REPORT.md) — sanitized field report from one constrained workstation
- [docs/VALIDATION-REPORT-2026-04-05.md](docs/VALIDATION-REPORT-2026-04-05.md) — detailed sanitized Campaign A report tied to the validation plan

## License

MIT — see [LICENSE](LICENSE)
