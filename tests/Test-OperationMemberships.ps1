#Requires -Version 7.4
# SPDX-License-Identifier: Apache-2.0
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidOverwritingBuiltInCmdlets','',Justification='Offline fixture mocks module discovery/imports.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars','',Justification='Isolated fixture state crosses external script scopes and is removed in finally.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions','',Justification='Graph mock only updates an in-memory membership map.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSupportsShouldProcess','',Justification='Mock accepts the SDK Confirm parameter but has no external side effects.')]
[CmdletBinding()]param()
$ErrorActionPreference='Stop'
$scriptPath=Join-Path (Split-Path $PSScriptRoot -Parent) 'deployment/azure/Add-OperationUserMemberships.ps1'
$global:OperationMembershipTest=@{Writes=0;Members=@{};WrongTenant=$false;BadGroup=$false;FailRequest=$false;HideMembers=$false}
$fixture=New-Module -ScriptBlock {
    function Import-Module {
        param($Name,$RequiredVersion,$ErrorAction)
        $null=$Name;$null=$ErrorAction
        if($RequiredVersion -ne [version]'9.9.9'){throw 'Unpinned Graph import'}
    }
    function Get-Module {
        param($Name,[switch]$ListAvailable)
        if($ListAvailable){foreach($n in $Name){[pscustomobject]@{Name=$n;Version=[version]'9.9.9'}}}
    }
    function Get-MgContext {
        $id=if($global:OperationMembershipTest.WrongTenant){'22222222-2222-2222-2222-222222222222'}else{'11111111-1111-1111-1111-111111111111'}
        [pscustomobject]@{TenantId=$id;Environment='Global'}
    }
    function Get-MgUser {
        param($Filter,[switch]$All,$Property)
        $null=$All;$null=$Property
        $upn=($Filter -split "'")[1]
        [pscustomobject]@{Id=('u-'+$upn);UserPrincipalName=$upn;UserType='Member';OnPremisesSyncEnabled=$false;AccountEnabled=$true}
    }
    function Get-MgGroup {
        param($Filter,[switch]$All,$Property)
        $null=$All;$null=$Property
        $name=($Filter -split "'")[1]
        $types=if($global:OperationMembershipTest.BadGroup -and $name -eq 'sg-operation-automation-auditors'){@('DynamicMembership')}else{@()}
        [pscustomobject]@{Id=$name;DisplayName=$name;SecurityEnabled=$true;MailEnabled=$false;GroupTypes=@($types);OnPremisesSyncEnabled=$false;IsAssignableToRole=$false}
    }
    function Get-MgGroupMember {
        param($GroupId,[switch]$All)
        $null=$All
        if(-not $global:OperationMembershipTest.HideMembers){
            foreach($id in @($global:OperationMembershipTest.Members[$GroupId])){if($id){[pscustomobject]@{Id=$id}}}
        }
    }
    function New-MgGroupMemberByRef {
        param($GroupId,$BodyParameter,$Confirm,$ErrorAction)
        $null=$Confirm;$null=$ErrorAction
        $global:OperationMembershipTest.Writes++
        if($global:OperationMembershipTest.FailRequest){throw 'Simulated Graph failure'}
        $id=$BodyParameter['@odata.id'].Substring('https://graph.microsoft.com/v1.0/directoryObjects/'.Length)
        $global:OperationMembershipTest.Members[$GroupId]=@($global:OperationMembershipTest.Members[$GroupId])+$id
    }
}
try {
    & $fixture {
        param($ScriptPath)
        $inputs=@{TenantId='11111111-1111-1111-1111-111111111111';UpnDomain='example.onmicrosoft.com';WarningAction='SilentlyContinue'}
        $preview=@(& $ScriptPath @inputs -WhatIf)
        if($preview.Count -ne 5 -or $global:OperationMembershipTest.Writes){throw 'WhatIf wrote memberships'}
        $global:OperationMembershipTest.BadGroup=$true
        try{$null=& $ScriptPath @inputs -Confirm:$false;throw 'Expected preflight refusal'}catch{if($_.Exception.Message -notlike 'Group must be*'){throw}}
        if($global:OperationMembershipTest.Writes){throw 'Late preflight failure wrote earlier memberships'}
        $global:OperationMembershipTest.BadGroup=$false
        $added=@(& $ScriptPath @inputs -Confirm:$false)
        if($global:OperationMembershipTest.Writes -ne 5 -or @($added|Where-Object Status -ne Added).Count){throw 'Expected five confirmed additions'}
        $again=@(& $ScriptPath @inputs -Confirm:$false)
        if($global:OperationMembershipTest.Writes -ne 5 -or @($again|Where-Object Status -ne AlreadyMember).Count){throw 'Rerun was not idempotent'}
        $global:OperationMembershipTest.Members=@{}
        $only=@(& $ScriptPath @inputs -UserName azaut-dir-01 -Confirm:$false)
        if($only.Count -ne 1 -or $global:OperationMembershipTest.Writes -ne 6){throw 'Subset selection failed'}
        $global:OperationMembershipTest.WrongTenant=$true
        try{$null=& $ScriptPath @inputs -Confirm:$false;throw 'Expected context refusal'}catch{if($_.Exception.Message -notlike 'Connect Microsoft Graph*'){throw}}
        if($global:OperationMembershipTest.Writes -ne 6){throw 'Wrong tenant wrote memberships'}
        $global:OperationMembershipTest.WrongTenant=$false
        $global:OperationMembershipTest.HideMembers=$true
        $pending=@(& $ScriptPath @inputs -UserName azaut-dir-01 -Confirm:$false)
        if($pending[0].Status -ne 'PendingVerification'){throw 'Unverified write claimed success'}
        $global:OperationMembershipTest.FailRequest=$true
        try{$null=& $ScriptPath @inputs -UserName azaut-dir-01 -Confirm:$false;throw 'Expected write refusal'}catch{if($_.Exception.Message -notlike 'Membership request failed*'){throw}}
        [pscustomobject]@{Checks=8;Failed=0;LiveGraphContacted=$false}
    } $scriptPath
} finally {
    Remove-Module $fixture -ErrorAction SilentlyContinue
    Remove-Variable OperationMembershipTest -Scope Global -ErrorAction SilentlyContinue
}
