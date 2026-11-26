#Requires -Version 7.4
# SPDX-License-Identifier: Apache-2.0
Set-StrictMode -Version Latest
$script:ProviderModule=$null
function Initialize-RunbookVault {
    <# .SYNOPSIS
    Select a code-owned provider; never load executable paths from configuration.
    #>
    [CmdletBinding()]param([Parameter(Mandatory)][string]$ConfigurationPath)
    Close-RunbookVault
    try {
        $config=Get-Content -LiteralPath $ConfigurationPath -Raw -ErrorAction Stop | ConvertFrom-Json
        if($config.Provider -cne 'OpenBao'){throw 'Unsupported provider'}
        $script:ProviderModule=Import-Module (Join-Path $PSScriptRoot '../vaults/openbao/OpenBao.psm1') -Force -PassThru -Prefix TsmaProvider -Scope Local -ErrorAction Stop
        & $script:ProviderModule {param($Path) Initialize-RunbookVault -ConfigurationPath $Path} $ConfigurationPath
    } catch {$script:ProviderModule=$null;throw 'RUNBOOK_VAULT_CONFIG_INVALID'}
}
function Test-RunbookVault {
    <# .SYNOPSIS
    Check mapped credential health through the selected provider.
    #>
    [CmdletBinding()]param([string]$Reference='OperationDirectory')
    if($null -eq $script:ProviderModule){throw 'RUNBOOK_VAULT_UNINITIALIZED'}
    & $script:ProviderModule {param($Name) Test-RunbookVault -Reference $Name} $Reference
}
function Get-RunbookCredential {
    <# .SYNOPSIS
    Return an in-memory PSCredential through the selected provider.
    #>
    [CmdletBinding()][OutputType([Management.Automation.PSCredential])]
    param([string]$Reference='OperationDirectory')
    if($null -eq $script:ProviderModule){throw 'RUNBOOK_VAULT_UNINITIALIZED'}
    & $script:ProviderModule {param($Name) Get-RunbookCredential -Reference $Name} $Reference
}
function Close-RunbookVault {
    <# .SYNOPSIS
    Forget local provider state; does not rotate passwords or cancel sessions.
    #>
    [CmdletBinding()]param()
    if($null -ne $script:ProviderModule){& $script:ProviderModule {Close-RunbookVault}}
    $script:ProviderModule=$null
}
Export-ModuleMember -Function Initialize-RunbookVault,Test-RunbookVault,Get-RunbookCredential,Close-RunbookVault
