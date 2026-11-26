#Requires -Version 7.4
# SPDX-License-Identifier: Apache-2.0
[CmdletBinding()]param()
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'deployment/Install-WindowsWorker.ps1'), [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'Installer parse failed' }
$definitions = ($ast.EndBlock.Statements | Where-Object { $_ -is [Management.Automation.Language.FunctionDefinitionAst] } | ForEach-Object { $_.Extent.Text }) -join "
"
$module = New-Module -Name WorkerOwnershipTests -ScriptBlock ([scriptblock]::Create($definitions + ';Export-ModuleMember -Function *'))
Import-Module $module -Force
$checks = 0
function Assert-Check { param([bool]$Condition, [string]$Name) if (-not $Condition) { throw $Name }; $script:checks++ }
try {
    foreach ($directory in @($false, $true)) {
        $security = Get-TSMAProtectedSecurity -Directory:$directory
        Assert-Check ($security.GetOwner([Security.Principal.SecurityIdentifier]).Value -eq 'S-1-5-32-544') 'Canonical Administrators owner'
        Assert-Check $security.AreAccessRulesProtected 'Inheritance disabled'
        $rules = @($security.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier]))
        Assert-Check ($rules.Count -eq 2 -and @($rules | Where-Object { $_.IdentityReference.Value -notin @('S-1-5-18', 'S-1-5-32-544') -or $_.FileSystemRights -ne 'FullControl' -or $_.AccessControlType -ne 'Allow' }).Count -eq 0) 'Only trusted full-control principals'
        if ($directory) { Assert-Check (@($rules | Where-Object { $_.InheritanceFlags -ne 'ContainerInherit, ObjectInherit' }).Count -eq 0) 'Directory rules inherit to descendants' }
    }
    # Dynamic module-local mocks deliberately replace filesystem commands.
    $fixtureDefinition = @'

        $script:Fixture = @{Mode = 'Safe'; Writes = 0; Copies = 0 }
        function script:Resolve-Path { param($LiteralPath, $ErrorAction) [pscustomobject]@{Path = 'C:\Fixture' } }
        function script:Test-Path { param($LiteralPath, $PathType) if ($LiteralPath -like 'C:\Fixture*') { return $true }; $script:Fixture.Mode -ne 'Fresh' }
        function script:Get-Item { param($LiteralPath, [switch]$Force, $ErrorAction) [pscustomobject]@{FullName = $LiteralPath; Attributes = $(if ($script:Fixture.Mode -eq 'Link' -and $LiteralPath -notlike 'C:\Fixture*') { [IO.FileAttributes]::ReparsePoint }else { 0 }); PSIsContainer = $true } }
        function script:Get-ChildItem { param($LiteralPath, [switch]$Recurse, [switch]$Force) if ($LiteralPath -like 'C:\ProgramData\TSMA*') { [pscustomobject]@{FullName = 'C:\ProgramData\TSMA\Config\retained.json'; Attributes = 0; PSIsContainer = $false } } }
        function script:Get-Acl {
            param($LiteralPath, $ErrorAction)
            $owner = if ($script:Fixture.Mode -eq 'RootOwner' -or ($script:Fixture.Mode -eq 'ChildOwner' -and $LiteralPath -like '*retained.json')) { 'S-1-5-21-1-2-3-1001' }else { 'S-1-5-18' }
            $descriptor = [pscustomobject]@{OwnerSid = $owner; AreAccessRulesProtected = ($script:Fixture.Mode -ne 'InheritedRoot') }
            $descriptor | Add-Member ScriptMethod GetOwner { param($Type) [Security.Principal.SecurityIdentifier]::new($this.OwnerSid) }
            $descriptor | Add-Member ScriptMethod GetAccessRules {
                param($Explicit, $Inherited, $Type)
                $sid = if ($script:Fixture.Mode -eq 'UntrustedAce') { 'S-1-1-0' }else { 'S-1-5-32-544' }
                [pscustomobject]@{AccessControlType = 'Allow'; IdentityReference = [Security.Principal.SecurityIdentifier]::new($sid) }
            }
            $descriptor
        }
        function script:Assert-TSMANoLinkedAncestor { param($LiteralPath) if (-not $LiteralPath) { throw 'Missing path' } }
        function script:Initialize-TSMAProtectedDirectory { param($LiteralPath, $Confirm) if (-not $LiteralPath) { throw 'Missing directory' }; $script:Fixture.Writes++ }
        function script:Set-TSMAProtectedItem { param($LiteralPath, $Confirm) if (-not $LiteralPath) { throw 'Missing item' }; $script:Fixture.Writes++ }
        function script:Copy-Item { param($Path, $Destination, [switch]$Recurse, [switch]$Force, $ErrorAction) if ($Destination -ne 'C:\ProgramData\TSMA\src') { throw 'Unexpected copy destination' }; $script:Fixture.Copies++ }

