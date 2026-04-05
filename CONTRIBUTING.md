# Contributing

Thank you for helping improve WSL Tunnel.

## Reporting Issues

Before opening an issue, gather:

- Windows version
- WSL version from `wsl --version`
- the exact command you ran
- the full error output
- the output of `.\wsl-tunnel.ps1 list` or `status` when relevant

## Pull Requests

1. Fork the repository
2. Create a branch for your change
3. Keep user-facing docs in English
4. Run the validation script locally:

   ```powershell
   pwsh -File tests\test-tunnel.ps1
   ```

5. Open a pull request with a clear summary and reproduction steps when fixing a bug

## Project Conventions

- PowerShell is the primary implementation language
- the service catalog is versioned in `catalog/tunnels.json`
- the CLI should stay explicit and easy for non-experts to use
- changes should preserve clear error messages and reversible actions

## Good Contributions

- improving reliability of tunnel discovery or startup
- clarifying docs and examples
- improving interactive selection UX
- expanding tests without making them brittle
- improving portability while keeping the Windows + WSL focus

## Out of Scope for Small PRs

- unrelated environment management tooling
- repo-wide rewrites that change the core UX without discussion
- enterprise-specific customizations that do not generalize
