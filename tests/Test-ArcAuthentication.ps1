#Requires -Version 7.4
# SPDX-License-Identifier: Apache-2.0
[CmdletBinding()]param()
$ErrorActionPreference='Stop'
$base=Split-Path $PSScriptRoot -Parent
$file=Join-Path ([IO.Path]::GetTempPath()) ('arc-auth-'+[guid]::NewGuid()+'.json')
$checks=0
function Assert-Result {param([bool]$Condition,[string]$Name) $script:checks++;if(-not $Condition){throw "Failed: $Name"}}
try {
    $c=Get-Content (Join-Path $base 'examples/OperationDirectory.example.json') -Raw | ConvertFrom-Json
    $c.ManagedIdentityResource='api://11111111-1111-1111-1111-111111111111'
    $c | ConvertTo-Json -Depth 8 | Set-Content $file
    $module=Import-Module (Join-Path $base 'src/vaults/openbao/OpenBao.psm1') -Force -PassThru
    Initialize-RunbookVault $file
    & $module {
        $script:ArcFixture=@{Acquired=0;Logins=0;Fail=$false;Root=$false;Lease=300}
        function script:Get-ArcIdentityToken {
            $script:ArcFixture.Acquired++
            if($script:ArcFixture.Fail){throw 'TOKEN_ERROR_MUST_NOT_ESCAPE'}
            'FAKE-ENTRA-JWT'
        }
        function script:Invoke-RestMethod {
            param($Uri,$Method,$Headers,$TimeoutSec,$MaximumRedirection,$Body,$ContentType,$ErrorAction,$Verbose,$Debug)
            if($Headers.Count -ne 0 -or $TimeoutSec -ne 15 -or $ContentType -ne 'application/json' -or $ErrorAction -ne 'Stop'){throw 'Invalid login controls'}
            if($Uri -ne 'https://bao.example.com:8200/v1/auth/jwt-arc/login' -or $Method -ne 'Post' -or $MaximumRedirection -ne 0 -or $Verbose -or $Debug){throw 'Invalid transport'}
            $b=[Text.Encoding]::UTF8.GetString($Body)|ConvertFrom-Json
            if($b.role -ne 'operation-directory-worker01' -or $b.jwt -ne 'FAKE-ENTRA-JWT'){throw 'Wrong login payload'}
            $script:ArcFixture.Logins++
            @{auth=@{client_token='FAKE-BAO';lease_duration=$script:ArcFixture.Lease;policies=@($(if($script:ArcFixture.Root){'root'}else{'operation-directory-worker'}))}}
        }
    }
    & $module {Connect-WorkerVault;Connect-WorkerVault}
    Assert-Result (& $module {$script:ArcFixture.Acquired -eq 1 -and $script:ArcFixture.Logins -eq 1}) 'Cached OpenBao token'
    & $module {$script:Vault.Expires=[DateTimeOffset]::MinValue;Connect-WorkerVault}
    Assert-Result (& $module {$script:ArcFixture.Acquired -eq 2}) 'Expired token reacquires managed identity'
    foreach($scenario in @('Fail','Root','Lease')) {
        Initialize-RunbookVault $file
        & $module {param($Scenario) $script:ArcFixture.Fail=$false;$script:ArcFixture.Root=$false;$script:ArcFixture.Lease=300;if($Scenario -eq 'Lease'){$script:ArcFixture.Lease=301}else{$script:ArcFixture[$Scenario]=$true}} $scenario
        $message=''
        try {& $module {Connect-WorkerVault}} catch {$message=$_.Exception.Message}
        Assert-Result ($message -eq 'RUNBOOK_VAULT_AUTH_FAILED') ('Fail closed: '+$scenario)
        Assert-Result (& $module {$null -eq $script:Vault.Token}) 'Failed authentication leaves no cached token'
    }
    foreach($bad in @('https://management.azure.com/','api://not-a-guid')) {
        $c.ManagedIdentityResource=$bad;$c|ConvertTo-Json -Depth 8|Set-Content $file
        $message='';try{Initialize-RunbookVault $file}catch{$message=$_.Exception.Message}
        Assert-Result ($message -eq 'RUNBOOK_VAULT_CONFIG_INVALID') 'Reject unintended token resource'
    }
    $c.ManagedIdentityResource='api://11111111-1111-1111-1111-111111111111';$c.Authentication='Unknown';$c|ConvertTo-Json -Depth 8|Set-Content $file
    $message='';try{Initialize-RunbookVault $file}catch{$message=$_.Exception.Message}
    Assert-Result ($message -eq 'RUNBOOK_VAULT_CONFIG_INVALID') 'Unknown auth never falls back'
    [pscustomobject]@{Checks=$checks;Failed=0;LiveArcTokenTested=$false}
} finally {Remove-Module OpenBao -ErrorAction SilentlyContinue;[IO.File]::Delete($file)}
