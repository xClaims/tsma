# Maintenance, rotation and recovery

## Pause and resume writes

On the worker, run the repository deployment script elevated:

~~~powershell
.\deployment\azure\Set-DirectoryWritesEnabled.ps1 -Enabled $false -ChangeReference CHG-MAINTENANCE
~~~

This blocks new write admissions through the local policy. Already admitted jobs may finish. Wait for active jobs to finish and reconcile locks before changing code, configuration or credentials. Coordinate Azure starts/schedules and all other account consumers separately. Preview remains available while policy/scope review is valid.

After maintenance and read-only validation:

~~~powershell
.\deployment\azure\Set-DirectoryWritesEnabled.ps1 -Enabled $true -ChangeReference CHG-RESTORE
~~~

Enabling requires a current scope review. There is no short write window to renew; writable state persists until disabled. Do not extend ReviewExpiresUtc without reviewing scope, excluded roots and protected inventory.

## Upgrade code

Record the current commit, protected configuration and job/evidence state. Disable admissions, drain jobs and preserve the previous package outside the runtime. Run Install-WindowsWorker.ps1 -MaintenanceAcknowledged after previewing WhatIf. This is a file-copy deployment, not an atomic hot upgrade. Do not run jobs during copying. Live configuration/evidence are preserved; superseded files are not automatically deleted. Validate from a fresh worker job before enabling writes.

## Unsafe existing runtime ownership

If installation reports TSMA_RUNTIME_OWNER_UNTRUSTED, TSMA_RUNTIME_ACL_UNTRUSTED or TSMA_RUNTIME_ACL_UNPROTECTED, stop and keep jobs paused. Do not bypass the checks or automatically take ownership of an unreviewed directory. A previously user-owned path may contain modified code or configuration even after permissions are tightened.

An authorized worker administrator must inspect owners, explicit/inherited permissions, links, code/configuration integrity and the creating account. Preserve evidence and protected backups. Restore a trusted baseline under change control, or prepare a clean installation from reviewed source and re-create reviewed configuration. Recovery must account for existing evidence and uncertain jobs. Rerun WhatIf/preflight and fresh read-only checks before resuming writes. SYSTEM and local Administrators are the accepted runtime owners; individual user ownership is deliberately not accepted merely because that user is currently an administrator.

## Credential rotation

OpenBao owns the AD password. TSMA retrieves a fresh credential for each job and verifies identity/age metadata. The worker policy cannot rotate the account or change the LDAP engine. Administrative reconciliation access is separate from worker access.

Confirm independent scheduled rotation by recording last_vault_rotation before and after the configured period while no manual rotation is requested. Verify fresh read-only AD authentication after rotation. Do not disable freshness checks to work around drift or a sealed vault. Check UTC on the Hyper-V host, worker, DC and vault host after suspension/resume.

The current implementation does not implement coordinated maximum-age-plus-drain. For a controlled manual rotation, pause and drain every consumer first; use a separately authorized vault administrator. Avoid long-running jobs sharing a rotating password. Password changes do not terminate existing authenticated sessions reliably.

## RecoveryRequired or retained lock

1. Pause new admissions and preserve job output, RunId, JSON evidence, Application events and vault audit correlation.
2. Establish whether the original job/process is still active. Do not delete a live lock.
3. Read actual direct membership on the recorded DC and compare the intended user/group GUIDs with evidence.
4. If membership is present, record that fact; do not blindly repeat or automatically remove it. If absent, determine whether the original write can still complete before considering a retry.
5. Resolve the underlying fault and have an accountable administrator record the reconciliation decision. Remove a stale lock only after the owning run is confirmed inactive and uncertain state is resolved.
6. Validate read-only behavior, then reopen admissions under an approved reference.

## Rollback to the earlier installation

Pause TSMA writes and drain/reconcile its jobs. Restore the prior published entry point and its own known-good configuration. Never allow both runtimes to use the same execution account concurrently: their local locks live in different paths. A code rollback is not an AD membership rollback.
