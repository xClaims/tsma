#Requires -Version 7.4
# SPDX-License-Identifier: Apache-2.0
<#
.SYNOPSIS
Bulk assign the baseline Operation invocation and audit roles to Entra groups.
.DESCRIPTION
Requires an existing matching Az context and group-read/role-assignment authority.
Only Automation Operator and Reader at Automation-account scopes are assigned.
Publisher/platform roles remain deferred. No direct-user grants or removals.
#>
[CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')]
param(
    [Parameter(Mandatory)][guid]$TenantId,
    [Parameter(Mandatory)][string]$DirectoryAutomationAccountId,
    [string]$ServerAutomationAccountId
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module Az.Accounts -ErrorAction Stop
Import-Module Az.Resources -ErrorAction Stop
$context=Get-AzContext
if($null -eq $context -or $context.Tenant.Id -ne $TenantId.ToString()){
    throw 'Select the intended Azure tenant and subscription before role assignment.'
}
$scopePattern='^/subscriptions/([0-9a-fA-F-]{36})/resourceGroups/([^/]+)/providers/Microsoft\.Automation/automationAccounts/([^/]+)$'
$scopes=[Collections.Generic.List[object]]::new()
foreach($service in @('Directory','Server')){
    $id=if($service -eq 'Directory'){$DirectoryAutomationAccountId}else{$ServerAutomationAccountId}
    if([string]::IsNullOrWhiteSpace($id)){
        if($service -eq 'Directory'){throw 'Directory Automation account ID is required.'}
        continue
    }
    $id=$id.TrimEnd('/')
    if($id -notmatch $scopePattern){throw "Invalid Automation account resource ID for $service."}
    $subscription=[guid]::Parse($Matches[1])
    if($context.Subscription.Id -ne $subscription.ToString()){throw 'All scopes must belong to the selected Azure subscription.'}
    if(@($scopes | Where-Object Scope -ieq $id).Count){throw 'Directory and Server services must use different Automation accounts.'}
    $resource=Get-AzResource -ResourceId $id -ErrorAction Stop
    if($resource.ResourceType -ine 'Microsoft.Automation/automationAccounts'){throw 'Scope is not an Automation account.'}
    $scopes.Add([pscustomobject]@{Service=$service;Scope=$id})
}
$roleIds=@{
    'Automation Operator'='d3881f73-407a-4167-8283-e981cbba0404'
    'Reader'='acdd72a7-3385-48ef-bd42-f606fba81ae7'
}
foreach($name in $roleIds.Keys){
    $role=Get-AzRoleDefinition -Id $roleIds[$name] -ErrorAction Stop
    if($null -eq $role -or $role.IsCustom -or $role.Name -ne $name){throw "Built-in role validation failed: $name"}
}
$plan=[Collections.Generic.List[object]]::new()
$groupCache=@{}
foreach($scope in $scopes){
    $operatorName=if($scope.Service -eq 'Directory'){'sg-operation-directory-operators'}else{'sg-operation-server-operators'}
    foreach($mapping in @(
        @{Group=$operatorName;Role='Automation Operator'},
        @{Group='sg-operation-automation-auditors';Role='Reader'}
    )){
        $groupName=$mapping.Group
        if(-not $groupCache.ContainsKey($groupName)){
            # Read Graph JSON directly: Az.Resources models rename/drop some Graph
            # fields (for example groupTypes -> GroupType). Preserve explicit nulls.
            $filter=[uri]::EscapeDataString("displayName eq '$groupName'")
            $select='id,displayName,securityEnabled,mailEnabled,groupTypes,onPremisesSyncEnabled,isAssignableToRole'
            $uri='https://graph.microsoft.com/v1.0/groups?$filter='+$filter+'&$select='+$select+'&$top=2'
            $response=Invoke-AzRestMethod -Uri $uri -Method GET -WhatIf:$false -Confirm:$false -ErrorAction Stop
            if($response.StatusCode -ne 200){throw "Group lookup failed for $groupName."}
            $payload=$response.Content | ConvertFrom-Json -AsHashtable
            if(-not $payload.ContainsKey('value')){throw "Group lookup returned an unexpected response for $groupName."}
            $groups=@($payload['value'])
            if($groups.Count -ne 1 -or $payload.ContainsKey('@odata.nextLink')){throw "Expected one group named $groupName; create it in Phase 3 or resolve duplicate names."}
            $group=$groups[0]
            foreach($property in @('id','displayName','securityEnabled','mailEnabled','groupTypes','onPremisesSyncEnabled','isAssignableToRole')){
                if(-not $group.ContainsKey($property)){
                    throw "Group metadata is incomplete ($property) for $groupName. No assignments have been written."
                }
            }
            $group=[pscustomobject]@{
                Id=$group['id'];DisplayName=$group['displayName']
                SecurityEnabled=$group['securityEnabled'];MailEnabled=$group['mailEnabled']
                OnPremisesSyncEnabled=$group['onPremisesSyncEnabled']
                GroupTypes=$group['groupTypes'];IsAssignableToRole=$group['isAssignableToRole']
            }
            if(-not $group.SecurityEnabled -or $group.MailEnabled -or $group.OnPremisesSyncEnabled -eq $true -or @($group.GroupTypes | Where-Object { $_ }).Count -gt 0 -or $group.IsAssignableToRole -eq $true){
                throw "Expected a cloud-only assigned security group without Entra role-assignability: $groupName"
            }
            $groupCache[$groupName]=$group
        }
        $group=$groupCache[$groupName]
        $assignments=@(Get-AzRoleAssignment -ObjectId $group.Id -Scope $scope.Scope -ErrorAction Stop)
        $exact=@($assignments | Where-Object {
            $_.Scope.TrimEnd('/') -ieq $scope.Scope -and
            ($_.RoleDefinitionId -split '/')[-1] -ieq $roleIds[$mapping.Role]
        })
        if(@($exact | Where-Object { -not [string]::IsNullOrEmpty($_.Condition) }).Count){
            throw "An existing conditional assignment requires manual review: $groupName / $($mapping.Role)"
        }
        if(@($assignments | Where-Object { $_.Scope.TrimEnd('/') -ine $scope.Scope }).Count){
            Write-Warning "$groupName has assignments at other/inherited scopes. Review effective access; this script does not remove or reconcile it."
        }
        $plan.Add([pscustomobject]@{
            Service=$scope.Service;Scope=$scope.Scope;GroupName=$groupName
            GroupId=$group.Id;RoleName=$mapping.Role;RoleId=$roleIds[$mapping.Role]
            Exists=($exact.Count -gt 0)
        })
    }
}
# All selected scopes, groups, roles and existing assignments are resolved before writing.
Write-Verbose 'Publisher and platform-administrator roles remain deferred; no assignments are created for those groups.'
foreach($item in $plan){
    $status='AlreadyAssigned'
    if(-not $item.Exists){
        if($PSCmdlet.ShouldProcess(($item.GroupName+' -> '+$item.Scope),('Assign '+$item.RoleName))){
            try{
                $null=New-AzRoleAssignment -ObjectId $item.GroupId -ObjectType Group -RoleDefinitionId $item.RoleId -Scope $item.Scope -ErrorAction Stop
            }catch{
                throw "Role assignment failed for $($item.GroupName) at $($item.Scope). Inspect current IAM before rerunning; prior assignments remain. $($_.Exception.Message)"
            }
            $after=@(Get-AzRoleAssignment -ObjectId $item.GroupId -Scope $item.Scope -ErrorAction Stop | Where-Object {
                $_.Scope.TrimEnd('/') -ieq $item.Scope -and
                ($_.RoleDefinitionId -split '/')[-1] -ieq $item.RoleId -and
                [string]::IsNullOrEmpty($_.Condition)
            })
            $status=if($after.Count){'Assigned'}else{'PendingVerification'}
            if(-not $after.Count){Write-Warning 'Assignment submitted but not yet visible; allow propagation and rerun to verify.'}
        }else{$status='NotAssigned'}
    }
    [pscustomobject]@{
        Service=$item.Service;GroupName=$item.GroupName;GroupId=$item.GroupId
        RoleName=$item.RoleName;Scope=$item.Scope;Status=$status
    }
}
