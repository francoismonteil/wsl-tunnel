# Documentation Index

This documentation is organized by intent so the repository does not read as a
single linear argument toward one tool.

## Recommended Reading Path

Read in this order:

1. decide whether you are in the right repository at all
2. qualify whether your workstation resembles the studied profile
3. compare possible response paths
4. read the tunnel implementation docs only if that path is still relevant

If your workstation does not resemble the studied profile, stop after the
diagnostic section. You should not need the implementation docs to reach that
decision.

## 1. Diagnostic

Use these documents to decide whether a workstation appears to match the mixed
Windows + WSL2 + Docker Engine profile studied in this repository.

- [ENTERPRISE-MIXED-MODE-WORKSTATION-DIAGNOSTIC.md](ENTERPRISE-MIXED-MODE-WORKSTATION-DIAGNOSTIC.md)
- [VALIDATION-MATRIX.md](VALIDATION-MATRIX.md)
- [MULTI-WORKSTATION-COMPARISON-KIT.md](MULTI-WORKSTATION-COMPARISON-KIT.md)

Reader outcome:

- if the profile does not match, stop here
- if the profile seems close, continue to the response docs

## 2. Empirical Validation

Use these documents to review observed workstation behavior and validation
campaigns before drawing broader conclusions.

- [VALIDATION-PLAN.md](VALIDATION-PLAN.md)
- [VALIDATION-REPORT-2026-04-05.md](VALIDATION-REPORT-2026-04-05.md)
- [MIRRORED-MODE-VALIDATION-PLAN.md](MIRRORED-MODE-VALIDATION-PLAN.md)
- [MIRRORED-MODE-VALIDATION-REPORT-2026-04-06.md](MIRRORED-MODE-VALIDATION-REPORT-2026-04-06.md)
- [LOCAL-PRACTICAL-TESTS.md](LOCAL-PRACTICAL-TESTS.md)
- [LOCAL-PRACTICAL-TEST-REPORT.md](LOCAL-PRACTICAL-TEST-REPORT.md)

Reader outcome:

- understand what is actually validated
- avoid stronger prevalence claims without additional workstation comparisons

## 3. Responses Explored

Use these documents to compare possible responses and candidate mechanisms
without assuming that any one of them should apply everywhere.

- [CONCEPT.md](CONCEPT.md)
- [SOLUTION-PLAN.md](SOLUTION-PLAN.md)
- [SOLUTION-PLAN-REPORT-2026-04-05.md](SOLUTION-PLAN-REPORT-2026-04-05.md)
- [CANDIDATE-SOLUTION-VALIDATION-PLAN.md](CANDIDATE-SOLUTION-VALIDATION-PLAN.md)
- [CANDIDATE-SOLUTION-VALIDATION-REPORT-2026-04-06.md](CANDIDATE-SOLUTION-VALIDATION-REPORT-2026-04-06.md)

Reader outcome:

- identify which response is worth exploring
- keep doctrine simplification and component relocation on the table
- treat `wsl-tunnel` as one conditional mechanism among others

## 4. Tool Implementation

Use these documents only if the targeted tunnel component is already relevant to
your qualified workstation and chosen response path.

- [SETUP.md](SETUP.md)
- [ARCHITECTURE.md](ARCHITECTURE.md)
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md)

Reader outcome:

- understand how the tunnel component works
- operate it only as a localized response to a qualified unsupported flow
