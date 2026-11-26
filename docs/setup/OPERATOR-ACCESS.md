# Create operator groups and scoped Azure access

**Run on:** the management workstation using separately authorized Entra group and Azure access administrators. No AD group membership, execution password or vault token is given to the human operator.

For the first deployment use existing named human identities whenever possible. Dedicated cloud-only administrative identities are also possible, but each must have an accountable individual and your authentication policy. Sample AzAUT names are examples, not a requirement to create shared accounts.

## 1. Create cloud security groups

The current baseline assignment helper expects the exact group names below. Its operator role is account-scoped, not per-runbook. Use an Automation account containing only runbooks approved for that operator class; do not mix higher-privilege runbooks in that account and claim isolation.

| Group | Initial purpose |
| --- | --- |
| sg-operation-directory-operators | Start/manage ordinary directory jobs |
| sg-operation-server-operators | Reserved for a separate member-server service; no rights assigned by the directory-only path |
| sg-operation-runbook-publishers | Publisher governance group; baseline helper does not grant it edit/publish rights |
| sg-operation-platform-administrators | Platform governance group; baseline helper does not grant it Owner/Contributor |
| sg-operation-automation-auditors | Read the selected Automation account/jobs |

In a fresh PowerShell 7 process, install/import a matching Authentication, Users and Groups set:

~~~powershell
$graphVersion=(Find-PSResource -Name Microsoft.Graph.Authentication -Repository PSGallery).Version.ToString()
Install-PSResource -Name Microsoft.Graph.Authentication,Microsoft.Graph.Users,Microsoft.Graph.Groups -Version $graphVersion -Repository PSGallery -Scope CurrentUser
Import-Module Microsoft.Graph.Authentication -RequiredVersion $graphVersion
Import-Module Microsoft.Graph.Users -RequiredVersion $graphVersion
Import-Module Microsoft.Graph.Groups -RequiredVersion $graphVersion
~~~

Then connect and create the groups:

~~~powershell
$tenantId='<your-tenant-guid>'
Connect-MgGraph -TenantId $tenantId -Scopes 'Group.ReadWrite.All','User.Read.All'
$names=@('sg-operation-directory-operators','sg-operation-server-operators','sg-operation-runbook-publishers','sg-operation-platform-administrators','sg-operation-automation-auditors')
foreach($name in $names){
    $existing=@(Get-MgGroup -Filter "displayName eq '$name'" -All -ErrorAction Stop)
    if($existing.Count -gt 1){throw ('Duplicate group names: '+$name)}
    if($existing.Count -eq 0){
        New-MgGroup -DisplayName $name -MailEnabled:$false -MailNickname $name -SecurityEnabled:$true -GroupTypes @() -IsAssignableToRole:$false -ErrorAction Stop |
            Select-Object Id,DisplayName
    } else {
        $existing | Select-Object Id,DisplayName
    }
}
~~~

These must be assigned-membership cloud security groups, not synchronized, dynamic, mail-enabled or Entra-role-assignable groups. Inspect existing groups rather than trusting display names alone. Group ownership is a privileged access path: set real accountable owners in Entra admin center -> Groups -> group -> Owners and protect their accounts. Optional PIM for Groups does not require isAssignableToRole=True.

## 2. Add one approved named operator

Resolve both objects and inspect before adding:

~~~powershell
$operatorUpn='named.operator@your-verified-domain.example' # Replace.
$operator=Get-MgUser -UserId $operatorUpn -Property Id,UserPrincipalName,AccountEnabled -ErrorAction Stop
$groups=@(Get-MgGroup -Filter "displayName eq 'sg-operation-directory-operators'" -All -ErrorAction Stop)
if($groups.Count -ne 1 -or -not $operator.AccountEnabled){throw 'Resolve one group and an enabled named operator first.'}
$operator | Select-Object Id,UserPrincipalName
$groups | Select-Object Id,DisplayName
~~~

After reviewing the IDs, add only the selected operator if not already a member:

~~~powershell
$group=$groups[0]
$present=@(Get-MgGroupMember -GroupId $group.Id -All | Where-Object Id -eq $operator.Id)
if(-not $present.Count){
    New-MgGroupMemberByRef -GroupId $group.Id -BodyParameter @{'@odata.id'=('https://graph.microsoft.com/v1.0/directoryObjects/'+$operator.Id)}
}
Get-MgGroupMember -GroupId $group.Id -All | Where-Object Id -eq $operator.Id | Select-Object Id
~~~

Install matching Microsoft.Graph.Users as well if using Get-MgUser; see [tool preparation](AZURE-WORKER.md) and [Graph installation](https://learn.microsoft.com/en-us/powershell/microsoftgraph/installation). If planning dedicated AzAUT identities, New-OperationUsers.ps1, Operation-Users.example.csv and Add-OperationUserMemberships.ps1 are optional administrative helpers with fixed role-name conventions. Review the CSV, replace AssignedTo with real ownership records, use a verified tenant UPN domain, preview WhatIf and assign no license/privileged role by assumption. AssignedTo is a recordkeeping label, not an enforced Entra ownership attribute.

## 3. Grant baseline Azure access

In a separate fresh Az session, authenticate to the correct tenant/subscription and use the actual Automation account resource ID from the worksheet:

~~~powershell
$tenantId='<your-tenant-guid>'
$subscriptionId='<your-subscription-guid>'
Connect-AzAccount -Tenant $tenantId -Subscription $subscriptionId
$accountId='/subscriptions/<subscription-guid>/resourceGroups/<your-resource-group>/providers/Microsoft.Automation/automationAccounts/<your-account>'
Set-Location C:\Code\tsma
.\deployment\azure\Set-OperationRoleAssignments.ps1 -TenantId $tenantId -DirectoryAutomationAccountId $accountId -WhatIf
~~~

Review, then run without WhatIf. The helper grants Automation Operator to the directory-operator group and Reader to the auditor group on that account. Publisher/platform groups remain unassigned by this helper. It does not remove inherited access or enable PIM. Azure role-assignment authority and group-read permission are required; consent in a separate Graph session does not automatically fix the Az token's Graph permissions. If Az-based group lookup is forbidden, an authorized access administrator can assign the same group object IDs through the account's Access control (IAM) UI.

Automation Operator can manage jobs across the account. For per-runbook access, follow the documented Automation Job Operator/Automation Runbook Operator combination and validate its actual effective access; the bundled helper does not implement that finer model. Do not describe account-wide grants as restricting each operator to one approved runbook. See [Microsoft Automation RBAC](https://learn.microsoft.com/en-us/azure/automation/automation-role-based-access-control).

## 4. Verify as the operator

Use a separate browser profile signed in only as the selected operator. Open the Automation account and run a published read-only identity/health job on the intended Hybrid Worker group. Confirm job output is visible, but editing/publishing runbooks, changing IAM, installing extensions and reading/modifying the worker OS are not authorized. Remove direct/inherited broad grants that would invalidate the test only through your approved access-change process.

A no-active-workers message visible only to an operator can indicate missing worker read permissions; confirm the actual heartbeat and effective RBAC instead of blindly re-registering. New assignments can take time to propagate. Keep job output free of credentials because operators/auditors may read it.

## 5. Optional production access control with PIM

To require human activation, follow the [optional PIM production procedure](../advanced/ENTRA-PIM.md) and replace intended standing human membership with eligible time-limited access after verifying baseline connectivity. Do not grant PIM to the workload merely to keep scheduled jobs functioning. Workers and human activation have separate lifecycles.
