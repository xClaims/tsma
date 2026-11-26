#Requires -Version 5.1
# SPDX-License-Identifier: Apache-2.0
<# Offline diagnostic contract tests; loads function ASTs, never AD or vault. #>
[CmdletBinding()]param()
$ErrorActionPreference='Stop'
$base=Split-Path $PSScriptRoot -Parent
$tokens=$null;$parseErrors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $base 'src/operations/DirectoryOperations/DirectoryOperations.psm1'),[ref]$tokens,[ref]$parseErrors)
if($parseErrors.Count){throw 'Parse failed'}
$functions=($ast.EndBlock.Statements | Where-Object {$_ -is [Management.Automation.Language.FunctionDefinitionAst]} | ForEach-Object {$_.Extent.Text}) -join "`n"
$module=New-Module -Name DirectoryDiagnosticTests -ScriptBlock ([scriptblock]::Create("Set-StrictMode -Version Latest`n"+$functions+"`nExport-ModuleMember -Function *"))
Import-Module $module -Force
$checks=0
function Assert-Case {param([bool]$Ok,[string]$Name) if(-not $Ok){throw $Name};$script:checks++}
$id='11111111-1111-1111-1111-111111111111';$other='22222222-2222-2222-2222-222222222222'
$cases=@(
    @{Name='Dictionary';Metadata=@{JobId=$id};Environment=$null;Expected='Captured'},
    @{Name='Ordered dictionary';Metadata=[ordered]@{jobid=[guid]$id};Environment=$null;Expected='Captured'},
    @{Name='Object';Metadata=[pscustomobject]@{JobId=[guid]$id};Environment=$null;Expected='Captured'},
    @{Name='Nested Guid';Metadata=@{JobId=[pscustomobject]@{Guid=$id}};Environment=$null;Expected='Captured'},
    @{Name='Environment GUID';Metadata=$null;Environment=$id;Expected='Captured'},
    @{Name='Environment JSON';Metadata=$null;Environment=('{"JobId":"'+$id+'"}');Expected='Captured'},
    @{Name='Environment nested JSON';Metadata=$null;Environment=('{"JobId":{"Guid":"'+$id+'"}}');Expected='Captured'},
    @{Name='Matching sources';Metadata=@{JobId=$id};Environment=$id;Expected='Captured'},
    @{Name='Conflicting sources';Metadata=@{JobId=$id};Environment=$other;Expected='Conflicting'},
    @{Name='Missing';Metadata=$null;Environment=$null;Expected='Unavailable'},
    @{Name='Broken serialized dictionary';Metadata=$null;Environment='System.Collections.Hashtable';Expected='Unavailable'},
    @{Name='Malformed JSON';Metadata=$null;Environment='{invalid';Expected='Unavailable'},
    @{Name='Unlabeled root Guid';Metadata=@{Guid=$id};Environment=$null;Expected='Unavailable'},
    @{Name='Unrelated GUID';Metadata=@{TenantId=$id};Environment=$null;Expected='Unavailable'},
    @{Name='Empty GUID';Metadata=@{JobId=[guid]::Empty};Environment=$null;Expected='Unavailable'},
    @{Name='Oversized metadata';Metadata=$null;Environment=('x'*9000);Expected='Unavailable'}
)
try {
    foreach($case in $cases) {
        $r=Get-DirectoryJobContext -Metadata $case.Metadata -EnvironmentMetadata $case.Environment
        Assert-Case ($r.JobCorrelationStatus -eq $case.Expected -and $(if($case.Expected -eq 'Captured'){$r.AzureJobId -eq $id -and -not [string]::IsNullOrWhiteSpace($r.AzureJobIdSource)}else{$null -eq $r.AzureJobId})) $case.Name
    }
    $r=Get-DirectoryFailureDetail -Code DIRECTORY_USER_DISABLED
    Assert-Case ($r.Reason -eq 'User account is disabled.' -and $r.ReasonCode -eq 'DIRECTORY_USER_DISABLED') 'Disabled message'
    $r=Get-DirectoryFailureDetail -Code 'SENSITIVE-ERROR-MUST-NOT-ESCAPE'
    Assert-Case ($r.ReasonCode -eq 'DIRECTORY_PROVIDER_OR_EVIDENCE_FAILURE' -and ($r|ConvertTo-Json) -notmatch 'SENSITIVE') 'Unknown errors sanitized'
    $secret=[Security.SecureString]::new();$secret.AppendChar('x');$secret.MakeReadOnly()
    $credential=[pscredential]::new('EXAMPLE\svc-op-directory',$secret)
    & $module {
        $script:SnapshotCase='Disabled'
        function script:Get-DirectoryGroup {param($Identity,$Policy,[pscredential]$Credential,$Properties) if(-not $Identity -or -not $Policy -or -not $Credential -or -not $Properties){throw 'Invalid context'};[pscustomobject]@{GroupCategory=$(if($script:SnapshotCase -eq 'Distribution'){'Distribution'}else{'Security'})}}
        function script:Get-DirectoryUser {param($Identity,$Policy,[pscredential]$Credential,$Properties) if(-not $Identity -or -not $Policy -or -not $Credential -or -not $Properties){throw 'Invalid context'};[pscustomobject]@{Enabled=($script:SnapshotCase -ne 'Disabled');primaryGroupID=$(if($script:SnapshotCase -eq 'PrimaryGroup'){512}else{513})}}
    }
    foreach($case in @(@{Name='Disabled';Code='DIRECTORY_USER_DISABLED'},@{Name='Distribution';Code='DIRECTORY_GROUP_NOT_SECURITY'},@{Name='PrimaryGroup';Code='DIRECTORY_USER_PRIMARY_GROUP_UNSUPPORTED'})) {
        & $module {param($Name) $script:SnapshotCase=$Name} $case.Name
        $message=''
        try {Get-DirectoryMembershipSnapshot -Policy @{DomainController='dc01.ad.example.com'} -GroupObjectGuid ([guid]$id) -MemberObjectGuid ([guid]$other) -Credential $credential}catch{$message=$_.Exception.Message}
        Assert-Case ($message -eq $case.Code) $case.Name
    }
    [pscustomobject]@{Checks=$checks;Failed=0;LiveServicesContacted=$false}
} finally {if($null -ne $secret){$secret.Dispose()};Remove-Module DirectoryDiagnosticTests -ErrorAction SilentlyContinue}
