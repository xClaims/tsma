#Requires -Version 5.1
# SPDX-License-Identifier: Apache-2.0
<#
.SYNOPSIS
Enable persistent directory writes or disable new admissions for maintenance.
.DESCRIPTION
Run elevated on WORKER01. Atomically updates the protected policy and removes retired
window fields. Already admitted jobs may finish; this is not job cancellation.
#>
[CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')]
param([Parameter(Mandatory)][bool]$Enabled,
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._/ -]{0,63}$')][string]$ChangeReference)
function ConvertTo-DirectoryWriteState {
    # Pure policy transformation, also exercised by offline tests.
    param([Parameter(Mandatory)]$Policy,[bool]$Enabled,[string]$ChangeReference,[string]$IdentitySid)
    if($Enabled -and [DateTimeOffset]::Parse($Policy.ReviewExpiresUtc) -le [DateTimeOffset]::UtcNow){throw 'Scope review expired. Review and renew it deliberately before enabling writes.'}
    $Policy.WritesEnabled=$Enabled
    $Policy.PSObject.Properties.Remove('ExclusiveMaintenanceWindow')
    $Policy.PSObject.Properties.Remove('MaintenanceWindowEndsUtc')
    $Policy | Add-Member NoteProperty WriteStateChangedUtc ([DateTimeOffset]::UtcNow.ToString('o')) -Force
    $Policy | Add-Member NoteProperty WriteStateChangeReference $ChangeReference -Force
    $Policy | Add-Member NoteProperty WriteStateChangedBySid $IdentitySid -Force
    $Policy
}
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
if(-not ([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Elevation required.'}
$path='C:\ProgramData\TSMA\Config\DirectoryGroupMembership.json'
$item=Get-Item -LiteralPath $path -ErrorAction Stop
if($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Unsafe policy file.'}
$acl=Get-Acl -LiteralPath $path
if(-not $acl.AreAccessRulesProtected){throw 'Policy ACL must be protected.'}
foreach($rule in $acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])) {
    if($rule.AccessControlType -eq 'Allow' -and $rule.IdentityReference.Value -notin @('S-1-5-18','S-1-5-32-544')){throw 'Unexpected policy ACL principal.'}
}
if(-not $PSCmdlet.ShouldProcess($path,('Set persistent WritesEnabled='+$Enabled))){return}
$lock=$null;$stage=$null
try {
    # Serialize policy editors separately from the runtime account lock.
    $lock=[IO.File]::Open($path+'.update.lock',[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    $policy=Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    $policy=ConvertTo-DirectoryWriteState -Policy $policy -Enabled $Enabled -ChangeReference $ChangeReference -IdentitySid $identity.User.Value
    $stage=$path+'.'+[guid]::NewGuid().ToString()+'.next'
    $backup=$path+'.'+[guid]::NewGuid().ToString()+'.previous'
    [IO.File]::WriteAllText($stage,($policy | ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
    Set-Acl -LiteralPath $stage -AclObject $acl
    [IO.File]::Replace($stage,$path,$backup)
    $stage=$null
    Set-Acl -LiteralPath $backup -AclObject $acl
    try {
        $message=@{WritesEnabled=$Enabled;ChangeReference=$ChangeReference;ChangedUtc=$policy.WriteStateChangedUtc;ChangedBySid=$identity.User.Value}|ConvertTo-Json -Compress
        [Diagnostics.EventLog]::WriteEntry('TSMA',$message,[Diagnostics.EventLogEntryType]::Information,4110)
    } catch {Write-Warning 'Write state was changed, but its Application Log event could not be recorded. Retain the policy change record and backup.'}
    [pscustomobject]@{WritesEnabled=$Enabled;ChangedUtc=$policy.WriteStateChangedUtc;ChangeReference=$ChangeReference;BackupPath=$backup;AlreadyAdmittedJobsMayFinish=$true;ReviewExpiresUtc=$policy.ReviewExpiresUtc}
} finally {if($null -ne $lock){$lock.Dispose()}}
