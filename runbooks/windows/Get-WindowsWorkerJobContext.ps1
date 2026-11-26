#Requires -Version 7.4
# SPDX-License-Identifier: Apache-2.0
<#
.SYNOPSIS
Report safe job-correlation results without printing raw platform metadata.
#>
[CmdletBinding()]param()
function Get-WorkerMetadataShape {
    # Shape labels and booleans only. Never return raw values or arbitrary keys.
    [CmdletBinding()]param([AllowNull()][string]$Value)
    $format='UnrecognizedText';$serialized=$false;$jobField=$false;$runbookField=$false
    if([string]::IsNullOrWhiteSpace($Value)){$format='Missing'}
    elseif($Value.Length -gt 8192){$format='TooLarge'}
    else {
        $text=$Value.Trim()
        switch -CaseSensitive ($text) {
            'System.Collections.Hashtable' {$format='SerializedHashtableTypeName';$serialized=$true}
            'System.Collections.Specialized.OrderedDictionary' {$format='SerializedOrderedDictionaryTypeName';$serialized=$true}
            'System.Management.Automation.PSCustomObject' {$format='SerializedPSCustomObjectTypeName';$serialized=$true}
        }
        if(-not $serialized) {
            $parsed=[guid]::Empty
            if([guid]::TryParse($text,[ref]$parsed)){$format=if($parsed -eq [guid]::Empty){'EmptyGuid'}else{'Guid'}}
            elseif($text.StartsWith('@{')){$format='PowerShellHashtableText'}
            elseif($text.StartsWith('{') -or $text.StartsWith('[') -or $text.StartsWith('"')) {
                try {
                    $decoded=ConvertFrom-Json -InputObject $text -ErrorAction Stop
                    if($text.StartsWith('{')) {
                        $format='JsonObject'
                        $jobField=$null -ne $decoded.PSObject.Properties['JobId']
                        $runbookField=$null -ne $decoded.PSObject.Properties['RunbookJobId']
                    } elseif($text.StartsWith('[')) {$format='JsonArray'}else{$format='JsonScalar'}
                } catch {$format='MalformedJson'}
            }
        }
    }
    [pscustomobject]@{Format=$format;IsSerializedTypeName=$serialized;HasJobIdField=$jobField;HasRunbookJobIdField=$runbookField}
}
$ErrorActionPreference='Stop'
if(-not $IsWindows -or [Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne 'S-1-5-18'){throw 'DIRECTORY_SYSTEM_WORKER_REQUIRED'}
Import-Module 'C:\ProgramData\TSMA\src\operations\DirectoryOperations\DirectoryOperations.psm1' -Force -ErrorAction Stop
$metadata=Get-Variable PSPrivateMetadata -ValueOnly -ErrorAction SilentlyContinue
$environmentMetadata=[Environment]::GetEnvironmentVariable('PSPrivateMetadata','Process')
$context=Get-DirectoryJobContext -Metadata $metadata -EnvironmentMetadata $environmentMetadata
$shape=Get-WorkerMetadataShape -Value $environmentMetadata
[pscustomobject]@{
    DiagnosticVersion=2
    Computer=[Environment]::MachineName
    PowerShell=$PSVersionTable.PSVersion.ToString()
    AzureJobId=$context.AzureJobId
    AzureJobIdSource=$context.AzureJobIdSource
    JobCorrelationStatus=$context.JobCorrelationStatus
    MetadataObjectType=$(if($null -eq $metadata){'Missing'}else{$metadata.GetType().FullName})
    EnvironmentMetadataFormat=$shape.Format
    EnvironmentMetadataIsSerializedTypeName=$shape.IsSerializedTypeName
    EnvironmentMetadataHasJobIdField=$shape.HasJobIdField
    EnvironmentMetadataHasRunbookJobIdField=$shape.HasRunbookJobIdField
    DirectoryChangesRequested=$false
    Utc=[DateTimeOffset]::UtcNow.ToString('o')
}
$metadata=$null;$environmentMetadata=$null
