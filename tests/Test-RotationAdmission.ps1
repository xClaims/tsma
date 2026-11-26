#Requires -Version 7.4
# SPDX-License-Identifier: Apache-2.0
[CmdletBinding()]param()
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('tsma-rotation-'+[guid]::NewGuid()+'.json')
$checks=0
function Assert-Result {param([bool]$Condition,[string]$Name) if(-not $Condition){throw $Name};$script:checks++}
function Assert-Denied {param([scriptblock]$Action,[string]$Code) $message='';try{& $Action | Out-Null}catch{$message=$_.Exception.Message};Assert-Result ($message -eq $Code) $Code}
try {
    $config=Get-Content -LiteralPath (Join-Path $root 'examples/OperationDirectory.example.json') -Raw | ConvertFrom-Json
    $config | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $fixture
    $provider=Import-Module (Join-Path $root 'src/vaults/openbao/OpenBao.psm1') -Force -PassThru
    Initialize-RunbookVault $fixture
    & $provider {
        $script:Case=@{AgeSeconds=60;Period=86400;Ttl=86340;CredentialAgeSeconds=60;Password='OFFLINE-FIRST';Reads=0}
        function script:Invoke-VaultRequest {
            param($Endpoint)
            if($Endpoint -like '*/static-role/operation-directory'){
                return @{data=@{username='svc-op-directory';dn='CN=svc-op-directory,OU=Service Accounts,OU=Tier 0,OU=Admin,DC=ad,DC=example,DC=com';rotation_period=$script:Case.Period;last_vault_rotation=[DateTimeOffset]::UtcNow.AddSeconds(-$script:Case.AgeSeconds).ToString('o')}}
            }
            if($Endpoint -like '*/static-cred/operation-directory'){
                $script:Case.Reads++
                return @{data=@{username='svc-op-directory';password=$script:Case.Password;ttl=$script:Case.Ttl;last_vault_rotation=[DateTimeOffset]::UtcNow.AddSeconds(-$script:Case.CredentialAgeSeconds).ToString('o')}}
            }
            throw 'Unexpected endpoint: fixture permits reads only'
        }
    }
    foreach($period in @(86400,'86400s','24h','1d')) {
        & $provider {param($Value) $script:Case.Period=$Value} $period
        Assert-Result (Test-RunbookVault).AdmissionAllowed ('Accept equivalent 24-hour duration '+$period)
    }
    & $provider {$script:Case.Period='4h'}
    Assert-Denied {Test-RunbookVault} RUNBOOK_VAULT_METADATA_INVALID
    & $provider {$script:Case.Period=86400;$script:Case.AgeSeconds=84600}
    $health=Test-RunbookVault
    Assert-Result ($health.Healthy -and -not $health.AdmissionAllowed) 'Near-rotation health is distinct from admission'
    Assert-Denied {Get-RunbookCredential} RUNBOOK_VAULT_ROTATION_ADMISSION_DENIED
    Assert-Result ((& $provider {$script:Case.Reads}) -eq 0) 'Reject before credential read'
    & $provider {$script:Case.AgeSeconds=60;$script:Case.Ttl=2100}
    Assert-Denied {Get-RunbookCredential} RUNBOOK_VAULT_ROTATION_ADMISSION_DENIED
    & $provider {$script:Case.Ttl=-1}
    Assert-Denied {Get-RunbookCredential} RUNBOOK_VAULT_ROTATION_ADMISSION_DENIED
    & $provider {$script:Case.Ttl='86340'}
    Assert-Denied {Get-RunbookCredential} RUNBOOK_VAULT_CREDENTIAL_UNAVAILABLE
    & $provider {$script:Case.Ttl=$null}
    Assert-Denied {Get-RunbookCredential} RUNBOOK_VAULT_CREDENTIAL_UNAVAILABLE
    & $provider {$script:Case.Ttl=86340;$script:Case.CredentialAgeSeconds=84600}
    Assert-Denied {Get-RunbookCredential} RUNBOOK_VAULT_ROTATION_ADMISSION_DENIED
    & $provider {$script:Case.CredentialAgeSeconds=3600}
    Assert-Denied {Get-RunbookCredential} RUNBOOK_VAULT_CREDENTIAL_UNAVAILABLE
    & $provider {$script:Case.CredentialAgeSeconds=60}
    $first=Get-RunbookCredential
    try {Assert-Result ($first.GetNetworkCredential().Password -eq 'OFFLINE-FIRST') 'First phase retrieves current credential'}finally{$first.Password.Dispose()}
    & $provider {$script:Case.Password='OFFLINE-SECOND'}
    $second=Get-RunbookCredential
    try {Assert-Result ($second.GetNetworkCredential().Password -eq 'OFFLINE-SECOND') 'Later phase retrieves again rather than caching password'}finally{$second.Password.Dispose()}
    & $provider {$script:Case.Ttl=86340.125}
    $fractional=Get-RunbookCredential
    try {Assert-Result ($fractional -is [pscredential]) 'OpenBao fractional numeric TTL supported'}finally{$fractional.Password.Dispose()}
    & $provider {$script:Case.Ttl=[double]::NaN}
    Assert-Denied {Get-RunbookCredential} RUNBOOK_VAULT_CREDENTIAL_UNAVAILABLE
    & $provider {$script:Case.Ttl=[double]::PositiveInfinity}
    Assert-Denied {Get-RunbookCredential} RUNBOOK_VAULT_CREDENTIAL_UNAVAILABLE
    & $provider {$script:Case.AgeSeconds=86401}
    Assert-Denied {Test-RunbookVault} RUNBOOK_VAULT_ROTATION_OVERDUE
    foreach($margin in @(0,299,86400,2100.5,$true)) {
        $config.MinimumRemainingLifetimeSeconds=$margin
        $config | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $fixture
        Assert-Denied {Initialize-RunbookVault $fixture} RUNBOOK_VAULT_CONFIG_INVALID
    }
    $config.PSObject.Properties.Remove('MinimumRemainingLifetimeSeconds')
    $config | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $fixture
    Initialize-RunbookVault $fixture
    Assert-Result ((& $provider {$script:Vault.Config.MinimumRemainingLifetimeSeconds}) -eq 2100) 'Older configuration inherits safe margin'
    [pscustomobject]@{Checks=$checks;Failed=0;LiveServicesContacted=$false;PasswordsPrinted=$false}
} finally {Close-RunbookVault;Remove-Module OpenBao -ErrorAction SilentlyContinue;[IO.File]::Delete($fixture)}
