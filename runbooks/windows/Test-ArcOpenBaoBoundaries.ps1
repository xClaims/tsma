#Requires -Version 7.4
# SPDX-License-Identifier: Apache-2.0
<#
.SYNOPSIS
Verify isolated JWT rejection roles and reject a signature-modified token.
.DESCRIPTION
Requires administrator-created arc-deny-* roles from CONFIGURE-ARC-OPENBAO.md.
Uses the fixed live Arc configuration. Does not change vault configuration.
#>
[CmdletBinding()]param()
$ErrorActionPreference='Stop'
$module=Import-Module 'C:\ProgramData\TSMA\src\vaults\openbao\OpenBao.psm1' -Force -PassThru
$jwt=$null;$altered=$null
try {
    Initialize-RunbookVault 'C:\ProgramData\TSMA\Config\Vault-OperationDirectory.json'
    # Prove the production role accepts this genuine token source first.
    & $module {Connect-WorkerVault}
    $jwt=& $module {Get-ArcIdentityToken}
    $parts=$jwt.Split('.')
    if($parts.Count -ne 3 -or $parts[2].Length -lt 2){throw 'ARC_JWT_FORMAT_UNEXPECTED'}
    $first=if($parts[2][0] -eq 'A'){'B'}else{'A'}
    $altered=$parts[0]+'.'+$parts[1]+'.'+$first+$parts[2].Substring(1)
    $checks=[Collections.Generic.List[object]]::new()
    foreach($case in @('audience','tenant','identity','issuer','signature')) {
        $role=if($case -eq 'signature'){'operation-directory-worker01'}else{'arc-deny-'+$case}
        $token=if($case -eq 'signature'){$altered}else{$jwt}
        $passed=$false;$observed='UnexpectedSuccess'
        try {
            $null=& $module {
                param($Role,$Jwt)
                Invoke-VaultRequest -Endpoint 'auth/jwt-arc/login' -Method Post -Anonymous -Payload @{role=$Role;jwt=$Jwt}
            } $role $token
        } catch {
            if($_.Exception.Message -match '^RUNBOOK_VAULT_REQUEST_FAILED_(400|403)$'){$passed=$true;$observed='HTTP'+$Matches[1]}
            else {$observed='RequestUnavailable'}
        }
        $checks.Add([pscustomobject]@{Check=$case;Passed=$passed;Observed=$observed})
    }
    $checks.ToArray()
    $failed=@($checks | Where-Object {-not $_.Passed}).Count
    [pscustomobject]@{AllPassed=($failed -eq 0);CheckCount=5;FailedCount=$failed;VaultConfigurationChangesRequested=$false;Utc=[DateTimeOffset]::UtcNow.ToString('o')}
    if($failed){throw 'ARC_JWT_REJECTION_CHECK_FAILED'}
} finally {$jwt=$null;$altered=$null;$token=$null;$parts=$null;Close-RunbookVault}
