#Requires -Version 7.4
# SPDX-License-Identifier: Apache-2.0
[CmdletBinding()]param()
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$path=Join-Path ([IO.Path]::GetTempPath()) ('tsma-facade-'+[guid]::NewGuid()+'.json')
$facade=Import-Module (Join-Path $root 'src/contracts/RunbookVault.psm1') -Force -PassThru
$checks=0
try {
    $config=Get-Content -LiteralPath (Join-Path $root 'examples/OperationDirectory.example.json') -Raw | ConvertFrom-Json
    $config | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path
    Initialize-RunbookVault -ConfigurationPath $path
    $provider=& $facade {$script:ProviderModule}
    if($provider.Name -ne 'OpenBao'){throw 'Facade did not load code-owned provider'};$checks++
    # Exercise actual module wiring; replace only the provider transport.
    & $provider {
        function script:Invoke-VaultRequest {
            param($Endpoint)
            $last=[DateTimeOffset]::UtcNow.AddMinutes(-1).ToString('o')
            if($Endpoint -like '*/static-role/*'){return @{data=@{username='svc-op-directory';dn='CN=svc-op-directory,OU=Service Accounts,OU=Tier 0,OU=Admin,DC=ad,DC=example,DC=com';rotation_period=14400;last_vault_rotation=$last}}}
            if($Endpoint -like '*/static-cred/*'){return @{data=@{username='svc-op-directory';password='OFFLINE-FAKE';last_vault_rotation=$last}}}
            throw 'Unexpected fixture request'
        }
    }
    if(-not (Test-RunbookVault -Reference OperationDirectory).Healthy){throw 'Health not dispatched'};$checks++
    $credential=Get-RunbookCredential -Reference OperationDirectory
    if($credential -isnot [pscredential] -or $credential.UserName -cne 'EXAMPLE\svc-op-directory'){throw 'Credential not dispatched'};$credential.Password.Dispose();$checks++
    Close-RunbookVault
    if(& $provider {$null -ne $script:Vault}){throw 'Provider state retained'};$checks++
    try {Get-RunbookCredential;throw 'Expected closed-provider failure'}catch{if($_.Exception.Message -ne 'RUNBOOK_VAULT_UNINITIALIZED'){throw};$checks++}
    [pscustomobject]@{Checks=$checks;Failed=0;LiveServicesContacted=$false;ActualModuleWiringTested=$true}
} finally {& $facade {Close-RunbookVault};Remove-Module RunbookVault -ErrorAction SilentlyContinue;[IO.File]::Delete($path)}
