#Requires -Version 7.4
# SPDX-License-Identifier: Apache-2.0
[CmdletBinding()]param()
$ErrorActionPreference='Stop'
$base=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $base 'src/vaults/openbao/VaultAuthorization.psm1') -Force
$fixture=@{Mode='Healthy';Requests=[Collections.Generic.List[object]]::new()}
$request={
    param($Endpoint,$Method,$Payload)
    $fixture.Requests.Add(@{Endpoint=$Endpoint;Method=$Method})
    if($Method -eq 'Post'){
        if($Endpoint -ne 'sys/capabilities-self'){throw 'Unsafe management POST attempted'}
        if($fixture.Mode -eq 'Capabilities403'){throw 'RUNBOOK_VAULT_REQUEST_FAILED_403'}
        $caps=@{}
        foreach($path in $Payload.paths){
            $caps[$path]=if($path -eq 'sys/capabilities-self'){@('update')}elseif($path -in @('ldap-operation/static-role/operation-directory','ldap-operation/static-cred/operation-directory')){@('read')}else{@('deny')}
        }
        switch($fixture.Mode){
            'ExtraAllowedCapability' {$caps['ldap-operation/static-cred/operation-directory']=@('read','update')}
            'RotationAllowed' {$caps['ldap-operation/rotate-role/operation-directory']=@('update')}
            'MissingCapability' {$caps.Remove('ldap-operation/rotate-root')}
            'RootCapabilities' {foreach($key in @($caps.Keys)){$caps[$key]=@('root')}}
        }
        if($fixture.Mode -eq 'TopLevel'){return [pscustomobject]$caps}
        return [pscustomobject]@{data=[pscustomobject]$caps}
    }
    if($Method -ne 'Get' -or $Endpoint -like '*/static-cred/*'){throw 'Unexpected credential read or request method'}
    switch($fixture.Mode){
        'ReadAllowed' {return @{SensitiveBody='DO-NOT-EMIT'}}
        'NotFound' {throw 'RUNBOOK_VAULT_REQUEST_FAILED_404'}
        'Transport' {throw 'RUNBOOK_VAULT_REQUEST_FAILED_transport'}
        default {throw 'RUNBOOK_VAULT_REQUEST_FAILED_403'}
    }
}.GetNewClosure()
$count=0
foreach($mode in @('Healthy','TopLevel','ExtraAllowedCapability','RotationAllowed','MissingCapability','RootCapabilities','Capabilities403','ReadAllowed','NotFound','Transport')){
    $fixture.Mode=$mode
    $result=Test-OperationDirectoryVaultAuthorization -Request $request
    $shouldPass=$mode -in @('Healthy','TopLevel')
    if($result.AllPassed -ne $shouldPass -or $result.CheckCount -ne 18){throw "Incorrect diagnostic verdict: $mode"}
    if(($result|ConvertTo-Json -Depth 6) -match 'DO-NOT-EMIT'){throw 'Response body leaked'}
    $count++
}
if(@($fixture.Requests | Where-Object {$_.Method -eq 'Post' -and $_.Endpoint -ne 'sys/capabilities-self'}).Count){throw 'A target-management POST was sent'}
[pscustomobject]@{Checks=$count;Failed=0;LiveVaultContacted=$false}
