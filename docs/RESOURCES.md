# Community resource index

The primary TSMA installation path is [Getting started](GETTING-STARTED.md). The upstream documents below cover infrastructure and vendor features TSMA builds upon. Check current support matrices, releases, permissions, pricing and licensing at deployment time; source minimum-version declarations are not service support guarantees.

The [workflow diagrams](WORKFLOWS.md) summarize approval, identity, operation and schedule behavior.

## TSMA procedures

| Task | Guide |
| --- | --- |
| Plan the installation and prerequisites | [Prerequisites](PREREQUISITES.md) |
| Prepare accounts and scoped AD permissions | [AD directory setup](setup/AD-DIRECTORY.md) |
| Issue/trust TLS certificates and test LDAPS | [Certificates/LDAPS](setup/CERTIFICATES-LDAPS.md) |
| Bootstrap the vault and persistent storage | [OpenBao server](setup/OPENBAO-SERVER.md) |
| Configure reset/reconciliation and rotation | [OpenBao LDAP](setup/OPENBAO-LDAP.md) |
| Deploy Azure resources and Windows worker | [Azure/Arc](setup/AZURE-WORKER.md) |
| Create dedicated audience and JWT bindings | [Entra/OpenBao](setup/ENTRA-OPENBAO.md) |
| Protect/install code, mapping and policy | [Worker runtime](INSTALL.md) |
| Grant named operator invocation access | [Operator access](setup/OPERATOR-ACCESS.md) |
| Prove first safe membership operation | [Group membership](ADD-DIRECTORY-GROUP-MEMBER.md) |
| Test positive/denied/recovery behavior | [Validation](VALIDATION.md) |
| Maintain and recover the service | [Operations](OPERATIONS.md) |
| Add optional human just-in-time access | [Entra PIM](advanced/ENTRA-PIM.md) |

## Microsoft infrastructure and tools

- [Install Git](https://git-scm.com/downloads) and [PowerShell on Windows](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-windows).
- [Install Azure PowerShell](https://learn.microsoft.com/en-us/powershell/azure/install-azure-powershell) and [Microsoft Graph PowerShell](https://learn.microsoft.com/en-us/powershell/microsoftgraph/installation).
- [AD DS deployment](https://learn.microsoft.com/en-us/windows-server/identity/ad-ds/deploy/install-active-directory-domain-services--level-100-), [CA installation](https://learn.microsoft.com/en-us/windows-server/networking/core-network-guide/cncg/server-certs/install-the-certification-authority), and [LDAPS certificates](https://learn.microsoft.com/en-us/windows-server/identity/ad-ds/configure-ldap-signing-certificates).
- [Arc onboarding](https://learn.microsoft.com/en-us/azure/azure-arc/servers/onboard-portal), [Arc network requirements](https://learn.microsoft.com/en-us/azure/azure-arc/servers/network-requirements), and [Arc identity](https://learn.microsoft.com/en-us/azure/azure-arc/servers/managed-identity-authentication).
- [Hybrid Worker deployment/support](https://learn.microsoft.com/en-us/azure/automation/extension-based-hybrid-runbook-worker-install), [Hybrid runbook runtimes](https://learn.microsoft.com/en-us/azure/automation/automation-hrw-run-runbooks), and [Automation RBAC](https://learn.microsoft.com/en-us/azure/automation/automation-role-based-access-control).
- [Azure Automation pricing](https://azure.microsoft.com/en-us/pricing/details/automation/) and [cost budgets](https://learn.microsoft.com/en-us/azure/cost-management-billing/costs/tutorial-acm-create-budgets).
- [PIM for Groups](https://learn.microsoft.com/en-us/entra/id-governance/privileged-identity-management/concept-pim-for-groups) and [Governance licensing](https://learn.microsoft.com/en-us/entra/id-governance/licensing-fundamentals).

## OpenBao, Docker and TLS

- [OpenBao release metadata](https://github.com/openbao/openbao/releases) and [installation](https://openbao.org/docs/install/).
- [Server configuration](https://openbao.org/docs/configuration/), [OCI plugins](https://openbao.org/docs/configuration/plugins/), [audit](https://openbao.org/docs/configuration/audit/), and [seal/unseal](https://openbao.org/docs/concepts/seal/).
- [LDAP secrets engine](https://openbao.org/docs/secrets/ldap/) and [LDAP API](https://openbao.org/api-docs/secret/ldap/).
- [JWT authentication](https://openbao.org/docs/auth/jwt/) and [JWT API](https://openbao.org/docs/api/auth/jwt/).
- [Docker Engine installation](https://docs.docker.com/engine/install/) and [Compose plugin](https://docs.docker.com/compose/install/linux/).

## Asking for help

Provide the TSMA commit, OS/runtime/extension versions, sanitized stage/command, safe reason/status code and relevant nonsecret expected/observed behavior. Do not attach tokens, passwords, private keys, unseal shares, raw credential responses or unreviewed transcripts. An issue should identify which stage's exit condition failed; this is more useful than continuing later stages after an error. Follow [SECURITY.md](../SECURITY.md) for sensitive reports.
