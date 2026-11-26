#Requires -Version 7.4
#Requires -RunAsAdministrator
# SPDX-License-Identifier: Apache-2.0
<#
.SYNOPSIS
Install TSMA code into its fixed protected Windows runtime directory.
.DESCRIPTION
Rejects unsafe existing ownership/access before writes. Creates directories with
protected security descriptors and explicitly normalizes trusted runtime ownership.
Does not change Azure/AD or overwrite configuration/evidence contents.
For updates, disable admissions and drain jobs before using MaintenanceAcknowledged.
#>
[CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')]
param([string]$SourceRoot=(Split-Path $PSScriptRoot -Parent),[switch]$MaintenanceAcknowledged)

function Get-TSMAProtectedSecurity {
    # Constructs an in-memory descriptor; does not modify the filesystem.
    [CmdletBinding()][OutputType([Security.AccessControl.ObjectSecurity])]
    param([switch]$Directory)
    $security=if($Directory){[Security.AccessControl.DirectorySecurity]::new()}else{[Security.AccessControl.FileSecurity]::new()}
    $security.SetAccessRuleProtection($true,$false)
    $security.SetOwner([Security.Principal.SecurityIdentifier]::new('S-1-5-32-544'))
    foreach($sid in @('S-1-5-18','S-1-5-32-544')) {
        $principal=[Security.Principal.SecurityIdentifier]::new($sid)
        $rule=if($Directory){[Security.AccessControl.FileSystemAccessRule]::new($principal,'FullControl','ContainerInherit,ObjectInherit','None','Allow')}else{[Security.AccessControl.FileSystemAccessRule]::new($principal,'FullControl','Allow')}
        $security.AddAccessRule($rule)
    }
    $security
}
function Assert-TSMAExistingRuntimeItem {
    [CmdletBinding()]param([Parameter(Mandatory)][string]$LiteralPath,[switch]$RequireProtectedAcl)
    $item=Get-Item -LiteralPath $LiteralPath -Force -ErrorAction Stop
    if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'TSMA_RUNTIME_LINK_REJECTED'}
    $security=Get-Acl -LiteralPath $LiteralPath -ErrorAction Stop
    $owner=$security.GetOwner([Security.Principal.SecurityIdentifier]).Value
    if($owner -notin @('S-1-5-18','S-1-5-32-544')){throw 'TSMA_RUNTIME_OWNER_UNTRUSTED: existing paths must be owned by SYSTEM or local Administrators; inspect under controlled recovery before retrying.'}
    if($RequireProtectedAcl -and -not $security.AreAccessRulesProtected){throw 'TSMA_RUNTIME_ACL_UNPROTECTED'}
    foreach($rule in $security.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])) {
        if($rule.AccessControlType -eq 'Allow' -and $rule.IdentityReference.Value -notin @('S-1-5-18','S-1-5-32-544')){throw 'TSMA_RUNTIME_ACL_UNTRUSTED: existing runtime access must be limited to SYSTEM and local Administrators.'}
    }
}
function Assert-TSMANoLinkedAncestor {
    [CmdletBinding()]param([Parameter(Mandatory)][string]$LiteralPath)
    $cursor=[IO.DirectoryInfo]::new($LiteralPath)
    while($null -ne $cursor){if($cursor.Exists -and ($cursor.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'TSMA_RUNTIME_LINK_REJECTED'};$cursor=$cursor.Parent}
}
function Initialize-TSMAProtectedDirectory {
    [CmdletBinding(SupportsShouldProcess)]param([Parameter(Mandatory)][string]$LiteralPath)
    Assert-TSMANoLinkedAncestor -LiteralPath $LiteralPath
    $exists=Test-Path -LiteralPath $LiteralPath
    if($exists){Assert-TSMAExistingRuntimeItem -LiteralPath $LiteralPath}
    if(-not $PSCmdlet.ShouldProcess($LiteralPath,'Create or normalize protected Administrators-owned directory')){return}
    $security=Get-TSMAProtectedSecurity -Directory
    if($exists){Set-Acl -LiteralPath $LiteralPath -AclObject $security -ErrorAction Stop}else{
        # Create with its protected DACL/owner atomically, not after inheriting a writable ACL.
        [IO.FileSystemAclExtensions]::Create([IO.DirectoryInfo]::new($LiteralPath),$security)
    }
    Assert-TSMAExistingRuntimeItem -LiteralPath $LiteralPath -RequireProtectedAcl
}
function Set-TSMAProtectedItem {
    [CmdletBinding(SupportsShouldProcess)]param([Parameter(Mandatory)][string]$LiteralPath)
    $item=Get-Item -LiteralPath $LiteralPath -Force -ErrorAction Stop
    if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'TSMA_RUNTIME_LINK_REJECTED'}
    if(-not $PSCmdlet.ShouldProcess($LiteralPath,'Apply protected Administrators ownership and runtime permissions')){return}
    $security=Get-TSMAProtectedSecurity -Directory:$item.PSIsContainer
    Set-Acl -LiteralPath $LiteralPath -AclObject $security -ErrorAction Stop
    Assert-TSMAExistingRuntimeItem -LiteralPath $LiteralPath -RequireProtectedAcl
}
function Invoke-TSMAWorkerInstallation {
    [CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')]
    param([Parameter(Mandatory)][string]$SourceRoot,[switch]$MaintenanceAcknowledged)
    $ErrorActionPreference='Stop'
    if(-not $IsWindows){throw 'Windows required.'}
    $destination='C:\ProgramData\TSMA'
    $sourcePath=(Resolve-Path -LiteralPath $SourceRoot -ErrorAction Stop).Path
    foreach($relative in @('src/contracts/RunbookVault.psm1','src/vaults/openbao/OpenBao.psm1','src/platforms/azure/ArcIdentity.ps1','src/operations/DirectoryOperations/DirectoryOperations.psm1')) {
        if(-not (Test-Path -LiteralPath (Join-Path $sourcePath $relative) -PathType Leaf)){throw ('Source layout incomplete: '+$relative)}
    }
    foreach($item in @(Get-Item -LiteralPath (Join-Path $sourcePath 'src'))+@(Get-ChildItem -LiteralPath (Join-Path $sourcePath 'src') -Recurse -Force)) {
        if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Linked source paths are unsupported.'}
    }
    Assert-TSMANoLinkedAncestor -LiteralPath $destination
    if(Test-Path -LiteralPath $destination){
        # Reject rather than silently adopt attacker-owned or permissively secured content.
        Assert-TSMAExistingRuntimeItem -LiteralPath $destination -RequireProtectedAcl
        foreach($item in Get-ChildItem -LiteralPath $destination -Recurse -Force){Assert-TSMAExistingRuntimeItem -LiteralPath $item.FullName}
    }
    if((Test-Path -LiteralPath (Join-Path $destination 'src')) -and -not $MaintenanceAcknowledged){throw 'Existing installation: pause admissions, drain jobs, and supply MaintenanceAcknowledged.'}
    if(-not $PSCmdlet.ShouldProcess($destination,'Install protected TSMA source; normalize trusted ownership and preserve configuration/evidence contents')){return}
    Initialize-TSMAProtectedDirectory -LiteralPath $destination -Confirm:$false
    foreach($name in @('Config','src','Evidence')){Initialize-TSMAProtectedDirectory -LiteralPath (Join-Path $destination $name) -Confirm:$false}
    Copy-Item -Path (Join-Path $sourcePath 'src/*') -Destination (Join-Path $destination 'src') -Recurse -Force -ErrorAction Stop
    # Normalize ownership and DACLs on installed code and retained data, not their contents.
    foreach($item in Get-ChildItem -LiteralPath $destination -Recurse -Force){Set-TSMAProtectedItem -LiteralPath $item.FullName -Confirm:$false}
    [pscustomobject]@{RuntimeRoot=$destination;CodeInstalled=$true;OwnershipNormalized=$true;ConfigurationContentsChanged=$false;EvidenceContentsChanged=$false;AzureChanged=$false;ADChanged=$false}
}
Invoke-TSMAWorkerInstallation -SourceRoot $SourceRoot -MaintenanceAcknowledged:$MaintenanceAcknowledged -WhatIf:$WhatIfPreference
