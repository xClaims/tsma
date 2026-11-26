#Requires -Version 5.1
# SPDX-License-Identifier: Apache-2.0
[CmdletBinding()]param([switch]$OfflineOnly)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$checks=0
foreach($file in Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object {$_.FullName -notmatch '[\\/]\.git[\\/]' -and $_.Extension -in @('.ps1','.psm1','.psd1')}) {
    $tokens=$null;$errors=$null
    $null=[Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
    if($errors.Count){throw ('PowerShell parse failed: '+$file.FullName+' '+($errors.Message -join '; '))};$checks++
}
foreach($file in Get-ChildItem -LiteralPath $root -Recurse -File -Filter '*.json' | Where-Object {$_.FullName -notmatch '[\\/]\.git[\\/]'}){$null=Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json;$checks++}
$offline=@('Test-DirectoryGroupMembership.ps1','Test-DirectoryDiagnostics.ps1','Test-DirectoryWriteState.ps1','Test-WorkerMetadataShape.ps1','Test-VaultContract.ps1','Test-Repository.ps1')
$selected=if($OfflineOnly){$offline}else{@(Get-ChildItem -LiteralPath $PSScriptRoot -Filter 'Test-*.ps1' | Select-Object -ExpandProperty Name)}
if(-not $OfflineOnly -and $PSVersionTable.PSVersion -lt [version]'7.4'){throw 'Full suite requires PowerShell 7.4 or later. Use OfflineOnly for isolated logic/source checks.'}
$executable=[Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
foreach($name in $selected){
    Write-Output ('Running '+$name)
    & $executable -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot $name)
    if($LASTEXITCODE -ne 0){throw ('Test script failed: '+$name)}
}
[pscustomobject]@{SourceChecks=$checks;TestScripts=$selected.Count;Failed=0;OfflineOnly=[bool]$OfflineOnly;LiveServicesContacted=$false;ProductionRuntimeValidated=$false}
