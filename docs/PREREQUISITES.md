# Prerequisites and deployment worksheet

This page defines the infrastructure you supply. TSMA is an automation package; it does not install Windows/Ubuntu, create a forest, build a CA, obtain an Azure subscription, or grant administrative authority for you.

## Machines and services

| Component | Requirement | Where to begin if missing |
| --- | --- | --- |
| AD DS/DNS | A healthy domain with a reachable DC and a reviewed Tier 0 OU | Install supported Windows Server and promote a DC using Microsoft's [AD DS deployment guide](https://learn.microsoft.com/en-us/windows-server/identity/ad-ds/deploy/install-active-directory-domain-services--level-100-) |
| Windows worker | A supported domain-joined member server, not a DC, with administrative installation access | Provision a supported Windows Server VM/host; join it to your domain and patch it |
| Management workstation | Git, PowerShell 7, compatible Az/Graph modules, browser, and authorized named administrator accounts | Follow [tool and cloud setup](setup/AZURE-WORKER.md) |
| Vault host | A patched Linux host supported by Docker Engine, persistent disk and trusted DNS | Follow [vault server setup](setup/OPENBAO-SERVER.md) |
| PKI | A CA capable of issuing trusted DC and vault TLS certificates | Follow [certificates](setup/CERTIFICATES-LDAPS.md); an existing enterprise or suitable third-party CA can be used |
| Azure/Entra | Subscription, tenant, ability to create/read the selected resources and application trust | Record tenant/subscription IDs in your worksheet; baseline does not require PIM |

Production should use dedicated privileged execution infrastructure and an appropriate available vault architecture. A single vault node is a functional starting point with an availability limitation. Co-locating unrelated attack/testing services with the vault or hosting a CA on the automation worker is not the reference community deployment.

Check the current [Hybrid Worker support matrix](https://learn.microsoft.com/en-us/azure/automation/extension-based-hybrid-runbook-worker-install) before selecting the worker OS, runtime and extension. TSMA source requires PowerShell 7.4 or later; Azure must separately support the chosen runtime. Windows PowerShell 5.1 is used only for specified administrative tools or the isolated test subset.

## Administrative authority

Use separately accountable roles where feasible:

- AD administrator: create OUs/accounts/groups, delegate exact member-write/reset rights and configure DC certificates.
- Azure deployment administrator: register providers, create Automation resources, onboard Arc and install worker extensions.
- Azure access administrator: assign reviewed RBAC at the intended scope. Resource creation authority does not automatically authorize role assignment.
- Entra application administrator with required consent: create the API application/service principal and assign its application role to the Arc identity.
- Vault administrator: initialize/configure OpenBao, LDAP/JWT mounts and policies; safeguard unseal/root recovery material.
- Operator: run approved runbooks; no Azure Contributor, publisher, worker local-administrator, direct vault-admin or AD privileged-account access is required.

One person may perform several setup roles in an isolated personal environment. That does not create production separation of duties. When selecting optional PIM, assess its licensing for benefiting users, approvers and reviewers before deployment.

## Network and time

| Source | Destination | Purpose |
| --- | --- | --- |
| Worker | AD DNS/domain services | Domain membership, Kerberos and ordinary AD prerequisites |
| Worker | Configured DC TCP 9389 | Explicit-credential ADWS reads |
| Worker and vault | Configured DC TCP 636 | Certificate-validated LDAP operations/password reset |
| Worker | Vault TCP 8200 HTTPS | JWT login, scoped metadata/credential reads |
| Worker | Required Azure/Arc endpoints over HTTPS | Registration, extension and job communication |
| Vault | Entra discovery/signing-key endpoints over HTTPS | JWT issuer/signature validation |
| Vault host | Approved OCI registries over HTTPS | Server/plugin acquisition and updates |
| Clients | DNS and approved time sources | Name resolution and consistent UTC |

AD membership needs more than the listed ADWS/LDAPS ports; use Microsoft's domain-service firewall guidance. Arc outbound endpoints vary by cloud/region; use the official requirements rather than opening unrestricted inbound access. Docker localhost is not the worker's localhost. Do not expose the Arc token endpoint remotely.

Check UTC and time-source health on DCs, worker, vault host and hypervisor after suspend/resume. A correct time-zone display alone does not prove synchronized clocks. Incorrect clocks can break Kerberos, JWT expiry, TLS and password-age admission.

## Naming and scope

Choose and record: domain DNS/NetBIOS names, DC FQDN, Tier 0 DN, worker FQDN/Arc name, vault FQDN/IP, Azure region, subscription/tenant IDs, Automation account/group IDs, saved worker registration GUID, execution/reconciliation account DNs, app IDs and JWT bindings. Keep role names used by code-owned probes consistent with the supplied templates.

The initial operation excludes the configured Tier 0 subtree and Domain Controllers OU; it also needs an inventory of powerful objects outside them. Do not move production assets merely to fit an example. GPO Block Inheritance is distinct from AD object ACL inheritance.

## Costs, backup and exit checks

Review Azure Automation execution, optional monitoring/log ingestion, optional Arc-enabled paid services, compute and storage costs. Set a subscription budget/alerts before enabling schedules; a budget alert is not a hard spending cap. Do not enable unrelated Defender/Update Manager services just to onboard a worker. See [Automation pricing](https://azure.microsoft.com/en-us/pricing/details/automation/) and [Azure budgets](https://learn.microsoft.com/en-us/azure/cost-management-billing/costs/tutorial-acm-create-budgets).

Assign backup/restore owners for AD, CA, vault Raft data/unseal material, protected configuration and audit evidence. Read the [security policy](../SECURITY.md) before sharing logs. Continue only when host identities, permissions, DNS, clock health, certificates, persistent storage and an authorized test user/group are available.
