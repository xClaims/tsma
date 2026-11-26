#Requires -Version 7.4
#Requires -RunAsAdministrator
# SPDX-License-Identifier: Apache-2.0
<# .SYNOPSIS
Validate and install a new protected vault configuration without logging its contents.
#>
[CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')]
param([Parameter(Mandatory)][string]$ConfigurationPath)
$ErrorActionPreference='Stop'
if(-not $IsWindows){throw 'Windows required.'}
$destination='C:\ProgramData\TSMA\Config\Vault-OperationDirectory.json'
if(Test-Path -LiteralPath $destination){throw 'Configuration exists. Review and replace it under a controlled maintenance procedure.'}
$parent=Get-Item -LiteralPath (Split-Path $destination -Parent) -ErrorAction Stop
for($cursor=$parent;$null -ne $cursor;$cursor=$cursor.Parent){if($cursor.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Linked runtime path rejected.'}}
$acl=Get-Acl -LiteralPath $parent.FullName
if(-not $acl.AreAccessRulesProtected){throw 'Install the protected runtime first.'}
foreach($rule in $acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])){if($rule.AccessControlType -eq 'Allow' -and $rule.IdentityReference.Value -notin @('S-1-5-18','S-1-5-32-544')){throw 'Unsafe runtime ACL.'}}
# Validate the installed trust boundary before writing configuration.
foreach($protectedPath in @('C:\ProgramData\TSMA','C:\ProgramData\TSMA\Config')) {
    $protectedItem=Get-Item -LiteralPath $protectedPath -Force -ErrorAction Stop
    for($cursor=$protectedItem;$null -ne $cursor;$cursor=$cursor.Parent){if($cursor.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Linked runtime path rejected.'}}
    $protectedAcl=Get-Acl -LiteralPath $protectedPath -ErrorAction Stop
    if($protectedAcl.GetOwner([Security.Principal.SecurityIdentifier]).Value -notin @('S-1-5-18','S-1-5-32-544') -or -not $protectedAcl.AreAccessRulesProtected){throw 'Runtime owner/ACL is untrusted. Complete protected installation or controlled recovery first.'}
    foreach($rule in $protectedAcl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])){if($rule.AccessControlType -eq 'Allow' -and $rule.IdentityReference.Value -notin @('S-1-5-18','S-1-5-32-544')){throw 'Untrusted runtime access.'}}
}
Import-Module 'C:\ProgramData\TSMA\src\contracts\RunbookVault.psm1' -Force -ErrorAction Stop
try {
    Initialize-RunbookVault -ConfigurationPath $ConfigurationPath
    $content=Get-Content -LiteralPath $ConfigurationPath -Raw -ErrorAction Stop
    if($content -match 'example\.com|11111111-1111-4111-8111-111111111111|REPLACE_'){throw 'Replace example values before installation.'}
    if(-not $PSCmdlet.ShouldProcess($destination,'Install new protected nonsecret vault mapping')){return}
    $fileAcl=[Security.AccessControl.FileSecurity]::new();$fileAcl.SetAccessRuleProtection($true,$false)
    $fileAcl.SetOwner([Security.Principal.SecurityIdentifier]::new('S-1-5-32-544'))
    foreach($sid in @('S-1-5-18','S-1-5-32-544')){$fileAcl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($sid),'FullControl','Allow'))}
    $stream=[IO.File]::Open($destination,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try {$bytes=[Text.Encoding]::UTF8.GetBytes($content);$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
    Set-Acl -LiteralPath $destination -AclObject $fileAcl
    [pscustomobject]@{ConfigurationInstalled=$true;Path=$destination;CredentialRetrieved=$false}
} finally {Close-RunbookVault}
