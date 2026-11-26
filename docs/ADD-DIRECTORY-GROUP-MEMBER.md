# Add a user to an existing directory group

See [the operation decision and recovery diagram](WORKFLOWS.md#3-directory-operation-decisions-and-recovery) for preview, mutation, idempotency and uncertain outcomes.

## Supported operation

Add one enabled ordinary user to one existing AD security group, chosen by sAMAccountName at job submission. This is not an unrestricted PowerShell endpoint. No users/groups are created, removed, moved or enabled. The runbook does not manage privileged groups.

Inputs:

| Parameter | Meaning |
| --- | --- |
| UserName | Existing user sAMAccountName |
| GroupName | Existing security group sAMAccountName |
| ChangeReference | Accountable ticket/change reference; audit context, not ticket approval verification |
| Preview | Boolean, default True; use False only for an authorized write |

## Prerequisites

Complete [installation](INSTALL.md), delegated AD rights, exact vault mapping, trusted LDAPS and scope inventory. Confirm policy ExecutionIdentity equals the mapped credential identity and MaximumPasswordAgeSeconds matches the vault configuration/role and MinimumRemainingLifetimeSeconds matches the vault mapping (default 2100). See [rotation safeguards](CREDENTIAL-ROTATION.md). Do not give the execution account rights to protected objects merely because code also checks exclusions.

The protected policy at C:\ProgramData\TSMA\Config\DirectoryGroupMembership.json includes DomainController, DomainSid, DomainDistinguishedName, Tier0DistinguishedName, ExcludedOuGuids, ProtectedObjectGuids, ExecutionIdentity, MaximumPasswordAgeSeconds, MinimumRemainingLifetimeSeconds, ScopeReviewReference, ReviewExpiresUtc, WritesEnabled and EvidenceDirectory. Examples contain placeholders, not an operational policy.

## Procedure

1. Pick an eligible user and group. Record current direct membership on the configured DC using a separately authorized read identity.
2. Start the published Add-DirectoryGroupMember runbook on the approved Windows Hybrid Worker with Preview=True.
3. Confirm Preview and MutationAttempted=False, or AlreadyMember if already directly present. Retain RunId, job output and evidence path.
4. Complete [negative tests](VALIDATION.md) before opening writes.
5. Enable persistent writes on the worker after review:

~~~powershell
.\deployment\azure\Set-DirectoryWritesEnabled.ps1 -Enabled $true -ChangeReference CHG-REPLACE -WhatIf
~~~

Review and run without WhatIf. This does not make Preview default False.

6. Start a fresh approved job with the same names and Preview=False. Expect VerifiedSuccess and MutationAttempted=True when the link was absent.
7. Independently read direct membership on the same DC. Retain local evidence and Application Log events.
8. Repeat the same request. Expect AlreadyMember and MutationAttempted=False.

There is no automatic removal/rollback runbook. Removal is a separate authorized action after reconciling actual state.

## Safeguards and outcomes

Objects are resolved to GUIDs and rechecked before a single LDAPS member-link add. Classification excludes privileged identifiers, configured protected inventory, excluded subtrees and privileged parent groups; unknown classification fails closed. Review group/application entitlements that directory nesting alone cannot reveal.

| Outcome | Meaning |
| --- | --- |
| Preview | Eligible proposed change; no membership write |
| AlreadyMember | No membership write needed |
| VerifiedSuccess | Mutation attempted and direct membership verified |
| RejectedBeforeWrite | No membership mutation attempted; review safe ReasonCode |
| RecoveryRequired | State may be uncertain; stop and reconcile before retry |

A local account lock and durable intent evidence precede mutation. An uncertain mutation preserves the lock. A failed lookup, disabled user, stale review, protected identity, invalid mapping or disabled WritesEnabled rejects the request. Credential age must leave a five-minute margin; this does not coordinate OpenBao's independent rotation.

## Evidence and job correlation

Evidence: C:\ProgramData\TSMA\Evidence\GroupMembership\<RunId>.json. Application source: TSMA. Events 4100 intent/preview, 4101 verified success, 4102 rejection and 4103 recovery; 4110 records write-state changes. Configure central event collection separately.

AzureJobId is populated only when valid platform metadata is supplied. If unavailable, use RunId and the Azure job output together. Never guess a job ID from sandbox filenames or the most recent job. Early wrapper rejection can occur before an operation RunId exists.
