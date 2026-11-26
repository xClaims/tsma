#Requires -Version 5.1
# SPDX-License-Identifier: Apache-2.0
<#
.SYNOPSIS
Prepare the protected policy, evidence directory and Application event source.
.DESCRIPTION
Run elevated on WORKER01. Reads OU identities; makes no AD changes or permissions grants.
Writes start disabled; explicitly enable them after preview and boundary validation.
#>
[CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')]
param([Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._/ -]{0,63}$')][string]$ScopeReviewReference,
    [ValidateRange(1,30)][int]$ReviewDays=7,
    [guid[]]$AdditionalProtectedObjectGuids=@(),
    [bool]$WritesEnabled=$false,
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9.-]+\.[A-Za-z0-9-]+$')][string]$DomainController,
    [Parameter(Mandatory)][string]$Tier0DistinguishedName,
    [Parameter(Mandatory)][string]$ExecutionAccount,
    [ValidateRange(600,604800)][int]$MaximumPasswordAgeSeconds=86400,
    [ValidateRange(300,86400)][int]$MinimumRemainingLifetimeSeconds=2100)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($MinimumRemainingLifetimeSeconds -ge $MaximumPasswordAgeSeconds){throw 'Rotation admission margin must be shorter than the interval.'}
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
if(-not ([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Elevation required.'}
Import-Module ActiveDirectory -ErrorAction Stop
$domain=Get-ADDomain -Server $DomainController -ErrorAction Stop
if(-not $Tier0DistinguishedName.EndsWith(','+$domain.DistinguishedName,[StringComparison]::OrdinalIgnoreCase)){throw 'Tier 0 OU must be inside the selected domain.'}
$roots=foreach($dn in @($Tier0DistinguishedName,('OU=Domain Controllers,'+$domain.DistinguishedName))) {
    (Get-ADOrganizationalUnit -Identity $dn -Server $DomainController -ErrorAction Stop).ObjectGUID.ToString()
}
$account=Get-ADUser -Identity $ExecutionAccount -Server $DomainController -ErrorAction Stop
$directory='C:\ProgramData\TSMA\Evidence\GroupMembership'
$configPath='C:\ProgramData\TSMA\Config\DirectoryGroupMembership.json'
if(Test-Path -LiteralPath $configPath){throw 'Policy exists. Review and update the protected policy deliberately; this script does not overwrite it.'}
if(-not (Test-Path -LiteralPath (Split-Path $configPath -Parent))){throw 'Install the protected Config directory first.'}
# Validate the installed trust boundary before writing configuration.
foreach($protectedPath in @('C:\ProgramData\TSMA','C:\ProgramData\TSMA\Config')) {
    $protectedItem=Get-Item -LiteralPath $protectedPath -Force -ErrorAction Stop
    for($cursor=$protectedItem;$null -ne $cursor;$cursor=$cursor.Parent){if($cursor.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Linked runtime path rejected.'}}
    $protectedAcl=Get-Acl -LiteralPath $protectedPath -ErrorAction Stop
    if($protectedAcl.GetOwner([Security.Principal.SecurityIdentifier]).Value -notin @('S-1-5-18','S-1-5-32-544') -or -not $protectedAcl.AreAccessRulesProtected){throw 'Runtime owner/ACL is untrusted. Complete protected installation or controlled recovery first.'}
    foreach($rule in $protectedAcl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])){if($rule.AccessControlType -eq 'Allow' -and $rule.IdentityReference.Value -notin @('S-1-5-18','S-1-5-32-544')){throw 'Untrusted runtime access.'}}
}
if(-not $PSCmdlet.ShouldProcess($configPath,'Create protected group-membership policy, evidence directory and event source')){return}
$null=New-Item -ItemType Directory -Path $directory -Force
$directoryAcl=[Security.AccessControl.DirectorySecurity]::new()
$directoryAcl.SetAccessRuleProtection($true,$false)
$directoryAcl.SetOwner([Security.Principal.SecurityIdentifier]::new('S-1-5-32-544'))
$fileAcl=[Security.AccessControl.FileSecurity]::new()
$fileAcl.SetAccessRuleProtection($true,$false)
    $fileAcl.SetOwner([Security.Principal.SecurityIdentifier]::new('S-1-5-32-544'))
foreach($sid in @('S-1-5-18','S-1-5-32-544')) {
    $principal=[Security.Principal.SecurityIdentifier]::new($sid)
    $directoryAcl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($principal,'FullControl','ContainerInherit,ObjectInherit','None','Allow'))
    $fileAcl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($principal,'FullControl','Allow'))
}
Set-Acl -LiteralPath $directory -AclObject $directoryAcl
if(-not [Diagnostics.EventLog]::SourceExists('TSMA')) {
    [Diagnostics.EventLog]::CreateEventSource('TSMA','Application')
} elseif([Diagnostics.EventLog]::LogNameFromSourceName('TSMA','.') -ne 'Application'){throw 'Event source exists in a different log.'}
$policy=[ordered]@{
    ExecutionIdentity=($domain.NetBIOSName+'\'+$account.SamAccountName);DomainDistinguishedName=$domain.DistinguishedName;Tier0DistinguishedName=$Tier0DistinguishedName;MaximumPasswordAgeSeconds=$MaximumPasswordAgeSeconds;MinimumRemainingLifetimeSeconds=$MinimumRemainingLifetimeSeconds
    DomainController=$DomainController;DomainSid=$domain.DomainSID.ToString();ExcludedOuGuids=@($roots)
    ProtectedObjectGuids=@($account.ObjectGUID.ToString())+@($AdditionalProtectedObjectGuids | ForEach-Object {$_.ToString()})
    ScopeReviewReference=$ScopeReviewReference;ReviewExpiresUtc=[DateTimeOffset]::UtcNow.AddDays($ReviewDays).ToString('o')
    WritesEnabled=$WritesEnabled
    EvidenceDirectory=$directory
}
$encoding=[Text.UTF8Encoding]::new($false)
[IO.File]::WriteAllText($configPath,($policy | ConvertTo-Json -Depth 6),$encoding)
Set-Acl -LiteralPath $configPath -AclObject $fileAcl
[pscustomobject]@{PolicyPath=$configPath;WritesEnabled=$WritesEnabled;EvidenceDirectory=$directory;EventSource='TSMA'}
