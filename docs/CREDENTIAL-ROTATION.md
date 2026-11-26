# Automatic credential rotation and admission safeguards

TSMA's default is **24-hour automatic password rotation with a 35-minute admission margin**. OpenBao owns the password and automatic timer. The worker reads credentials and metadata; it cannot request rotation or change the vault role. This is a configurable operational policy, not a compliance guarantee.

| Setting | Default | Meaning |
| --- | --- | --- |
| MaximumPasswordAgeSeconds | 86400 | Must match the OpenBao static role's rotation_period |
| MinimumRemainingLifetimeSeconds | 2100 | Do not admit credential use with 35 minutes or less remaining |

Use matching values in the protected vault mapping and directory-operation policy. The 35-minute margin budgets 30 minutes of expected work plus five minutes of safety. Longer operations require a deliberately increased margin or separate phases. The timer is not extended for running jobs. A crash, worker suspension, manual reset, administrator-triggered rotation or unexpectedly long job can still invalidate credentials. No plugin modification, maximum-age-plus-drain controller or distributed lock is implemented.

## Runtime behavior

1. Validate the mapped username/DN, configured rotation period, clock and last rotation timestamp.
2. Before retrieving a credential, reject admission when the remaining lifetime is at or below the configured margin. Health can be true while AdmissionAllowed is false.
3. Retrieve the current credential immediately before directory work. Check the credential response's timestamp and numeric ttl again; both must exceed the margin. Missing or malformed TTL fails closed.
4. For group-membership operations, enforce the margin on entry and immediately before the single write. Check that vault and operation policies agree. A near-rotation refusal returns DIRECTORY_ROTATION_ADMISSION_DENIED and makes no AD change.
5. Perform the write once, then verify actual direct membership. An uncertain write retains recovery evidence/lock; never automatically replay the mutation with a new password. Follow [recovery](OPERATIONS.md).
6. Dispose Credential.Password in finally. A later independent phase must call Get-RunbookCredential again; the facade does not cache execution passwords. Before that phase writes, recheck scope and actual AD state. Keep the last-rotation metadata associated with that phase's admission; do not attach newly rotated metadata to an older credential.

Refusal is not automatic queuing: Azure Automation records the failed/deferred job. An operator or separately designed scheduler can start a fresh request after successful rotation. Only a request proven to have made no write is eligible for an ordinary retry; uncertain outcomes require reconciliation first.

Example: rotation is due at 08:00 UTC. At 07:20, 40 minutes remain and a normal 30-minute operation may start. At 07:25 or later, new credential admissions are refused. After automatic rotation and verification, fresh work can resume. Do not assume this protects a job that runs longer than its declared budget.

## Migrate an existing four-hour installation

Perform these steps in maintenance; repository changes do not alter live configuration.

1. Record the deployed commit and approved change reference. Pause new Azure starts/schedules, including probes using this account, across every consumer.
2. On the worker, disable directory writes:

~~~powershell
.\deployment\azure\Set-DirectoryWritesEnabled.ps1 -Enabled $false -ChangeReference CHG-ROTATION
~~~

3. Wait for all jobs using the account to finish. Confirm uncertain jobs and retained locks have been reconciled. Disabling writes does not drain jobs automatically or stop credential reads from other runbooks.
4. Preserve protected configuration/evidence backups. Install the reviewed source package with Install-WindowsWorker.ps1 -MaintenanceAcknowledged and republish the updated Add-DirectoryGroupMember entry point. Keep starts paused during copying. See [installation](INSTALL.md).
5. As a separately authorized vault administrator, inspect the current role and update only its rotation interval. Substitute the real mount/role if different:

~~~sh
bao read ldap-operation/static-role/operation-directory
bao write ldap-operation/static-role/operation-directory rotation_period=24h
bao read ldap-operation/static-role/operation-directory
~~~

Do not recreate the role or print static-cred output. Confirm username/DN remain correct and rotation_period is 86400 seconds or its equivalent. The interval is measured from the last successful rotation, not from when this command runs. If the existing timestamp is over 24 hours old, keep consumers paused and have the vault administrator rotate and verify before reopening.

6. In an elevated PowerShell 7 session on the worker, preview and apply matching local settings:

~~~powershell
.\deployment\Set-CredentialRotationPolicy.ps1 -MaximumPasswordAgeSeconds 86400 -MinimumRemainingLifetimeSeconds 2100 -ChangeReference CHG-ROTATION -MaintenanceAcknowledged -WhatIf
.\deployment\Set-CredentialRotationPolicy.ps1 -MaximumPasswordAgeSeconds 86400 -MinimumRemainingLifetimeSeconds 2100 -ChangeReference CHG-ROTATION -MaintenanceAcknowledged
~~~

This requires WritesEnabled=False and trusted runtime ownership/ACLs. It preserves a .previous backup next to each configuration file. It replaces each file atomically, but the two-file update is not a transaction. If interrupted, leave starts paused, inspect both files and backups, then rerun after resolving the cause. Do not reopen with mismatched settings. Keep backups protected and outside source control. The script does not contact OpenBao, change authorization scope, renew scope review or enable writes.

7. From a fresh SYSTEM Hybrid Worker job, run the existing access and authorization probes using the live configuration. Expect credential retrieval and authenticated AD object read to succeed; the authorization probe must still deny rotation and configuration changes. Run a group-membership preview before a controlled mutation. Keep a separately authorized manual rotation test drained.
8. Enable directory writes deliberately, then resume the appropriate starts/schedules:

~~~powershell
.\deployment\azure\Set-DirectoryWritesEnabled.ps1 -Enabled $true -ChangeReference CHG-ROTATION-COMPLETE
~~~

## Monitoring and acceptance

- Observe last_vault_rotation advance across a full 24-hour interval without a manual request. Record before/after UTC timestamps and vault audit evidence; a successful manual rotation does not validate the automatic timer.
- Test fresh, read-only AD authentication after rotation using the existing access probe. Vault retrieval by itself does not prove the password works against AD.
- Alert on overdue rotation, vault/identity failures, lockouts, authentication failures and malformed/mismatched metadata. An AdmissionAllowed=False result within the 35-minute margin is expected; persistent refusal after the expected rotation needs investigation.
- Run authentication probes outside the planned admission blackout; do not disable the margin to make a scheduled probe pass. Publish Get-WindowsCredentialRotationStatus to the Windows Hybrid Worker group and schedule it to monitor metadata even during the blackout. It returns Healthy, AdmissionAllowed, remaining lifetime and last/next rotation UTC without retrieving an AD password. A successful metadata-only run does not prove AD authentication. Monitoring schedules and alerts must be configured by the deployment owner; this package does not create them automatically.
- After host/VM sleep, verify UTC synchronization before restarting work. Never bypass freshness checks to compensate for clock drift.
- Emergency compromise handling may require immediate access revocation/rotation and stopping work. The normal admission margin is not an emergency containment guarantee.

If rollback is necessary, pause and drain again. Restore a matched code/configuration set and deliberately restore the vault role's corresponding interval; do not roll back only one component. Preserve all evidence. Password changes do not reliably terminate existing sessions.

Provider behavior: [OpenBao LDAP secrets](https://openbao.org/docs/secrets/ldap/).
