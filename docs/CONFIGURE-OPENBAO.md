# Configure OpenBao for a new TSMA installation

No existing vault, API application or previous TSMA experience is assumed. Follow these complete procedures in order:

1. [Certificates and LDAPS](setup/CERTIFICATES-LDAPS.md): supply public CA trust, a working DC LDAPS certificate and the vault TLS key/certificate.
2. [Install OpenBao](setup/OPENBAO-SERVER.md): Docker/Compose, pinned server/plugin artifacts, TLS permissions, persistent volumes, initialization, unseal and declarative audit.
3. [Configure LDAP password management](setup/OPENBAO-LDAP.md): mount the secrets engine, configure the reconciliation account and CA PEM, create the execution-account static role and validate rotation.
4. [Prepare Azure Arc identity](setup/AZURE-WORKER.md): obtain the actual machine identity; this can be prepared independently of vault installation.
5. [Create Entra/OpenBao trust](setup/ENTRA-OPENBAO.md): create or inspect the API application/role, assign the machine identity, install exact JWT bindings and worker read policy.
6. [Install worker configuration](INSTALL.md): deploy nonsecret mapping through the protected Windows runtime, then run read-only/denied probes.

For the whole deployment map, begin at [Getting started](GETTING-STARTED.md).

## Identities that must not be confused

| Identity/object | Purpose |
| --- | --- |
| Human Azure operator | May start approved published jobs according to Azure RBAC |
| Worker SYSTEM process | Hosts the current runbook/Arc authentication adapter |
| Arc machine service principal | Obtains the dedicated-audience Entra JWT |
| Entra API application/client ID | Identifies the API resource/audience; not the worker identity |
| OpenBao JWT role | Binds issuer, audience, tenant, machine oid, app role and token lifetime |
| OpenBao reconciliation/bind account | Authenticates to AD and resets only the intended managed account |
| AD execution account | Performs the directory changes through explicitly delegated AD permissions |

No worker SecretID or app client secret is used. The LDAP reconciliation password still exists and needs an owned lifecycle. Never give workers an initial root token, unseal share, reconciliation password, mount-management policy or unrelated account credential.

## Names and version assumptions

The initial code-owned diagnostics use ldap-operation/operation-directory, jwt-arc and role operation-directory-worker01. Their allowed/denied endpoint tests are not dynamically generated from arbitrary operator input. If you deliberately rename those resources, update and validate the code-owned probes/tests together.

The deployment examples require compatible server/plugin versions. Literal APPROVED_VERSION/VERIFIED_DIGEST values are not usable tags/digests. Select current supported artifacts through official release metadata and record what was installed. A historical exercised plugin artifact is not a security endorsement for all future releases.

## Existing resources

Community users may bring existing infrastructure. In that case, inspect initialized state, mounts, app objects, identities, role assignment and policies before each creation step. Do not reinitialize a vault, overwrite an issuer, recreate an application on duplicate names or change unrelated services to follow an example. Record exact IDs in your private worksheet.

See [operations](OPERATIONS.md) for rotation, maintenance and recovery, and [validation](VALIDATION.md) for acceptance evidence. Vendor-specific setup does not alter the stable credential-provider interface used by business runbooks.
