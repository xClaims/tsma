#Requires -Version 7.4
# SPDX-License-Identifier: Apache-2.0
<#
.SYNOPSIS
Verify SYSTEM vault retrieval and an explicit service-account ADWS read.
.DESCRIPTION
Reads svc-op-directory's own AD object only. No AD writes or rotation requests.
Does not test LDAPS directly or establish effective Helpdesk modification rights.
#>
[CmdletBinding()]param()
$ErrorActionPreference='Stop'
if(-not $IsWindows){throw 'Windows worker required'}
$hostIdentity=[Security.Principal.WindowsIdentity]::GetCurrent()
if($hostIdentity.User.Value -ne 'S-1-5-18'){throw 'Run this probe on the SYSTEM Hybrid Worker.'}
Import-Module 'C:\ProgramData\TSMA\src\contracts\RunbookVault.psm1' -Force -ErrorAction Stop
Import-Module ActiveDirectory -ErrorAction Stop
$credential=$null
$stage='Vault'
try {
    $configPath='C:\ProgramData\TSMA\Config\Vault-OperationDirectory.json'
    Initialize-RunbookVault -ConfigurationPath $configPath
    $config=Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
    $authentication=$config.Authentication
    $health=Test-RunbookVault -Reference OperationDirectory
    $credential=Get-RunbookCredential -Reference OperationDirectory
    $policy=Get-Content -LiteralPath 'C:\ProgramData\TSMA\Config\DirectoryGroupMembership.json' -Raw | ConvertFrom-Json
    if($credential.UserName -cne $policy.ExecutionIdentity){throw 'Unexpected identity'}
    $stage='ADRead'
    $target=$config.Accounts.OperationDirectory.DistinguishedName
    $account=Get-ADUser -Identity $target -Server $policy.DomainController -Credential $credential -ErrorAction Stop
    if($account.DistinguishedName -ine $target -or $account.SamAccountName -cne $config.Accounts.OperationDirectory.UserName){throw 'Unexpected AD object'}
    [pscustomobject]@{
        Computer=[Environment]::MachineName
        HostIdentity=$hostIdentity.Name
        IdentitySid=$hostIdentity.User.Value
        ADExecutionIdentity=$credential.UserName
        CredentialReference='OperationDirectory'
        VaultAuthentication=$authentication
        VaultHealthy=$health.Healthy
        LastRotationUtc=$health.LastRotationUtc
        ADObjectRead=$true
        ADTransport='Active Directory Web Services; explicit credentials'
        LDAPSAuthenticationTested=$false
        DirectoryChangesRequested=$false
        RotationRequested=$false
        Utc=[DateTimeOffset]::UtcNow.ToString('o')
    }
} catch {
    # Avoid raw SDK/provider errors or credential-bearing diagnostic objects.
    throw ('OPERATION_DIRECTORY_'+$stage.ToUpperInvariant()+'_FAILED')
} finally {
    if($null -ne $credential){$credential.Password.Dispose();$credential=$null}
    Close-RunbookVault
}