'@
    & $module ([scriptblock]::Create($fixtureDefinition))
    foreach ($case in @(
            @{Mode = 'RootOwner'; Code = 'TSMA_RUNTIME_OWNER_UNTRUSTED*' },
            @{Mode = 'ChildOwner'; Code = 'TSMA_RUNTIME_OWNER_UNTRUSTED*' },
            @{Mode = 'UntrustedAce'; Code = 'TSMA_RUNTIME_ACL_UNTRUSTED*' },
            @{Mode = 'InheritedRoot'; Code = 'TSMA_RUNTIME_ACL_UNPROTECTED' },
            @{Mode = 'Link'; Code = 'TSMA_RUNTIME_LINK_REJECTED' }
        )) {
        & $module { param($Mode) $script:Fixture = @{Mode = $Mode; Writes = 0; Copies = 0 } } $case.Mode
        $message = ''
        try { Invoke-TSMAWorkerInstallation -SourceRoot 'C:\Fixture' -MaintenanceAcknowledged -Confirm:$false | Out-Null }catch { $message = $_.Exception.Message }
        $state = & $module { $script:Fixture }
        Assert-Check ($message -like $case.Code -and $state.Writes -eq 0 -and $state.Copies -eq 0) ('Reject unsafe existing runtime before writes: ' + $case.Mode)
    }
    & $module { $script:Fixture = @{Mode = 'Safe'; Writes = 0; Copies = 0 } }
    $message = ''; try { Invoke-TSMAWorkerInstallation -SourceRoot 'C:\Fixture' -Confirm:$false | Out-Null }catch { $message = $_.Exception.Message }
    Assert-Check ($message -like 'Existing installation:*' -and (& $module { $script:Fixture.Writes }) -eq 0) 'Maintenance acknowledgement required'
    Invoke-TSMAWorkerInstallation -SourceRoot 'C:\Fixture' -MaintenanceAcknowledged -WhatIf | Out-Null
    Assert-Check ((& $module { $script:Fixture.Writes + $script:Fixture.Copies }) -eq 0) 'WhatIf makes no writes'
    foreach ($mode in @('Safe', 'Fresh')) {
        & $module { param($Mode) $script:Fixture = @{Mode = $Mode; Writes = 0; Copies = 0 } } $mode
        $result = Invoke-TSMAWorkerInstallation -SourceRoot 'C:\Fixture' -MaintenanceAcknowledged -Confirm:$false
        $state = & $module { $script:Fixture }
        Assert-Check ($result.CodeInstalled -and $result.OwnershipNormalized -and -not $result.ConfigurationContentsChanged -and -not $result.EvidenceContentsChanged -and $state.Copies -eq 1 -and $state.Writes -ge 4) ('Trusted install preserves contents: ' + $mode)
    }
    [pscustomobject]@{Checks = $checks; Failed = 0; RuntimeFilesystemModified = $false; LiveServicesContacted = $false }
}
finally { Remove-Module WorkerOwnershipTests -ErrorAction SilentlyContinue }

