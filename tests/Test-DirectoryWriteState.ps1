#Requires -Version 5.1
# SPDX-License-Identifier: Apache-2.0
[CmdletBinding()]param()
$ErrorActionPreference='Stop'
$file=Join-Path (Split-Path $PSScriptRoot -Parent) 'deployment/azure/Set-DirectoryWritesEnabled.ps1'
$tokens=$null;$parseErrors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$parseErrors)
if($parseErrors.Count){throw 'Parse failed'}
$function=@($ast.EndBlock.Statements | Where-Object {$_ -is [Management.Automation.Language.FunctionDefinitionAst] -and $_.Name -eq 'ConvertTo-DirectoryWriteState'})
if($function.Count -ne 1){throw 'Policy transformer missing'}
$module=New-Module -Name WriteStateTests -ScriptBlock ([scriptblock]::Create($function[0].Extent.Text+';Export-ModuleMember -Function ConvertTo-DirectoryWriteState'))
Import-Module $module -Force
$count=0
try {
    $policy=[pscustomobject]@{WritesEnabled=$false;ReviewExpiresUtc=[DateTimeOffset]::UtcNow.AddDays(1).ToString('o');ExclusiveMaintenanceWindow=$false;MaintenanceWindowEndsUtc='1970-01-01T00:00:00Z';ExcludedOuGuids=@('reviewed-root');DomainSid='reviewed-domain'}
    $result=ConvertTo-DirectoryWriteState -Policy $policy -Enabled $true -ChangeReference CHG-1 -IdentitySid S-1-5-18
    if(-not $result.WritesEnabled -or $null -ne $result.PSObject.Properties['MaintenanceWindowEndsUtc'] -or $null -ne $result.PSObject.Properties['ExclusiveMaintenanceWindow']){throw 'Persistent enable/migration failed'};$count++
    if($result.WriteStateChangeReference -ne 'CHG-1' -or $result.WriteStateChangedBySid -ne 'S-1-5-18' -or $result.ExcludedOuGuids[0] -ne 'reviewed-root' -or $result.DomainSid -ne 'reviewed-domain'){throw 'Audit or scope preservation failed'};$count++
    $result=ConvertTo-DirectoryWriteState -Policy $result -Enabled $false -ChangeReference CHG-2 -IdentitySid S-1-5-18
    if($result.WritesEnabled){throw 'Disable failed'};$count++
    $result.ReviewExpiresUtc='1970-01-01T00:00:00Z'
    $result=ConvertTo-DirectoryWriteState -Policy $result -Enabled $false -ChangeReference CHG-3 -IdentitySid S-1-5-18
    if($result.WritesEnabled){throw 'Maintenance disable must work even with expired review'};$count++
    $rejected=$false
    try {$null=ConvertTo-DirectoryWriteState -Policy $result -Enabled $true -ChangeReference CHG-4 -IdentitySid S-1-5-18}catch{$rejected=$true}
    if(-not $rejected -or $result.WritesEnabled){throw 'Expired review bypassed'};$count++
    [pscustomobject]@{Checks=$count;Failed=0;LivePolicyChanged=$false}
} finally {Remove-Module WriteStateTests -ErrorAction SilentlyContinue}
