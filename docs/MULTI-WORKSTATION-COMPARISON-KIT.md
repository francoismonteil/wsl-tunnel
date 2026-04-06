# Multi-Workstation Comparison Kit

This document turns the repository's diagnostic grid into a reusable
multi-workstation comparison packet.

Its purpose is not to prove that every enterprise workstation behaves the same.
Its purpose is to make the next comparison executable, bounded, and comparable
to the reference workstation already documented in this repository.

## When To Use This Kit

Use this kit only if:

- a second workstation needs to be compared against the profile studied here
- the team wants to know whether the same constraint pattern appears elsewhere
- you want stronger empirical grounding than wording changes alone can provide

Do not use this kit as a generic WSL2 troubleshooting script for unrelated
environments.

## What This Kit Produces

A completed comparison should produce:

- a workstation inventory
- proxy observations from inside containers
- results for tests `T1` through `T6`
- a short divergence list versus the reference workstation
- one bounded conclusion:
  - `profile close`
  - `profile partial`
  - `not comparable`

## Comparison Rules

- Use the same fixture ports unless a local conflict makes that impossible.
- Record exact commands when you must deviate.
- Keep `OK`, `KO`, `Partial`, `Conditional`, and `NR` semantics aligned with the
  repository's validation matrix.
- Do not add stronger prevalence claims from one additional workstation alone.
- If a result is ambiguous, mark it `NR` or explain the ambiguity explicitly.

## Acceptance Logic

Use these interpretation rules before writing any conclusion:

| Situation | Interpretation |
|---|---|
| A required fixture never existed on the workstation | `NR`, not `KO` |
| Transport works but the app rejects hostname or TLS assumptions | `Partial` |
| Success requires explicit proxy bypass or relay policy | `Conditional` |
| Results differ because the workstation uses Docker Desktop instead of Linux Docker Engine in WSL2 | `not comparable` unless the comparison is intentionally widened |

## Workstation Inventory Template

Fill this section first.

```md
# Workstation Comparison - <machine-or-anonymized-label>

Date:
Operator:
Reference compared against:

## Environment

- Windows edition / build:
- Managed enterprise workstation: yes / no / unknown
- WSL distribution:
- WSL version:
- WSL networking mode: NAT / mirrored / unknown
- `localhostForwarding=true`: yes / no / unknown
- Docker model: Linux Docker Engine in WSL2 / Docker Desktop / other
- VPN or security tooling relevant to routing:
- Windows-hosted dependency used for tests:

## Proxy Snapshot

- Proxy variables present in bridge containers: yes / no
- `HTTP_PROXY`:
- `HTTPS_PROXY`:
- `NO_PROXY`:
- Private RFC1918 ranges covered in `NO_PROXY`: yes / no / partial
```

## Test Matrix Template

Use the commands from
[ENTERPRISE-MIXED-MODE-WORKSTATION-DIAGNOSTIC.md](ENTERPRISE-MIXED-MODE-WORKSTATION-DIAGNOSTIC.md)
so the results stay comparable.

```md
## Results

| Test | Flow | Result | Notes |
|---|---|---|---|
| T1 | Windows -> native WSL2 service |  |  |
| T2 | Windows -> Docker published port |  |  |
| T3 | WSL2 -> Docker published port |  |  |
| T4 | WSL2 -> Windows service via localhost |  |  |
| T5 | Container -> native WSL2 service |  |  |
| T6a | Container -> Windows/private IP with proxy bypass |  |  |
| T6b | Container -> Windows/private IP with default proxy behavior |  |  |
```

## Divergence Template

Summarize only the meaningful differences from the reference workstation.

```md
## Divergences vs Reference

- Same as reference:
- Different from reference:
- Ambiguous or not recorded:
```

## Conclusion Template

Choose exactly one conclusion and justify it briefly.

```md
## Qualification Conclusion

- Conclusion: profile close / profile partial / not comparable
- Why:
- Remaining ambiguity:
- Is stronger prevalence language justified from this result alone? no
```

## Minimum Decision Criteria

Use these criteria when selecting the bounded conclusion.

| Conclusion | Minimum interpretation |
|---|---|
| `profile close` | Most signature tests match the reference profile, including the `NAT` / `mirrored` tradeoff and at least one container or proxy signature |
| `profile partial` | Some key signatures match, but one or more core dimensions differ or remain ambiguous |
| `not comparable` | The workstation shape, Docker model, or available fixtures differ enough that comparison would mislead |

## Repository Position

This kit improves empirical quality, but it does not change the repository's
core claims by itself.

Until at least one additional workstation is compared with this same packet, the
repository should avoid stronger wording about prevalence, typicality, or team
standardization.
