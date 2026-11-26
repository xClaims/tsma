# Security policy

## Reporting a vulnerability

Report vulnerabilities privately through [GitHub private vulnerability reporting](https://github.com/xClaims/tsma/security/advisories/new), or open this repository's Security -> Advisories page and select Report a vulnerability.

Do not put exploit details, credentials, passwords, tokens, private keys, unseal material, production evidence or sensitive environment information in a public issue or pull request. If the private reporting button is unavailable, open a public issue titled "Private security reporting unavailable" with no vulnerability details and ask maintainers to enable the reporting channel. Wait for a private channel before sending sensitive material.

A useful private report identifies the affected commit/version, component, prerequisites, impact, and minimal sanitized reproduction. Include mitigation suggestions when available. You do not need to send real credentials or customer data to demonstrate a report.

## Maintainer publication step

GitHub private vulnerability reporting is a repository setting available for public repositories. When publishing TSMA, enable it under Settings -> Advanced Security -> Private vulnerability reporting, verify that the Report a vulnerability button is available, and configure maintainer notifications. Merely adding SECURITY.md does not enable this feature.

See [GitHub's enablement instructions](https://docs.github.com/en/code-security/how-tos/report-and-fix-vulnerabilities/configure-vulnerability-reporting/configure-for-a-repository). Repository visibility is managed separately; no installation script changes it.

## Supported versions and fixes

Until versioned releases are published, security fixes target the latest main branch. Report suspected issues on any revision and provide the exact commit ID; maintainers may ask you to validate against the current branch. Older snapshots have no independent maintenance commitment unless explicitly documented in a release policy.

A published release or passing offline test suite is not an independent security certification. Validate installation permissions, identity bindings, target scope, and recovery behavior for the actual deployment.

## Handling an exposed secret

Revoke or rotate the credential promptly, investigate its use, and coordinate removal of sensitive history/artifacts. Deleting the current file does not remove earlier commits, forks, downloaded artifacts or logs. Keep private deployment configuration and execution evidence outside version control.
