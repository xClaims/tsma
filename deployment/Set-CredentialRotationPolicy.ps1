#Requires -Version 7.4
#Requires -RunAsAdministrator
# SPDX-License-Identifier: Apache-2.0
<#
.SYNOPSIS
Update protected rotation/admission settings during drained maintenance.
.DESCRIPTION
Does not change the vault role. Pause and drain all consumers first, then update
the OpenBao role separately. Both local files are backed up and atomically
replaced individually. A partial update fails closed on configuration mismatch.
#>
[CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')]
param([ValidateRange(600,604800)][int]$MaximumPasswordAgeSeconds=86400,
    [ValidateRange(300,86400)][int]$MinimumRemainingLifetimeSeconds=2100,
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._/ -]{0,63}$')][string]$ChangeReference,
    [Parameter(Mandatory)][switch]$MaintenanceAcknowledged)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if(-not $IsWindows -or -not $MaintenanceAcknowledged){throw 'Drained Windows maintenance required.'}
if($MinimumRemainingLifetimeSeconds -ge $MaximumPasswordAgeSeconds){throw 'Admission margin must be shorter than the interval.'}
$root='C:\ProgramData\TSMA'
$paths=@((Join-Path $root 'Config\Vault-OperationDirectory.json'),(Join-Path $root 'Config\DirectoryGroupMembership.json'))
$items=@()
foreach($path in $paths) {
    $item=Get-Item -LiteralPath $path -Force -ErrorAction Stop
    for($cursor=$item;$null -ne $cursor;$cursor=if($cursor -is [IO.FileInfo]){$cursor.Directory}else{$cursor.Parent}) {
        if($cursor.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Linked runtime path rejected.'}
        if($cursor.FullName -eq $root -or $cursor.FullName.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)){
            $acl=Get-Acl -LiteralPath $cursor.FullName -ErrorAction Stop
            if(-not $acl.AreAccessRulesProtected -or $acl.GetOwner([Security.Principal.SecurityIdentifier]).Value -notin @('S-1-5-18','S-1-5-32-544')){throw 'Untrusted runtime owner/ACL.'}
            foreach($rule in $acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])){if($rule.AccessControlType -eq 'Allow' -and $rule.IdentityReference.Value -notin @('S-1-5-18','S-1-5-32-544')){throw 'Untrusted runtime access.'}}
        }
    }
    $config=Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    $config.MaximumPasswordAgeSeconds=$MaximumPasswordAgeSeconds
    $config | Add-Member NoteProperty MinimumRemainingLifetimeSeconds $MinimumRemainingLifetimeSeconds -Force
    $items+=@{Path=$path;Configuration=$config;Acl=(Get-Acl -LiteralPath $path);Hash=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash}
}
if($items[1].Configuration.WritesEnabled -isnot [bool] -or $items[1].Configuration.WritesEnabled){throw 'Disable writes and drain consumers before changing rotation policy.'}
if($items[0].Configuration.Provider -cne 'OpenBao' -or $items[0].Configuration.Accounts.OperationDirectory.CredentialUserName -cne $items[1].Configuration.ExecutionIdentity){throw 'Configuration mapping mismatch.'}
if(-not $PSCmdlet.ShouldProcess($root,'Update rotation policy; preserve protected backups; change reference '+$ChangeReference)){return}
$backups=@()
foreach($entry in $items) {
    $next=$entry.Path+'.'+[guid]::NewGuid().ToString('N')+'.next'
    $backup=$entry.Path+'.'+[guid]::NewGuid().ToString('N')+'.previous'
    try {
        $entry.Configuration | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $next -Encoding utf8 -ErrorAction Stop
        Set-Acl -LiteralPath $next -AclObject $entry.Acl -ErrorAction Stop
        if((Get-FileHash -LiteralPath $entry.Path -Algorithm SHA256).Hash -ne $entry.Hash){throw 'Configuration changed during maintenance.'}
        [IO.File]::Replace($next,$entry.Path,$backup)
        $backups+=$backup
    } finally {if(Test-Path -LiteralPath $next){[IO.File]::Delete($next)}}
}
[pscustomobject]@{MaximumPasswordAgeSeconds=$MaximumPasswordAgeSeconds;MinimumRemainingLifetimeSeconds=$MinimumRemainingLifetimeSeconds;WritesEnabled=$false;Backups=$backups;ChangeReference=$ChangeReference;VaultChanged=$false;Utc=[DateTimeOffset]::UtcNow.ToString('o')}
