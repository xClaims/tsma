#Requires -Version 7.4
# SPDX-License-Identifier: Apache-2.0
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidOverwritingBuiltInCmdlets','',Justification='Offline fixture mocks module imports.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars','',Justification='Unique fixture state crosses script scopes and is removed in finally.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions','',Justification='Mock records role assignments in memory only.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSupportsShouldProcess','',Justification='Read-only REST mock accepts SDK WhatIf/Confirm parameters to verify preview behavior.')]
[CmdletBinding()]param()
$ErrorActionPreference='Stop'
$scriptPath=Join-Path (Split-Path $PSScriptRoot -Parent) 'deployment/azure/Set-OperationRoleAssignments.ps1'
$global:OperationRbacTest=@{Assignments=[Collections.Generic.List[object]]::new();WrongTenant=$false;DuplicateGroup=$false;Conditional=$false;MissingMetadata=$false;SyncedGroup=$false;DynamicGroup=$false}
$fixture=New-Module -ScriptBlock {
    function Import-Module {param($Name,$ErrorAction)$null=$Name;$null=$ErrorAction}
    function Get-AzContext {
        $tenant=if($global:OperationRbacTest.WrongTenant){'33333333-3333-3333-3333-333333333333'}else{'11111111-1111-1111-1111-111111111111'}
        [pscustomobject]@{Tenant=@{Id=$tenant};Subscription=@{Id='22222222-2222-2222-2222-222222222222'}}
    }
    function Get-AzResource {param($ResourceId,$ErrorAction)$null=$ResourceId;$null=$ErrorAction;[pscustomobject]@{ResourceType='Microsoft.Automation/automationAccounts'}}
    function Get-AzRoleDefinition {
        param($Id,$ErrorAction)$null=$ErrorAction
        $name=if($Id -eq 'd3881f73-407a-4167-8283-e981cbba0404'){'Automation Operator'}else{'Reader'}
        [pscustomobject]@{Name=$name;IsCustom=$false}
    }
    function Invoke-AzRestMethod {
        param($Uri,$Method,$WhatIf,$Confirm,$ErrorAction)
        $null=$Confirm;$null=$ErrorAction
        if($Method -ne 'GET' -or $WhatIf){throw 'Group lookup must be a real read-only GET, including during preview'}
        $filter=[uri]::UnescapeDataString((($Uri -split '\?')[1] -split '&')[0].Substring('$filter='.Length))
        $name=($filter -split "'")[1]
        # Raw Graph JSON has null on-premises state for cloud-native groups,
        # unlike the generated Az model that may omit/rename these properties.
        $group=@{id=$name;displayName=$name;securityEnabled=$true;mailEnabled=$false;onPremisesSyncEnabled=$null;isAssignableToRole=$null;groupTypes=@()}
        if($global:OperationRbacTest.MissingMetadata){$group.Remove('onPremisesSyncEnabled')}
        if($global:OperationRbacTest.SyncedGroup){$group.onPremisesSyncEnabled=$true}
        if($global:OperationRbacTest.DynamicGroup){$group.groupTypes=@('DynamicMembership')}
        $items=@($group)
        if($global:OperationRbacTest.DuplicateGroup -and $name -eq 'sg-operation-automation-auditors'){$items+=@($group)}
        [pscustomobject]@{StatusCode=200;Content=(@{value=$items}|ConvertTo-Json -Depth 6)}
    }
    function Get-AzRoleAssignment {
        param($ObjectId,$Scope,$ErrorAction)$null=$ErrorAction
        if($global:OperationRbacTest.Conditional){
            [pscustomobject]@{ObjectId=$ObjectId;Scope=$Scope;RoleDefinitionId='d3881f73-407a-4167-8283-e981cbba0404';Condition='existing-condition'}
        }else{$global:OperationRbacTest.Assignments | Where-Object {$_.ObjectId -eq $ObjectId -and $_.Scope -eq $Scope}}
    }
    function New-AzRoleAssignment {
        param($ObjectId,$ObjectType,$RoleDefinitionId,$Scope,$ErrorAction)$null=$ErrorAction
        if($ObjectType -ne 'Group'){throw 'Wrong principal type'}
        $global:OperationRbacTest.Assignments.Add([pscustomobject]@{ObjectId=$ObjectId;RoleDefinitionId=$RoleDefinitionId;Scope=$Scope;Condition=$null})
    }
}
try{
    & $fixture {
        param($ScriptPath)
        $prefix='/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-operation/providers/Microsoft.Automation/automationAccounts/'
        $inputs=@{TenantId='11111111-1111-1111-1111-111111111111';DirectoryAutomationAccountId=($prefix+'aa-directory')}
        $preview=@(& $ScriptPath @inputs -WhatIf)
        if($preview.Count -ne 2 -or $global:OperationRbacTest.Assignments.Count){throw 'WhatIf wrote assignments'}
        $global:OperationRbacTest.DuplicateGroup=$true
        try{$null=& $ScriptPath @inputs -Confirm:$false;throw 'Expected group refusal'}catch{if($_.Exception.Message -notlike 'Expected one group*'){throw}}
        if($global:OperationRbacTest.Assignments.Count){throw 'Preflight failed after writes'}
        $global:OperationRbacTest.DuplicateGroup=$false
        $result=@(& $ScriptPath @inputs -Confirm:$false)
        if($result.Count -ne 2 -or @($result|Where-Object Status -ne Assigned).Count){throw 'Directory role grants failed'}
        $again=@(& $ScriptPath @inputs -Confirm:$false)
        if($global:OperationRbacTest.Assignments.Count -ne 2 -or @($again|Where-Object Status -ne AlreadyAssigned).Count){throw 'Repeated grants were not skipped'}
        $both=@(& $ScriptPath @inputs -ServerAutomationAccountId ($prefix+'aa-server') -Confirm:$false)
        if($both.Count -ne 4 -or $global:OperationRbacTest.Assignments.Count -ne 4){throw 'Two-account grants failed'}
        if(@($both|Where-Object {$_.GroupName -match 'publishers|administrators' -or $_.RoleName -notin @('Reader','Automation Operator')}).Count){throw 'Unapproved role granted'}
        $global:OperationRbacTest.WrongTenant=$true
        try{$null=& $ScriptPath @inputs -Confirm:$false;throw 'Expected context refusal'}catch{if($_.Exception.Message -notlike 'Select the intended Azure tenant*'){throw}}
        $global:OperationRbacTest.WrongTenant=$false
        try{$null=& $ScriptPath @inputs -ServerAutomationAccountId $inputs.DirectoryAutomationAccountId -Confirm:$false;throw 'Expected isolation refusal'}catch{if($_.Exception.Message -notlike 'Directory and Server*'){throw}}
        $global:OperationRbacTest.Conditional=$true
        try{$null=& $ScriptPath @inputs -Confirm:$false;throw 'Expected conditional refusal'}catch{if($_.Exception.Message -notlike 'An existing conditional assignment*'){throw}}
        if($global:OperationRbacTest.Assignments.Count -ne 4){throw 'Refused configuration caused writes'}
        $global:OperationRbacTest.Conditional=$false
        $global:OperationRbacTest.MissingMetadata=$true
        try{$null=& $ScriptPath @inputs -Confirm:$false;throw 'Expected metadata refusal'}catch{if($_.Exception.Message -notlike 'Group metadata is incomplete*'){throw}}
        $global:OperationRbacTest.MissingMetadata=$false
        foreach($flag in @('SyncedGroup','DynamicGroup')){
            $global:OperationRbacTest[$flag]=$true
            try{$null=& $ScriptPath @inputs -Confirm:$false;throw 'Expected group type refusal'}catch{if($_.Exception.Message -notlike 'Expected a cloud-only assigned security group*'){throw}}
            $global:OperationRbacTest[$flag]=$false
        }
        if($global:OperationRbacTest.Assignments.Count -ne 4){throw 'Invalid group metadata caused writes'}
        [pscustomobject]@{Checks=11;Failed=0;AzureContacted=$false}
    } $scriptPath
}finally{
    Remove-Module $fixture -ErrorAction SilentlyContinue
    Remove-Variable OperationRbacTest -Scope Global -ErrorAction SilentlyContinue
}
