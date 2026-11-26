# Architecture and trust boundaries

## Execution flow

Operator -> Azure RBAC -> published runbook -> Windows Hybrid Worker (SYSTEM) -> Arc managed identity -> dedicated Entra API audience -> OpenBao JWT login -> scoped vault token -> mapped AD execution credential -> validated AD operation.

The operator's Azure identity authorizes starting a runbook. The worker identity authorizes credential retrieval. The AD execution account authorizes the actual directory change. These are distinct identities. A ticket number supplies audit context; TSMA does not verify a CAB approval or ticket system.

## Code boundaries

- Operations enforce eligibility, exclusions, intent evidence, mutation and postcheck. They receive a PSCredential and protected scope policy, not an OpenBao token.
- The public RunbookVault facade selects a code-owned provider. Configuration cannot nominate arbitrary executable files.
- The OpenBao provider owns HTTPS requests, scoped JWT login, token caching and credential metadata validation.
- The Azure adapter obtains a token only from Arc's fixed local endpoint and validates the challenge-file location. SYSTEM is required by the current adapter.
- Runbooks compose these components. Vendor-specific diagnostic probes intentionally call the provider's internals and are not portable business operations.

See [credential contract](CONTRACTS.md). Operation evidence includes Azure job-ID fields for platform correlation. The current implementation does not yet define a general cross-cloud job submission interface.

## Tier boundaries

Ordinary operations exclude the configured Tier 0 subtree and the domain's Domain Controllers OU, pinned by GUID. Privileged SIDs, adminCount, critical-system flags, reviewed protected GUIDs, and transitive group parents provide additional checks. The current operation accepts an enabled user with the supported Domain Users primary group and an existing security group. It does not create users, manage privileged groups, or move objects.

Do not infer a simple permission hierarchy from Schema Admins, Enterprise Admins and Domain Admins. They represent different authority. Higher-privilege automation requires independently reviewed operations and execution credentials; TSMA does not activate those groups.

Anyone able to publish arbitrary code to the privileged worker, change its protected configuration, administer its OS, or change the vault policy can affect the execution boundary. Separate operators from publishers, worker administrators, vault administrators and access administrators. Azure Owners and equivalent control-plane administrators are privileged actors.

## Limitations

- One local account lock serializes this operation on one worker. It is not a distributed lease, checkout, rotation drain or global concurrency control.
- A five-minute admission margin reduces rotation overlap; a bounded operation may still encounter an independently scheduled rotation. Do not treat this as maximum-age-plus-drain implementation.
- AD classification/read/write steps are not an atomic forest transaction. OU moves, ACL changes, nesting changes and replication create races.
- Group ancestry and SID checks cannot discover every delegated privilege or application entitlement. Maintain the protected inventory and constrain the AD execution account's actual permissions.
- Azure job metadata may be unavailable or malformed on a worker. TSMA records its own RunId and never guesses a job ID. Correlate using the job's output when necessary.
- Local evidence and Application events are not tamper-proof against SYSTEM or administrators. Configure central collection, retention and access separately.
- Stop/kill is not an automatic rollback. Uncertain mutations require reconciliation before retry.
- PIM expiration blocks future authorized requests after propagation; it does not cancel an already running job or revoke its established AD sessions.

## Deployment safety

The runtime root is C:\ProgramData\TSMA. Install reviewed source and protected configuration using the standalone [community procedure](GETTING-STARTED.md). Writes start disabled. When replacing an existing installation, use the separate [upgrade procedure](MIGRATION.md) and never admit concurrent mutation consumers using the same account.
