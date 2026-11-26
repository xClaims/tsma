#Requires -Version 5.1
# SPDX-License-Identifier: Apache-2.0
[CmdletBinding()]param()
$ErrorActionPreference='Stop'
$file=Join-Path (Split-Path $PSScriptRoot -Parent) 'runbooks/windows/Get-WindowsWorkerJobContext.ps1'
$tokens=$null;$parseErrors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$parseErrors)
if($parseErrors.Count){throw 'Probe parse failed'}
$function=@($ast.EndBlock.Statements | Where-Object {$_ -is [Management.Automation.Language.FunctionDefinitionAst] -and $_.Name -eq 'Get-WorkerMetadataShape'})
if($function.Count -ne 1){throw 'Classifier missing'}
# Load only the pure classifier: no runbook entry point, imports, environment reads or AD.
$module=New-Module -Name WorkerMetadataShapeTests -ScriptBlock ([scriptblock]::Create($function[0].Extent.Text+'; Export-ModuleMember -Function Get-WorkerMetadataShape'))
Import-Module $module -Force
$count=0
$cases=@(
    @{Value=$null;Format='Missing'},
    @{Value=' ';Format='Missing'},
    @{Value='System.Collections.Hashtable';Format='SerializedHashtableTypeName'},
    @{Value='  System.Collections.Hashtable  ';Format='SerializedHashtableTypeName'},
    @{Value='System.Collections.Specialized.OrderedDictionary';Format='SerializedOrderedDictionaryTypeName'},
    @{Value='System.Management.Automation.PSCustomObject';Format='SerializedPSCustomObjectTypeName'},
    @{Value='11111111-1111-1111-1111-111111111111';Format='Guid'},
    @{Value='00000000-0000-0000-0000-000000000000';Format='EmptyGuid'},
    @{Value='{"JobId":"11111111-1111-1111-1111-111111111111"}';Format='JsonObject'},
    @{Value='{"RunbookJobId":{}}';Format='JsonObject'},
    @{Value='{"Token":"SENSITIVE-CANARY"}';Format='JsonObject'},
    @{Value='["SENSITIVE-CANARY"]';Format='JsonArray'},
    @{Value='"SENSITIVE-CANARY"';Format='JsonScalar'},
    @{Value='{"broken"';Format='MalformedJson'},
    @{Value='@{JobId=SENSITIVE-CANARY}';Format='PowerShellHashtableText'},
    @{Value='SENSITIVE-CANARY';Format='UnrecognizedText'},
    @{Value=('SENSITIVE-CANARY'*1000);Format='TooLarge'}
)
try {
    foreach($case in $cases) {
        $result=Get-WorkerMetadataShape -Value $case.Value
        if($result.Format -ne $case.Format){throw ('Incorrect shape: '+$case.Format)}
        if(($result | ConvertTo-Json -Compress) -match 'SENSITIVE-CANARY'){throw 'Raw metadata leaked'}
        if($result.IsSerializedTypeName -ne ($case.Format -like 'Serialized*')){throw 'Type-name flag incorrect'}
        $count++
    }
    $result=Get-WorkerMetadataShape -Value '{"JobId":null}'
    if(-not $result.HasJobIdField -or $result.HasRunbookJobIdField){throw 'Job field detection failed'}
    $count++
    $result=Get-WorkerMetadataShape -Value '{"RunbookJobId":null}'
    if($result.HasJobIdField -or -not $result.HasRunbookJobIdField){throw 'Runbook field detection failed'}
    $count++
    [pscustomobject]@{Checks=$count;Failed=0;LiveServicesContacted=$false}
} finally {Remove-Module WorkerMetadataShapeTests -ErrorAction SilentlyContinue}
