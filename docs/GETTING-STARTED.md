# Start a new TSMA installation

This guide starts with your own infrastructure and ends with an independently verified directory-group operation.

The first supported path is Azure Automation + an Azure Arc-connected Windows worker + OpenBao + Active Directory Domain Services. Entra PIM is an optional production access-control configuration; validate baseline connectivity before enabling its activation requirements. AWS/GCP and other vault providers are not implemented. Linux hosts can run the vault; the Linux worker examples are not the supported credential-execution path.

## What you will build

A named operator starts a published Azure runbook. SYSTEM on your Windows worker obtains a token from that machine's Arc identity. OpenBao accepts the dedicated Entra JWT and returns only the mapped AD service-account credential. The runbook validates the requested user/group, records intent, adds membership through LDAPS and verifies it on the same DC. The human does not receive the execution password.

## Choose a starting point

| You have | Start with |
| --- | --- |
| No domain, CA, worker or vault | Complete infrastructure prerequisites, then all stages below |
| AD and trusted LDAPS, but no automation/vault | Complete planning, skip only prerequisite tasks you independently verify |
| Existing Arc/vault resources | Inspect and record exact IDs, then follow the relevant stages without recreating resources |
| An installed TSMA deployment to upgrade/replace | Use [upgrade and deployment replacement](MIGRATION.md) |

## Deployment order

| Stage | Procedure | Required exit evidence |
| --- | --- | --- |
| 0 | [Prerequisites and planning](PREREQUISITES.md) | Hosts, identities, naming, costs, permissions and network paths recorded |
| 1 | [AD accounts and delegation](setup/AD-DIRECTORY.md) | Execution account, reconciliation account and narrowly delegated rights |
| 2 | [Certificates and LDAPS](setup/CERTIFICATES-LDAPS.md) | Trusted DC/vault certificates and successful TLS validation |
| 3 | [OpenBao server](setup/OPENBAO-SERVER.md) | Initialized/unsealed HTTPS vault, declarative audit, registered LDAP/JWT plugins |
| 4 | [OpenBao AD rotation](setup/OPENBAO-LDAP.md) | Correct account role and separately verified password rotation |
| 5 | [Azure account, Arc and worker](setup/AZURE-WORKER.md) | Connected identity, worker heartbeat, successful SYSTEM identity job |
| 6 | [Entra-to-OpenBao trust](setup/ENTRA-OPENBAO.md) | Recorded app/role/identity IDs and exact JWT role/policy |
| 7 | [Install the worker runtime](INSTALL.md) | Protected code, configuration and scope policy; writes disabled |
| 8 | [Operator access](setup/OPERATOR-ACCESS.md) | Named operator can invoke approved jobs, cannot publish or administer the worker |
| 9 | [Acceptance](VALIDATION.md) and [first operation](ADD-DIRECTORY-GROUP-MEMBER.md) | Read-only/denied probes, preview, authorized mutation, idempotency and evidence |
| 10 | [Operations](OPERATIONS.md) | Maintenance, backup, monitoring and recovery ownership |

Each document identifies the machine and administrative context. PowerShell blocks run in a terminal, not PowerShell ISE when SSH/password prompts are involved. A variable created in one session does not exist on another host or in a new process: reload the relevant variables before each block. Stop at errors; do not execute later creation lines after a failed check.

## Get the repository

On the administrative workstation, install Git and a supported PowerShell 7 release, then:

~~~powershell
git clone https://github.com/xClaims/tsma.git C:\Code\tsma
Set-Location C:\Code\tsma
.\tests\Invoke-TSMAChecks.ps1
~~~

While upstream is private, clone access requires repository permission; public users can use these steps after publication or from an authorized fork. Never paste personal access tokens into the clone URL.

## Example values are not your configuration

The guides use ad.example.com, EXAMPLE, dc01.ad.example.com, worker01.ad.example.com, bao.example.com and documentation-only 192.0.2.0/24 addresses. Replace them with values that actually resolve and route in your environment. Do not copy example GUIDs as real tenant, subscription, app, identity or OU IDs.

Use [the deployment worksheet](../examples/DeploymentWorksheet.example.json) as a private record outside the checkout. It is a planning document, not a configuration file consumed by TSMA scripts. The two worker configuration schemas remain separate. Real IDs are generally not passwords but still belong in your deployment record rather than reusable community examples.

## Baseline versus production acceptance

A functional first deployment is not a production certification. Use an authorized isolated environment for the first write. Availability, backup, central logs, publisher governance, privileged hosting, patching, cost ownership and disaster recovery must be addressed before production use. Offline tests do not provision or validate these systems. Read [architecture and limitations](ARCHITECTURE.md) and [resource links](RESOURCES.md).
