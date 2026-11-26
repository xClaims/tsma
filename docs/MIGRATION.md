# Upgrade and deployment replacement

Use this procedure when replacing an existing TSMA deployment or moving TSMA to another approved worker. New installations start at [Getting started](GETTING-STARTED.md); they do not require an earlier installation or another repository.

## 1. Record and protect the current state

Record the deployed commit, Automation account/runbook/runtime, worker registration GUID/group, Arc resource/principal IDs, API application/role IDs, JWT binding, vault static role, AD execution identity, current scope policy and evidence location. Back up protected configuration and retain an approved known-good package outside the live runtime.

The runtime is C:\ProgramData\TSMA. Its src/contracts/RunbookVault.psm1 facade selects the provider; Config/Vault-OperationDirectory.json holds the protected nonsecret mapping. DirectoryGroupMembership.json contains reviewed domain/DC/execution identity, excluded OU GUIDs, protected inventory, password-age limit and review expiry. Do not copy policy/configuration blindly between domains or workers.

## 2. Pause and drain

Disable new write admissions using the [maintenance procedure](OPERATIONS.md), pause applicable starts/schedules under change control and let admitted jobs finish. Reconcile retained account locks and uncertain evidence before proceeding. Local locks on different hosts/runtime paths do not coordinate: never run two mutation consumers of the same execution account merely because both have a local lock.

## 3. Install and validate

For an in-place code update, inspect WhatIf and use Install-WindowsWorker.ps1 -MaintenanceAcknowledged only after drain. The copy is not a hot atomic deployment. Preserve live config/evidence, review schema changes and explicitly control any obsolete files.

For a replacement worker, complete the [installation procedure](INSTALL.md), record its actual Arc principal and deliberately update the exact Entra/OpenBao trust when necessary. A matching machine display name is not proof of the same principal. Preserve/reconcile existing worker registration instead of generating duplicate GUIDs on each retry.

Keep writes disabled while checking protected ACLs, module loading, identity, exact vault permissions, ADWS/LDAPS, exclusions, password freshness and preview. Confirm Application source TSMA and central collection. Publish/review the intended entry point/runtime and verify operator authorization, including optional PIM when enabled.

## 4. Cut over and recover

Under the approved change, enable the selected installation, perform one authorized operation, independently verify its result and repeat to prove idempotency. Retain commit, job IDs/RunIds, evidence and sign-off.

Rollback is a controlled code/configuration/routing change, not an automatic reversal of AD changes. Pause and drain the selected installation before restoring the known-good package. Reconcile actual directory state before retry or removal. Retire unused registrations/trust bindings only after dependency review and successful cutover.
