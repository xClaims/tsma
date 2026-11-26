#Requires -Version 7.4
# SPDX-License-Identifier: Apache-2.0
<#
.SYNOPSIS
Preview or add one eligible user to the requested existing AD group.
#>
[CmdletBinding()]
param([Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._$ -]{0,127}$')][string]$UserName,
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._$ -]{0,127}$')][string]$GroupName,
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._/ -]{0,63}$')][string]$ChangeReference,
    [bool]$Preview=$true)
$ErrorActionPreference='Stop'
if(-not $IsWindows -or [Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne 'S-1-5-18'){throw 'DIRECTORY_SYSTEM_WORKER_REQUIRED'}
Import-Module 'C:\ProgramData\TSMA\src\contracts\RunbookVault.psm1' -Force -ErrorAction Stop
Import-Module 'C:\ProgramData\TSMA\src\operations\DirectoryOperations\DirectoryOperations.psm1' -Force -ErrorAction Stop
Import-Module ActiveDirectory -ErrorAction Stop
$credential=$null
$metadata=Get-Variable PSPrivateMetadata -ValueOnly -ErrorAction SilentlyContinue
$jobContext=Get-DirectoryJobContext -Metadata $metadata -EnvironmentMetadata ([Environment]::GetEnvironmentVariable('PSPrivateMetadata','Process'))
if($jobContext.JobCorrelationStatus -ne 'Captured'){
    Write-Warning ('DIRECTORY_JOB_ID_'+$jobContext.JobCorrelationStatus.ToUpperInvariant()+': platform job metadata could not be normalized. Use RunId and Azure job output for correlation; no job ID was guessed.')
}
$metadata=$null
$stage='Policy'
try {
    $policyPath='C:\ProgramData\TSMA\Config\DirectoryGroupMembership.json'
    $file=Get-Item -LiteralPath $policyPath -ErrorAction Stop
    if($file.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'DIRECTORY_POLICY_FILE_UNSAFE'}
    $acl=Get-Acl -LiteralPath $policyPath
    if(-not $acl.AreAccessRulesProtected){throw 'DIRECTORY_POLICY_FILE_UNSAFE'}
    foreach($rule in $acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])) {
        if($rule.AccessControlType -eq 'Allow' -and $rule.IdentityReference.Value -notin @('S-1-5-18','S-1-5-32-544')){throw 'DIRECTORY_POLICY_FILE_UNSAFE'}
    }
    $policy=Get-Content -LiteralPath $policyPath -Raw | ConvertFrom-Json
    $stage='Vault'
    Initialize-RunbookVault 'C:\ProgramData\TSMA\Config\Vault-OperationDirectory.json'
    $health=Test-RunbookVault -Reference OperationDirectory
    if($health.PasswordAgeLimitSeconds -ne $policy.MaximumPasswordAgeSeconds){throw 'DIRECTORY_POLICY_INVALID'}
    $credential=Get-RunbookCredential -Reference OperationDirectory
    $stage='Operation'
    Invoke-DirectoryGroupMember -UserName $UserName -GroupName $GroupName -ChangeReference $ChangeReference -Preview $Preview -Credential $credential -Policy $policy -LastRotationUtc ([DateTimeOffset]::Parse($health.LastRotationUtc)) -AzureJobId $jobContext.AzureJobId -AzureJobIdSource $jobContext.AzureJobIdSource -JobCorrelationStatus $jobContext.JobCorrelationStatus
} catch {
    # Only allowlisted explanatory text is emitted; raw SDK/provider messages stay private.
    $exception=$_.Exception
    $runId=$null;$outcome='RejectedBeforeWrite'
    if($exception.Data.Contains('DirectoryReasonCode')) {
        $detail=Get-DirectoryFailureDetail -Code ([string]$exception.Data['DirectoryReasonCode'])
        $parsed=[guid]::Empty
        if([guid]::TryParse([string]$exception.Data['DirectoryRunId'],[ref]$parsed)){$runId=$parsed.ToString('D')}
        $outcome=if($exception.Data['DirectoryOutcome'] -eq 'RecoveryRequired'){'RecoveryRequired'}else{'RejectedBeforeWrite'}
    } elseif($exception.Message -match '^DIRECTORY_[A-Z_]+$') {
        $detail=Get-DirectoryFailureDetail -Code $exception.Message
    } elseif($stage -eq 'Vault') {
        $detail=Get-DirectoryFailureDetail -Code DIRECTORY_VAULT_UNAVAILABLE
    } elseif($stage -eq 'Policy') {
        $detail=Get-DirectoryFailureDetail -Code DIRECTORY_POLICY_FILE_INVALID
    } else {
        $detail=Get-DirectoryFailureDetail -Code DIRECTORY_PROVIDER_OR_EVIDENCE_FAILURE
        $outcome='RecoveryRequired'
    }
    [pscustomobject]@{Outcome=$outcome;ReasonCode=$detail.ReasonCode;Reason=$detail.Reason;RecommendedAction=$detail.RecommendedAction;RunId=$runId;AzureJobId=$jobContext.AzureJobId;AzureJobIdSource=$jobContext.AzureJobIdSource;JobCorrelationStatus=$jobContext.JobCorrelationStatus;Utc=[DateTimeOffset]::UtcNow.ToString('o')}
    $reference=if($runId){' RunId='+$runId}else{''}
    throw ('DIRECTORY_OPERATION_'+$outcome.ToUpperInvariant()+' ReasonCode='+$detail.ReasonCode+': '+$detail.Reason+$reference)
} finally {
    if($null -ne $credential){$credential.Password.Dispose();$credential=$null}
    Close-RunbookVault
}
