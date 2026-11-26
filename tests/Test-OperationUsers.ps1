#Requires -Version 7.4
# SPDX-License-Identifier: Apache-2.0
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidOverwritingBuiltInCmdlets','',Justification='Offline fixture mocks imports and password input.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars','',Justification='Fixture state crosses external script scopes and is removed in finally.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions','',Justification='New-MgUser mock only records request contracts.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText','',Justification='Public offline fixture string, never a live account credential.')]
[CmdletBinding()]param()
$ErrorActionPreference='Stop'
$scriptPath=Join-Path (Split-Path $PSScriptRoot -Parent) 'deployment/azure/New-OperationUsers.ps1'
$global:OperationUserTestState=@{Created=0;Reads=0;Existing=$false;WrongTenant=$false;Federated=$false;MissingSet=$false}
$fixture=New-Module -ScriptBlock {
    function Import-Module {param($Name,$RequiredVersion,$ErrorAction) $null=$Name;$null=$ErrorAction; if($RequiredVersion -ne [version]'9.9.9'){throw 'Unpinned Graph import'}}
    function Get-Module {
        param($Name,[switch]$ListAvailable)
        if($ListAvailable){
            foreach($n in $Name){
                if($global:OperationUserTestState.MissingSet -and $n -eq 'Microsoft.Graph.Identity.DirectoryManagement'){continue}
                [pscustomobject]@{Name=$n;Version=[version]'9.9.9'}
            }
            [pscustomobject]@{Name='Microsoft.Graph.Authentication';Version=[version]'10.0.0'}
        }elseif($Name -eq 'Microsoft.Graph.Authentication'){
            [pscustomobject]@{Name='Microsoft.Graph.Authentication';Version=[version]'9.9.9'}
        }
    }
    function Get-MgContext {
        $id=if($global:OperationUserTestState.WrongTenant){'22222222-2222-2222-2222-222222222222'}else{'11111111-1111-1111-1111-111111111111'}
        [pscustomobject]@{TenantId=$id}
    }
    function Get-MgDomain {
        param([switch]$All,$Property)
        $null=$All;$null=$Property
        $type=if($global:OperationUserTestState.Federated){'Federated'}else{'Managed'}
        [pscustomobject]@{Id='example.onmicrosoft.com';IsVerified=$true;AuthenticationType=$type}
    }
    function Get-MgUser {
        param($Filter,[switch]$All,$Property)
        $null=$All;$null=$Property
        if($global:OperationUserTestState.Existing){
            [pscustomobject]@{Id='existing-id';UserPrincipalName=$Filter;DisplayName='Existing';UserType='Member';OnPremisesSyncEnabled=$false}
        }
    }
    function Read-Host {
        param($Prompt,[switch]$AsSecureString)
        $null=$Prompt
        if(-not $AsSecureString){throw 'Password input was not hidden'}
        $global:OperationUserTestState.Reads++
        ConvertTo-SecureString 'OfflineFixturePassword-123!' -AsPlainText -Force
    }
    function New-MgUser {
        param($BodyParameter,$ErrorAction)
        $null=$ErrorAction
        if(-not $BodyParameter.passwordProfile.forceChangePasswordNextSignIn -or $BodyParameter.passwordProfile.password -ne 'OfflineFixturePassword-123!' -or -not $BodyParameter.accountEnabled){throw 'Creation contract failed'}
        $global:OperationUserTestState.Created++
        [pscustomobject]@{Id=[guid]::NewGuid().ToString()}
    }
}
try {
    & $fixture {
        param($ScriptPath)
        $argsForUser=@{TenantId='11111111-1111-1111-1111-111111111111';UpnDomain='example.onmicrosoft.com'}
        $preview=@(& $ScriptPath @argsForUser -WhatIf)
        if($preview.Count -ne 5 -or $global:OperationUserTestState.Created -or $global:OperationUserTestState.Reads){throw 'WhatIf prompted or wrote'}
        $created=@(& $ScriptPath @argsForUser -Confirm:$false)
        if($global:OperationUserTestState.Created -ne 5 -or $global:OperationUserTestState.Reads -ne 5 -or @($created|Where-Object Status -ne Created).Count){throw 'Bulk create failed'}
        if(($created|ConvertTo-Json) -match 'OfflineFixturePassword'){throw 'Secret leaked to output'}
        $global:OperationUserTestState.Existing=$true
        $null=& $ScriptPath @argsForUser -Confirm:$false
        if($global:OperationUserTestState.Created -ne 5 -or $global:OperationUserTestState.Reads -ne 5){throw 'Existing user was changed'}
        $global:OperationUserTestState.WrongTenant=$true
        try {$null=& $ScriptPath @argsForUser -Confirm:$false;throw 'Expected tenant refusal'}catch{if($_.Exception.Message -notlike 'Connect Microsoft Graph*'){throw}}
        $global:OperationUserTestState.WrongTenant=$false
        $global:OperationUserTestState.Federated=$true
        try {$null=& $ScriptPath @argsForUser -Confirm:$false;throw 'Expected domain refusal'}catch{if($_.Exception.Message -notlike 'Use a verified managed*'){throw}}
        $global:OperationUserTestState.Federated=$false
        $global:OperationUserTestState.MissingSet=$true
        try {$null=& $ScriptPath @argsForUser -Confirm:$false;throw 'Expected version-set refusal'}catch{if($_.Exception.Message -notlike 'The loaded Graph Authentication version*'){throw}}
        if($global:OperationUserTestState.Created -ne 5){throw 'Version mismatch wrote users'}
        [pscustomobject]@{Checks=6;Failed=0;LiveGraphContacted=$false}
    } $scriptPath
}finally{
    Remove-Module $fixture -ErrorAction SilentlyContinue
    Remove-Variable OperationUserTestState -Scope Global -ErrorAction SilentlyContinue
}
