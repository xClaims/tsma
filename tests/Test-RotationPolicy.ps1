#Requires -Version 7.4
# SPDX-License-Identifier: Apache-2.0
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidOverwritingBuiltInCmdlets','',Justification='The isolated fixture supplies in-memory ACLs; it never changes runtime permissions.')]
[CmdletBinding()]param()
$ErrorActionPreference='Stop'
$base=Split-Path $PSScriptRoot -Parent
$root=Join-Path ([IO.Path]::GetTempPath()) ('tsma-policy-'+[guid]::NewGuid().ToString('N'))
$configDirectory=Join-Path $root 'Config'
$null=[IO.Directory]::CreateDirectory($configDirectory)
$vaultPath=Join-Path $configDirectory 'Vault-OperationDirectory.json'
$policyPath=Join-Path $configDirectory 'DirectoryGroupMembership.json'
$source=[IO.File]::ReadAllText((Join-Path $base 'deployment/Set-CredentialRotationPolicy.ps1'))
# Exercise the script's preflight/WhatIf only against a temporary fixture, with
# in-memory ACLs. No installed runtime or Windows ACLs are modified.
$source=$source.Replace('#Requires -RunAsAdministrator','').Replace("`$root='C:\ProgramData\TSMA'",("`$root='"+$root.Replace("'","''")+"'"))
$scriptBlock=[scriptblock]::Create($source)
$module=New-Module -Name RotationPolicyFixture -ScriptBlock {
    $script:Unsafe=$false
    function Get-Acl {
        param($LiteralPath,$ErrorAction)
        if(-not $LiteralPath){throw 'Missing ACL path'}
        if($ErrorAction -and $ErrorAction -ne 'Stop'){throw 'Unexpected error action'}
        $acl=[Security.AccessControl.FileSecurity]::new()
        $acl.SetAccessRuleProtection($true,$false)
        $sid=if($script:Unsafe){'S-1-1-0'}else{'S-1-5-32-544'}
        $acl.SetOwner([Security.Principal.SecurityIdentifier]::new($sid))
        $acl
    }
    Export-ModuleMember -Function @()
}
$checks=0
function Assert-Result {param([bool]$Condition,[string]$Name) if(-not $Condition){throw $Name};$script:checks++}
try {
    $vault=@{Provider='OpenBao';MaximumPasswordAgeSeconds=14400;Accounts=@{OperationDirectory=@{CredentialUserName='EXAMPLE\svc-op-directory'}}}
    $policy=@{MaximumPasswordAgeSeconds=14400;WritesEnabled=$false;ExecutionIdentity='EXAMPLE\svc-op-directory'}
    [IO.File]::WriteAllText($vaultPath,($vault | ConvertTo-Json -Depth 8))
    [IO.File]::WriteAllText($policyPath,($policy | ConvertTo-Json -Depth 8))
    $before=(Get-FileHash -LiteralPath $vaultPath).Hash+':'+(Get-FileHash -LiteralPath $policyPath).Hash
    & $module $scriptBlock -ChangeReference CHG-OFFLINE -MaintenanceAcknowledged -WhatIf
    $after=(Get-FileHash -LiteralPath $vaultPath).Hash+':'+(Get-FileHash -LiteralPath $policyPath).Hash
    Assert-Result ($before -eq $after -and @(Get-ChildItem -LiteralPath $configDirectory -File).Count -eq 2) 'WhatIf preserves files and creates no backups'
    $policy.WritesEnabled=$true
    [IO.File]::WriteAllText($policyPath,($policy | ConvertTo-Json))
    $message='';try{& $module $scriptBlock -ChangeReference CHG-OFFLINE -MaintenanceAcknowledged -WhatIf}catch{$message=$_.Exception.Message}
    Assert-Result ($message -like 'Disable writes*') 'Maintenance gate is enforced even in preview'
    $policy.WritesEnabled=$false;$policy.ExecutionIdentity='EXAMPLE\other'
    [IO.File]::WriteAllText($policyPath,($policy | ConvertTo-Json))
    $message='';try{& $module $scriptBlock -ChangeReference CHG-OFFLINE -MaintenanceAcknowledged -WhatIf}catch{$message=$_.Exception.Message}
    Assert-Result ($message -eq 'Configuration mapping mismatch.') 'Identity mismatch denied'
    & $module {$script:Unsafe=$true}
    $message='';try{& $module $scriptBlock -ChangeReference CHG-OFFLINE -MaintenanceAcknowledged -WhatIf}catch{$message=$_.Exception.Message}
    Assert-Result ($message -eq 'Untrusted runtime owner/ACL.') 'Untrusted owner denied before configuration changes'
    $message='';try{& $module $scriptBlock -ChangeReference CHG-OFFLINE -MaintenanceAcknowledged:$false -WhatIf}catch{$message=$_.Exception.Message}
    Assert-Result ($message -eq 'Drained Windows maintenance required.') 'Explicit maintenance acknowledgement required'
    $message='';try{& $module $scriptBlock -ChangeReference CHG-OFFLINE -MaintenanceAcknowledged -MaximumPasswordAgeSeconds 600 -MinimumRemainingLifetimeSeconds 2100 -WhatIf}catch{$message=$_.Exception.Message}
    Assert-Result ($message -eq 'Admission margin must be shorter than the interval.') 'Invalid interval and margin denied'
    [pscustomobject]@{Checks=$checks;Failed=0;RuntimeFilesystemModified=$false;LiveServicesContacted=$false;AtomicReplacementTested=$false}
} finally {
    [IO.File]::Delete($vaultPath);[IO.File]::Delete($policyPath)
    [IO.Directory]::Delete($configDirectory);[IO.Directory]::Delete($root)
    Remove-Module RotationPolicyFixture -ErrorAction SilentlyContinue
}
