# Optional production security: Microsoft Entra PIM

Use this procedure to require time-limited human activation before starting TSMA runbooks. PIM is an optional deployment configuration: installations without it use the baseline Azure RBAC procedure. Configure PIM in Microsoft Entra; the TSMA worker and business runbooks continue to use the same credential and operation interfaces.

See [approval and execution workflows](../WORKFLOWS.md) for how activation approval relates to Azure authorization and runbook execution.

## 1. Prerequisites and ownership

Complete [operator access](../setup/OPERATOR-ACCESS.md), confirm working baseline invocation, and record the tenant, group object IDs, Azure scopes, current memberships, accountable service owner, access administrator, approvers and emergency contacts.

Every user eligible for PIM group membership/ownership needs an appropriate Microsoft Entra ID P2 or Microsoft Entra ID Governance license. Assess approver/reviewer requirements under the current [licensing terms](https://learn.microsoft.com/en-us/entra/id-governance/licensing-fundamentals). One tenant license does not cover every participant. This procedure uses PIM for Groups and does not depend on preview app-role activation or preview bulk conversion features.

Perform configuration as an authorized group owner/access administrator with permissions appropriate to the group type. Confirm the supported authority in [Microsoft's group eligibility procedure](https://learn.microsoft.com/en-us/entra/id-governance/privileged-identity-management/groups-assign-member-owner). Protect owner and access-administrator identities: they can change group membership outside the activation process.

## 2. Preserve the Azure authorization boundary

Use the group names expected by the baseline helpers:

| Group | PIM treatment |
| --- | --- |
| sg-operation-directory-operators | Eligible human Member assignments for ordinary directory invocation |
| sg-operation-server-operators | Apply the same approach when the separate server-operation service is deployed |
| sg-operation-runbook-publishers | Govern membership for separately assigned, reviewed publishing access |
| sg-operation-platform-administrators | Govern membership for separately assigned platform-administration access |
| sg-operation-automation-auditors | Standing or eligible read access according to the audit policy |

The baseline helper grants Automation Operator and Reader at Automation-account scope. PIM changes when the human gains that access; it does not narrow its scope. Keep only runbooks approved for that operator class in the account. Use Microsoft's reviewed per-runbook role combination when finer invocation separation is required. Creating a publisher/platform group does not itself assign its Azure permissions.

Inventory direct user grants, inherited Azure roles, nested group paths and privileged account access. A permanent alternative grant can bypass PIM eligibility. Record the intended removals and an approved recovery path before changing access.

## 3. Bring the group under PIM management

In the Microsoft Entra admin center, open ID Governance -> Privileged Identity Management -> Groups. Use Discover groups to select the existing security group and bring it under management when it is not already listed. Select the group by its recorded object ID, not merely a display name. See [bringing groups into PIM](https://learn.microsoft.com/en-us/entra/id-governance/privileged-identity-management/groups-discover-groups).

Use assigned-membership cloud security groups as configured in the baseline. isAssignableToRole does not need to be enabled for this TSMA group-membership use case. Do not change it to obtain PIM capabilities.

## 4. Configure Member and Owner activation policies

Within the selected PIM group, open Settings and edit the Member policy. Configure the Owner policy separately; do not leave ownership as an unreviewed route to granting access.

The following is a recommended starting policy to be approved by the accountable service owner, not a hard-coded TSMA requirement:

| Setting | Operator membership | Publishing/administration membership |
| --- | --- | --- |
| Maximum activation duration | One hour | One hour or a shorter approved duration |
| Activation authentication | Require MFA; use an approved authentication context where configured | Require the approved stronger authentication policy |
| Justification | Required; include the relevant change/incident reference | Required; include the release/change reference |
| Activation approval | Named approver distinct from the requester | Independent named approver |
| Eligibility | Time-bound, with a recorded review/renewal date | Time-bound, with a recorded review/renewal date |
| Notifications | Access administrators and accountable service contacts | Access administrators and release/security contacts |

Set actual people/groups as approvers; do not leave placeholders or depend on the requesting operator approving their own access. Test backup approver coverage and timeout handling. Configure assignment policy to prohibit unintended permanent eligible/active assignments and apply the organization's approved eligibility duration. Schedule appropriate access reviews and remove expired eligibility that no longer has a business owner.

The available MFA/authentication-context options have their own tenant prerequisites. Apply matching Conditional Access policy when using an authentication context; selecting a label alone is not the complete policy. Consult [group settings](https://learn.microsoft.com/en-us/entra/id-governance/privileged-identity-management/groups-role-settings).

## 5. Assign eligible members and remove standing bypasses

In the group -> Assignments, review Eligible assignments and Active assignments. Add assignments -> Member -> select the approved named identity -> Next -> Eligible -> set approved start/end dates -> Assign. Use the distinct Owner role only for an identity authorized to administer ownership. Record assignment IDs/dates and the access approval.

Replace intended standing direct memberships and direct Azure role grants through the approved change procedure. Eligibility and permanent membership together do not require activation to use the permanent path. Verify both PIM active assignments and ordinary group membership. Keep only deliberately approved emergency arrangements outside normal activation; do not remove the last viable administrative recovery path.

Perform the change with authorized administrative coverage and an available backup administrator. Do not remove broad access blindly from unrelated services. Preview conversion features are not required: add eligible access and explicitly review/remove the intended standing assignment using supported administration interfaces.

## 6. Operator activation procedure

The named operator opens PIM -> My roles -> Groups -> Eligible assignments, selects the correct group and Activate, completes required authentication, enters justification/change reference and requests only the duration needed. When approval is required, wait for the named approver's decision before starting a job.

After activation, allow group/token/RBAC propagation and refresh the Azure session as necessary. Start the approved published runbook on the intended Hybrid Worker group. Retain the Azure job ID, TSMA RunId and activation/change reference in the operating record. When work finishes, deactivate the membership rather than waiting unnecessarily for expiry. See [operator activation](https://learn.microsoft.com/en-us/entra/id-governance/privileged-identity-management/groups-activate-roles).

A PIM justification or ticket field records context; this procedure does not independently validate CAB approval in an external ticket system.

## 7. Production acceptance and operational sign-off

Use a separate browser/session signed in only as the selected operator. An administrator's overlapping access invalidates the denial test.

| Test | Required result |
| --- | --- |
| Eligible, not active | New job submission is denied |
| Activation awaiting approval | Operator still cannot submit through the protected access path |
| Approved active membership | Approved invocation succeeds |
| Operator tries edit/publish/IAM/worker administration | Denied unless separately and deliberately authorized |
| Membership deactivated/expired | New invocation is denied after propagation; inspect cached/inherited access if it is not |
| Approver unavailable | Backup/timeout and escalation behave according to policy |
| Emergency recovery | Authorized recovery works and is logged without creating an uncontrolled permanent bypass |

Record tester, tenant/group/scope IDs, policy settings, eligibility/activation times, approver, observed propagation, job/RunId correlation and service-owner sign-off. Preserve PIM/Entra audit and Azure job records alongside TSMA evidence under the retention policy. Configure notifications/monitoring and review group ownership, direct grants and eligibility routinely.

Expiration/deactivation is not a guarantee of instantaneous Azure token revocation, cancellation of queued/running work, or termination of AD sessions. Already admitted work follows the operation's completion/recovery rules. Use the separate incident-response procedure for urgent containment rather than relying only on group expiry.

## 8. Recovery and change control

If activation or approval fails, first check licensing, eligible assignment dates, owner/member policy, approver coverage, authentication/Conditional Access, group identity, Azure effective access and token propagation. Do not weaken the vault's JWT bindings or grant the worker a broader credential to fix human access.

During a PIM configuration incident, use the separately approved emergency administrator path. Any temporary direct group/role assignment needs a named owner, bounded duration, incident record, monitoring and removal verification. Restore the intended eligibility model and repeat denial/activation checks before closing the incident.

PIM controls human Azure access. It does not rotate AD passwords, grant Domain Admins/Enterprise Admins/Schema Admins membership or replace worker/vault/AD boundaries. Protect publishers and worker administrators because they can influence code that retrieves credentials. Keep the Arc identity, narrow OpenBao policy and AD delegation independently enforced.
