# Package validation and deployment acceptance

## Recorded offline validation

Package validation was performed on 2026-11-26:

- All 18 offline test scripts passed in PowerShell 7.4.22.
- Ownership regression coverage rejects unsafe pre-existing runtime owners, ACLs and links before installation writes.
- Rotation coverage checks the 24-hour interval, admission blackout, response TTL, fresh phase retrieval and maintenance preflight/WhatIf. Live vault rotation and protected atomic file replacement still require deployment acceptance.
- PSScriptAnalyzer 1.25.0 reported zero findings.
- PowerShell source/JSON parsing, relative Markdown links and fenced PowerShell examples passed.
- Actual credential-facade/provider loading and dispatch were exercised with mocked provider transport.
- The documentation suite checks the standalone installation resources as well as their links and PowerShell examples.

The fixtures do not contact Azure, AD, Arc token services or OpenBao. The evidence-write failure warning is intentional recovery coverage. Test scripts run in separate processes to prevent mock-command leakage. The Windows PowerShell 5.1 isolated subset does not establish support for production modules on 5.1.

## Deployment acceptance

For each environment, complete the [validation procedure](VALIDATION.md): supported worker runtime/extension, actual Arc token issuance, vault JWT boundaries/policy, TLS/LDAPS, AD delegation, independent rotation, published-runbook behavior, audit collection and controlled mutation/recovery checks.

When enabling [optional PIM](advanced/ENTRA-PIM.md), include the documented inactive/active/expired-access tests, approval and emergency recovery checks. Record your actual environment's results and accountable sign-off; offline fixtures are not a substitute.

Run tests/Invoke-TSMAChecks.ps1 after source changes. CI is defined in .github/workflows/validate.yml. Retain deployed commit and validation evidence through the service lifecycle.
