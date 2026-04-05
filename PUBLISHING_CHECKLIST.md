# Publishing Checklist

Use this folder as the source for the public repository.

## Content Check

- `README.md` reflects the intended public landing page
- `catalog/tunnels.json` contains only safe example service names and ports
- `docs/` contains no internal organization details
- `docs/VALIDATION-MATRIX.md` reflects the currently observed behavior and does not overstate unverified claims
- `docs/LOCAL-PRACTICAL-TEST-REPORT.md` contains sanitized evidence only, with no raw workstation names, emails, or internal IP addresses
- dated validation reports in `docs/VALIDATION-REPORT-*.md` are sanitized and use placeholders for internal addresses and proxy hosts
- dated solution reports in `docs/SOLUTION-PLAN-REPORT-*.md` are sanitized and use placeholders for internal addresses, proxy hosts, and local paths
- `examples/` use generic endpoints and payloads
- `local-only-*.patch` artifacts are ignored and not staged
- `tests/` pass from inside this folder

## Validation

Run:

```powershell
pwsh -File tests\test-tunnel.ps1
```

Optional smoke checks:

```powershell
pwsh -File .\wsl-tunnel.ps1 list
pwsh -File .\wsl-tunnel.ps1 status
```

## GitHub Preparation

From inside `public/`:

```powershell
git init
git add .
git commit -m "feat: initial public release"
```

Then create the remote repository and push:

```powershell
git remote add origin https://<git-host>/<owner>/<repo>.git
git branch -M main
git push -u origin main
```

## Nice-to-Have Before Release

- add repository topics
- add a short project description
- add an initial release tag
- review issue templates or discussion settings if you want community feedback
