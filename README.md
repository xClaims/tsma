# TSMA — Tiered Systems Management Automation

Secure systems automation with tiered execution boundaries and interchangeable platform and credential providers.

**Official upstream:** https://github.com/xClaims/tsma

TSMA is maintained by xClaims. Contributions are welcome through issues and pull requests. Independent forks are permitted under Apache License 2.0; only releases published by this repository are official TSMA releases.

## Current implementation

- Azure Automation on-demand and scheduled runbooks, with an Azure Arc-connected Windows Hybrid Runbook Worker.
- Worker authentication to OpenBao using Arc managed identity and a dedicated-audience Entra JWT; no stored worker password or SecretID.
- OpenBao LDAP static-account credential retrieval and rotation metadata checks.
- Add an enabled ordinary AD user to an existing security group, with preview, protected-target exclusions, verification, local account serialization, and audit evidence.
- Read-only identity, health, AD access, LDAPS, and vault authorization diagnostics.

TSMA can be installed into your own environment using the standalone community guides below. Validate the package on your worker before operational use. It is not a production certification. Linux health/identity scripts are reference examples only; Linux credential retrieval and worker deployment have not been validated here.

See [approval and execution diagrams](docs/WORKFLOWS.md) for the human access, identity, operation and schedule flows.

## Start here

1. Begin with [Getting started from scratch](docs/GETTING-STARTED.md).
2. Complete [prerequisites and planning](docs/PREREQUISITES.md), using the [deployment worksheet](examples/DeploymentWorksheet.example.json).
3. Follow the ordered AD, certificates, OpenBao, Azure/Arc and Entra trust procedures linked in that guide.
4. Install the [protected worker runtime](docs/INSTALL.md) and [operator access](docs/setup/OPERATOR-ACCESS.md).
5. Complete [acceptance](docs/VALIDATION.md), the [first operation](docs/ADD-DIRECTORY-GROUP-MEMBER.md), and [maintenance/recovery](docs/OPERATIONS.md).

See the [community resource index](docs/RESOURCES.md) for supporting vendor documentation and the [upgrade procedure](docs/MIGRATION.md) when replacing an installed deployment.

[Entra PIM](docs/advanced/ENTRA-PIM.md) provides an optional production deployment procedure for time-limited operator access. The baseline works without PIM. AWS, GCP, CyberArk, and HashiCorp Vault adapters are future work, not implemented integrations.

## Repository structure

| Path | Responsibility |
| --- | --- |
| src/operations/ | AD business operations, safeguards, verification and evidence |
| src/contracts/ | Stable credential-provider facade |
| src/platforms/azure/ | Arc identity-token acquisition |
| src/vaults/openbao/ | OpenBao REST provider and vendor authorization diagnostics |
| runbooks/windows/ | Windows entry points and diagnostic probes |
| runbooks/linux/ | Reference health/identity entry points only |
| deployment/ | Protected Windows installation and explicit cloud/vault provisioning |
| examples/ | Sanitized nonsecret configuration templates |
| tests/ | Offline behavioral tests and source checks |
| docs/ | Architecture, procedures, security design and roadmap |

## Security and scope

Tier 0 and domain-controller assets are excluded from the ordinary directory operation. Separate execution accounts, vault policies, code-publishing permissions, and worker boundaries are required for other privilege classes; a folder name alone is not enforcement. Ordinary AD scope remains exclusion-based and requires an accountable scope review and protected-object inventory.

The current lock is local to one worker. It does not coordinate other workers or OpenBao's scheduled rotation. Do not share the execution account across workers or independent consumers without an additional coordinator. Password rotation does not invalidate every established session. See [Tier 0 administration boundaries](docs/TIER0-PRIVILEGED-ADMINISTRATION.md) and [known limitations](docs/ARCHITECTURE.md#limitations).

## Validation

Run source and offline checks from the repository root:

~~~powershell
.\tests\Invoke-TSMAChecks.ps1
~~~

The full suite requires PowerShell 7.4 or later. The offline logic subset can run in Windows PowerShell 5.1; it does not validate the production runtime or contact Azure, AD, or OpenBao. See [validation](docs/VALIDATION.md).

## Contributing, security and license

See [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md). Licensed under [Apache License 2.0](LICENSE). Third-party material retains its applicable license and notices.
