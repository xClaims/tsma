# Contributing to TSMA

TSMA welcomes contributions through issues and pull requests in the official repository. Run tests/Invoke-TSMAChecks.ps1 in PowerShell 7.4 or later before proposing a change. Record live worker validation separately from offline fixture results.

Before making a substantial change, agree on its scope with the maintainers.

## Change guidelines

- Keep runbook entry points thin and business logic in `src/operations/`.
- Define common behavior in `src/contracts/` and keep vendor-specific behavior in adapters.
- Include appropriate validation, verification, audit evidence, and recovery behavior for administrative changes.
- Add meaningful tests for security boundaries and failure handling.
- Update relevant documentation and sanitized examples.
- Never commit credentials, tokens, private keys, production evidence, or environment-specific configuration.
- Describe what changed, how it was validated, and any remaining limitations in the pull request.

## Official upstream and contribution terms

Submit proposed improvements through issues and pull requests at https://github.com/xClaims/tsma. Maintainers review contributions and decide what enters the official project. Independent forks and development remain permitted under the license.

Unless explicitly stated otherwise, contributions intentionally submitted for inclusion in TSMA are submitted under Apache License 2.0, as described in Section 5 of the license. Contributors retain ownership of their contributions; submission does not assign copyright to xClaims.

Only submit material you have the right to contribute, and preserve applicable third-party license and attribution notices. Do not copy code from another project without checking its license compatibility and obligations.
