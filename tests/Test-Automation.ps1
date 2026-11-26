#Requires -Version 7.4
# SPDX-License-Identifier: Apache-2.0
[CmdletBinding()]param()
$ErrorActionPreference='Stop'
$base=Split-Path $PSScriptRoot -Parent
$failures=[Collections.Generic.List[string]]::new()
$count=0
function Assert-Check {param([bool]$Ok,[string]$Name) $script:count++;if(-not $Ok){$script:failures.Add($Name)}}
function Assert-Denied {param([scriptblock]$Action,[string]$Expected) try {& $Action | Out-Null;Assert-Check $false $Expected} catch {Assert-Check ($_.Exception.Message -eq $Expected) $Expected}}
foreach($file in Get-ChildItem $base -Recurse -File | Where-Object Extension -in @('.ps1','.psm1')) {
    $parseErrors=$null;$tokens=$null
    $null=[Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$parseErrors)
    Assert-Check ($parseErrors.Count -eq 0) ('Parse '+$file.Name)
}
foreach($file in Get-ChildItem $base -Recurse -Filter '*.json'){$null=Get-Content $file.FullName -Raw | ConvertFrom-Json;Assert-Check $true ('JSON '+$file.Name)}
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('automation-'+[guid]::NewGuid()+'.json')
try {
    $c=Get-Content (Join-Path $base 'examples/OperationDirectory.example.json') -Raw | ConvertFrom-Json
    $c.ManagedIdentityResource='api://11111111-1111-1111-1111-111111111111'
    $c | ConvertTo-Json -Depth 8 | Set-Content $fixture
    $module=Import-Module (Join-Path $base 'src/vaults/openbao/OpenBao.psm1') -Force -PassThru
    Initialize-RunbookVault $fixture
    & $module {
        $script:FixtureState=@{Last=[DateTimeOffset]::UtcNow.AddMinutes(-1);User='svc-op-directory';Period=86400;Fail=$false;Root=$false}
        function script:Get-ArcIdentityToken {'TEST-IDENTITY-TOKEN'}
        function script:Invoke-RestMethod {
            param($Uri,$Method,$Headers,$TimeoutSec,$MaximumRedirection,$Body,$ContentType,$ErrorAction,$Verbose,$Debug)
            if($TimeoutSec -ne 15 -or $ErrorAction -ne 'Stop' -or $Verbose -or $Debug){throw 'Invalid request controls'}
            if($MaximumRedirection -ne 0 -or $Uri -notlike 'https://bao.example.com:8200/v1/*'){throw 'Unexpected request'}
            if($script:FixtureState.Fail){throw 'TEST-SENSITIVE-ERROR'}
            if($Uri -like '*/auth/jwt-arc/login') {
                $b=[Text.Encoding]::UTF8.GetString($Body)|ConvertFrom-Json
                if($Method -ne 'Post' -or $ContentType -ne 'application/json'){throw 'Invalid login transport'}
                if($b.role -ne 'operation-directory-worker01' -or $b.jwt -ne 'TEST-IDENTITY-TOKEN'){throw 'Invalid auth'}
                return @{auth=@{client_token='TEST-TOKEN';lease_duration=300;policies=@($(if($script:FixtureState.Root){'root'}else{'validation'}))}}
            }
            if($Headers['X-Vault-Token'] -ne 'TEST-TOKEN'){throw 'No auth'}
            if($Uri -like '*/static-role/operation-directory'){return @{data=@{username=$script:FixtureState.User;dn='CN=svc-op-directory,OU=Service Accounts,OU=Tier 0,OU=Admin,DC=ad,DC=example,DC=com';rotation_period=$script:FixtureState.Period;last_vault_rotation=$script:FixtureState.Last.ToString('o')}}}
            if($Uri -like '*/static-cred/operation-directory'){return @{data=@{username=$script:FixtureState.User;ttl=86340;password='TEST-PASSWORD';last_vault_rotation=$script:FixtureState.Last.ToString('o')}}}
            throw 'Unexpected endpoint'
        }
    }
    Assert-Check (Test-RunbookVault).Healthy 'Healthy metadata'
    $cred=Get-RunbookCredential
    Assert-Check ($cred -is [pscredential] -and $cred.UserName -eq 'EXAMPLE\svc-op-directory') 'Credential mapping'
    $cred=$null
    Assert-Denied {Get-RunbookCredential -Reference '../Schema'} 'RUNBOOK_VAULT_REFERENCE_DENIED'
    & $module {$script:FixtureState.Last=[DateTimeOffset]::UtcNow.AddHours(-24)}
    Assert-Denied {Get-RunbookCredential} 'RUNBOOK_VAULT_ROTATION_OVERDUE'
    & $module {$script:FixtureState.Last=[DateTimeOffset]::UtcNow.AddMinutes(5)}
    Assert-Denied {Test-RunbookVault} 'RUNBOOK_VAULT_CLOCK_AHEAD'
    & $module {$script:FixtureState.Last=[DateTimeOffset]::UtcNow.AddMilliseconds(200)}
    Assert-Check (Test-RunbookVault).Healthy 'Small skew waited out'
    & $module {$script:FixtureState.User='wrong'}
    Assert-Denied {Test-RunbookVault} 'RUNBOOK_VAULT_METADATA_INVALID'
    & $module {$script:FixtureState.User='svc-op-directory';$script:FixtureState.Period=14400}
    Assert-Denied {Test-RunbookVault} 'RUNBOOK_VAULT_METADATA_INVALID'
    & $module {$script:FixtureState.Period=86400;$script:FixtureState.Fail=$true}
    Assert-Denied {Test-RunbookVault} 'RUNBOOK_VAULT_REQUEST_FAILED_transport'
    & $module {$script:FixtureState.Fail=$false;$script:FixtureState.Root=$true;$script:Vault.Token=$null}
    Assert-Denied {Test-RunbookVault} 'RUNBOOK_VAULT_REQUEST_FAILED_transport'
    Close-RunbookVault
    Assert-Denied {Get-RunbookCredential} 'RUNBOOK_VAULT_UNINITIALIZED'
    $c.Address='http://bao.example.com:8200';$c|ConvertTo-Json -Depth 8|Set-Content $fixture
    Assert-Denied {Initialize-RunbookVault $fixture} 'RUNBOOK_VAULT_CONFIG_INVALID'
} finally {Remove-Module OpenBao -ErrorAction SilentlyContinue;[IO.File]::Delete($fixture)}
[pscustomobject]@{Checks=$count;Failed=$failures.Count;Failures=@($failures)}
if($failures.Count){throw 'AUTOMATION_TESTS_FAILED'}
