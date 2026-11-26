#Requires -Version 7.4
# SPDX-License-Identifier: Apache-2.0
[CmdletBinding()]param()
$ErrorActionPreference='Stop'
if(-not $IsWindows){throw 'Windows worker required'}
Import-Module 'C:\ProgramData\TSMA\src\contracts\RunbookVault.psm1' -Force -ErrorAction Stop
Import-Module 'C:\ProgramData\TSMA\src\operations\LdapValidation\LdapValidation.psm1' -Force -ErrorAction Stop
$credential=$null
try {
    Initialize-RunbookVault -ConfigurationPath 'C:\ProgramData\TSMA\Config\Vault-OperationDirectory.json'
    $health=Test-RunbookVault -Reference OperationDirectory
    $credential=Get-RunbookCredential -Reference OperationDirectory
    $config=Get-Content -LiteralPath 'C:\ProgramData\TSMA\Config\Vault-OperationDirectory.json' -Raw | ConvertFrom-Json
    $policy=Get-Content -LiteralPath 'C:\ProgramData\TSMA\Config\DirectoryGroupMembership.json' -Raw | ConvertFrom-Json
    $mapping=$config.Accounts.OperationDirectory
    $result=Invoke-ValidationLdapRead -Credential $credential -DomainController $policy.DomainController -DistinguishedName $mapping.DistinguishedName -UserName $mapping.UserName -ExecutionIdentity $policy.ExecutionIdentity
    [pscustomobject]@{Computer=[Environment]::MachineName;IdentitySid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;CredentialRetrieved=$true;LastRotationUtc=$health.LastRotationUtc;DomainController=$result.DomainController;Port=$result.Port;TlsRequired=$result.TlsRequired;ADAuthenticationTested=$result.ADAuthenticationTested;ADAuthenticated=$result.ADAuthenticated;ObjectRead=$result.ObjectRead;DirectoryChangesRequested=$false;RotationRequested=$false;Utc=[DateTimeOffset]::UtcNow.ToString('o')}
} finally {if($null -ne $credential){$credential.Password.Dispose()};$credential=$null;Close-RunbookVault}
