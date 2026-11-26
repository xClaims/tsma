#Requires -Version 7.4
# SPDX-License-Identifier: Apache-2.0
[CmdletBinding()]param()
$ErrorActionPreference='Stop'
if(-not $IsWindows){throw 'Windows worker required'}
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
if($identity.User.Value -ne 'S-1-5-18'){throw 'Run this probe on the SYSTEM Hybrid Worker.'}
$vaultModule=Import-Module 'C:\ProgramData\TSMA\src\vaults\openbao\OpenBao.psm1' -Force -PassThru -ErrorAction Stop
Import-Module 'C:\ProgramData\TSMA\src\vaults\openbao\VaultAuthorization.psm1' -Force -ErrorAction Stop
$credential=$null
try {
    $configPath='C:\ProgramData\TSMA\Config\Vault-OperationDirectory.json'
    Initialize-RunbookVault -ConfigurationPath $configPath
    $authentication=& $vaultModule {$script:Vault.Authentication}
    $null=Test-RunbookVault -Reference OperationDirectory
    $credential=Get-RunbookCredential -Reference OperationDirectory
    $config=Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
    if($credential.UserName -cne $config.Accounts.OperationDirectory.CredentialUserName){throw 'Unexpected mapped identity'}
    $credential.Password.Dispose();$credential=$null

    # Keep the worker token inside the existing module. No token input
    # parameters, credential output, or target-management POSTs are exposed.
    $request={
        param($Endpoint,$Method,$Payload)
        & $vaultModule {
            param($Endpoint,$Method,$Payload)
            Invoke-VaultRequest -Endpoint $Endpoint -Method $Method -Payload $Payload
        } $Endpoint $Method $Payload
    }.GetNewClosure()
    $result=Test-OperationDirectoryVaultAuthorization -Request $request
    $result.Checks
    [pscustomobject]@{
        Computer=[Environment]::MachineName;IdentitySid=$identity.User.Value
        VaultAuthentication=$authentication
        CredentialReference='OperationDirectory';CredentialReadControlPassed=$true
        CheckCount=$result.CheckCount;FailedCount=$result.FailedCount
        AllPassed=$result.AllPassed;DirectoryChangesRequested=$false
        RotationRequested=$false;VaultConfigurationChangesRequested=$false
        Utc=[DateTimeOffset]::UtcNow.ToString('o')
    }
    if(-not $result.AllPassed){throw 'OPERATION_DIRECTORY_AUTHORIZATION_CHECKS_FAILED'}
} finally {
    if($null -ne $credential){$credential.Password.Dispose();$credential=$null}
    Close-RunbookVault
}
