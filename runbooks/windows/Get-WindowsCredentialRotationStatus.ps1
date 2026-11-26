#Requires -Version 7.4
# SPDX-License-Identifier: Apache-2.0
<#
.SYNOPSIS
Report rotation metadata and admission state without retrieving an AD password.
#>
[CmdletBinding()]param()
$ErrorActionPreference='Stop'
if(-not $IsWindows -or [Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne 'S-1-5-18'){throw 'SYSTEM Windows Hybrid Worker required.'}
Import-Module 'C:\ProgramData\TSMA\src\contracts\RunbookVault.psm1' -Force -ErrorAction Stop
try {
    Initialize-RunbookVault -ConfigurationPath 'C:\ProgramData\TSMA\Config\Vault-OperationDirectory.json'
    $health=Test-RunbookVault -Reference OperationDirectory
    [pscustomobject]@{
        Computer=[Environment]::MachineName
        Reference=$health.Reference
        Healthy=$health.Healthy
        LastRotationUtc=$health.LastRotationUtc
        NextRotationUtc=$health.NextRotationUtc
        PasswordAgeLimitSeconds=$health.PasswordAgeLimitSeconds
        MinimumRemainingLifetimeSeconds=$health.MinimumRemainingLifetimeSeconds
        RemainingLifetimeSeconds=$health.RemainingLifetimeSeconds
        AdmissionAllowed=$health.AdmissionAllowed
        CredentialRetrieved=$false
        ADAuthenticationTested=$false
        RotationRequested=$false
        Utc=[DateTimeOffset]::UtcNow.ToString('o')
    }
} catch {throw 'CREDENTIAL_ROTATION_MONITOR_FAILED: inspect vault availability, rotation metadata and worker clock using protected diagnostics.'}
finally {Close-RunbookVault}
