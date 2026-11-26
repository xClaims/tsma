#Requires -Version 5.1
# SPDX-License-Identifier: Apache-2.0
[CmdletBinding()]param()
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'src/contracts/RunbookVault.psm1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Contract parse failed'}
$functions=($ast.EndBlock.Statements | Where-Object {$_ -is [Management.Automation.Language.FunctionDefinitionAst]} | ForEach-Object {$_.Extent.Text}) -join "
"
$module=New-Module -Name ContractLogicTests -ScriptBlock ([scriptblock]::Create('Set-StrictMode -Version Latest;$script:ProviderModule=$null;'+$functions+';Export-ModuleMember -Function *'))
Import-Module $module -Force
$checks=0
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('tsma-contract-'+[guid]::NewGuid()+'.json')
try {
    try {Get-RunbookCredential;throw 'Expected uninitialized failure'}catch{if($_.Exception.Message -ne 'RUNBOOK_VAULT_UNINITIALIZED'){throw};$checks++}
    '{"Provider":"Untrusted","ModulePath":"untrusted.ps1"}' | Set-Content -LiteralPath $fixture
    try {Initialize-RunbookVault -ConfigurationPath $fixture;throw 'Expected provider refusal'}catch{if($_.Exception.Message -ne 'RUNBOOK_VAULT_CONFIG_INVALID'){throw};$checks++}
    $fake=New-Module -Name ContractFakeProvider -ScriptBlock {
        function Test-RunbookVault {param($Reference) [pscustomobject]@{Reference=$Reference;Healthy=$true;LastRotationUtc=[DateTimeOffset]::UtcNow.ToString('o');PasswordAgeLimitSeconds=14400}}
        function Get-RunbookCredential {param($Reference) if($Reference -ne 'OperationDirectory'){throw 'RUNBOOK_VAULT_REFERENCE_DENIED'};$secret=New-Object Security.SecureString;$secret.AppendChar('x');[pscredential]::new('EXAMPLE\svc-op-directory',$secret)}
        function Close-RunbookVault {}
        Export-ModuleMember -Function @()
    }
    & $module {param($Provider) $script:ProviderModule=$Provider} $fake
    $health=Test-RunbookVault -Reference OperationDirectory
    if(-not $health.Healthy -or $health.Reference -ne 'OperationDirectory' -or $health.PasswordAgeLimitSeconds -ne 14400){throw 'Health dispatch failed'};$checks++
    $credential=Get-RunbookCredential -Reference OperationDirectory
    if($credential -isnot [pscredential] -or $credential.UserName -ne 'EXAMPLE\svc-op-directory'){throw 'Credential dispatch failed'};$credential.Password.Dispose();$checks++
    try {Get-RunbookCredential -Reference Schema;throw 'Expected reference refusal'}catch{if($_.Exception.Message -ne 'RUNBOOK_VAULT_REFERENCE_DENIED'){throw};$checks++}
    Close-RunbookVault
    if(& $module {$null -ne $script:ProviderModule}){throw 'Close retained provider'};$checks++
    [pscustomobject]@{Checks=$checks;Failed=0;LiveServicesContacted=$false;ProductionRuntimeValidated=$false}
} finally {Remove-Module ContractLogicTests -ErrorAction SilentlyContinue;[IO.File]::Delete($fixture)}
