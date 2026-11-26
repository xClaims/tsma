#Requires -Version 7.4
# SPDX-License-Identifier: Apache-2.0
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidOverwritingBuiltInCmdlets','',Justification='Offline fixture replaces module import to prevent Azure module loading.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions','',Justification='Mock Azure commands record calls only; production ShouldProcess is tested separately.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars','',Justification='Unique fixture state crosses external script scopes and is removed in finally.')]
[CmdletBinding()]param()
$ErrorActionPreference='Stop'
$deployment=Join-Path (Split-Path $PSScriptRoot -Parent) 'deployment/azure'
$fixture=New-Module -ScriptBlock {
    $global:OperationProvisioningTestCalls=[Collections.Generic.List[object]]::new()
    $script:Subscription='11111111-1111-1111-1111-111111111111'
    function Import-Module {param($Name,$ErrorAction) $null=$Name;$null=$ErrorAction}
    function Get-AzContext { [pscustomobject]@{Subscription=[pscustomobject]@{Id='11111111-1111-1111-1111-111111111111'}} }
    function New-AzResourceGroup {
        param($Name,$Location,$Tag)
        $global:OperationProvisioningTestCalls.Add(@{Kind='Group';Name=$Name;Location=$Location;Tags=$Tag})
    }
    function New-AzResourceGroupDeployment {
        param($ResourceGroupName,$Mode,$TemplateFile,$accountName,$workerGroupName,$location,$resourceTags)
        if(-not (Test-Path $TemplateFile) -or $Mode -ne 'Incremental'){throw 'Invalid template deployment'}
        $global:OperationProvisioningTestCalls.Add(@{Kind='Deployment';Group=$ResourceGroupName;Account=$accountName;WorkerGroup=$workerGroupName;Location=$location;Tags=$resourceTags})
    }
    function Invoke-AzRestMethod {
        param($Path,$Method,$ErrorAction,$Payload)
        $null=$ErrorAction
        $global:OperationProvisioningTestCalls.Add(@{Kind='Rest';Path=$Path;Method=$Method;Payload=$Payload})
        if($Method -eq 'GET'){
            $body=if($Path -like '*/Microsoft.HybridCompute/*'){
                @{location='westus';identity=@{type='SystemAssigned'};properties=@{status='Connected';osType='Windows'}}
            }else{@{properties=@{automationHybridServiceUrl='https://example.azure-automation.net'}}}
            return [pscustomobject]@{StatusCode=200;Content=($body|ConvertTo-Json -Depth 6)}
        }
        [pscustomobject]@{StatusCode=201;Content='{}'}
    }
}
try {
    & $fixture {
        param($Deployment)
        $subscription=[guid]$script:Subscription
        $deploy=Join-Path $Deployment 'Deploy-OperationControlPlane.ps1'
        & $deploy -SubscriptionId $subscription -ServiceOwner Operations -CostCenter Identity -WhatIf
        if($global:OperationProvisioningTestCalls.Count){throw 'WhatIf wrote resources'}
        & $deploy -SubscriptionId $subscription -ServiceOwner Operations -CostCenter Identity -Confirm:$false | Out-Null
        $d=$global:OperationProvisioningTestCalls | Where-Object Kind -eq Deployment
        if($d.Account -ne 'aa-operation-directory-prd-wus-001' -or $d.WorkerGroup -ne 'hwg-operation-directory-prd-wus-001' -or $d.Tags.Environment -ne 'Production'){throw 'Production identity/tag contract failed'}
        $global:OperationProvisioningTestCalls.Clear()
        try {
            & $deploy -SubscriptionId '22222222-2222-2222-2222-222222222222' -ServiceOwner Operations -CostCenter Identity -Confirm:$false | Out-Null
            throw 'Expected context refusal'
        } catch {if($_.Exception.Message -ne 'Select the intended Azure subscription before deployment.'){throw}}
        if($global:OperationProvisioningTestCalls.Count){throw 'Wrong subscription caused writes'}
        $account='/subscriptions/'+$subscription+'/resourceGroups/rg-operation/providers/Microsoft.Automation/automationAccounts/aa-operation'
        $machine='/subscriptions/'+$subscription+'/resourceGroups/rg-operation/providers/Microsoft.HybridCompute/machines/OPAUTDIR01'
        $register=Join-Path $Deployment 'Register-ArcWorker.ps1'
        & $register -AutomationAccountId $account -ArcMachineId $machine -OperatingSystem Windows -WorkerId '33333333-3333-3333-3333-333333333333' -WorkerGroupName 'hwg-operation-directory-prd-wus-001' -WhatIf | Out-Null
        if(@($global:OperationProvisioningTestCalls | Where-Object Method -eq PUT).Count){throw 'Registration WhatIf sent PUT'}
        $global:OperationProvisioningTestCalls.Clear()
        & $register -AutomationAccountId $account -ArcMachineId $machine -OperatingSystem Windows -WorkerId '33333333-3333-3333-3333-333333333333' -WorkerGroupName 'hwg-operation-directory-prd-wus-001' -Confirm:$false | Out-Null
        $puts=@($global:OperationProvisioningTestCalls | Where-Object Method -eq PUT)
        if($puts.Count -ne 2 -or $puts[0].Path -notlike '*/hybridRunbookWorkerGroups/hwg-operation-directory-prd-wus-001/*'){throw 'Wrong worker group registration'}
        $global:OperationProvisioningTestCalls.Clear()
        & $register -AutomationAccountId $account -ArcMachineId $machine -OperatingSystem Windows -WorkerId '33333333-3333-3333-3333-333333333333' -Confirm:$false | Out-Null
        $legacyPut=@($global:OperationProvisioningTestCalls | Where-Object Method -eq PUT)[0]
        if($legacyPut.Path -notlike '*/hybridRunbookWorkerGroups/windows-operations/*'){throw 'Default worker group changed'}
        [pscustomobject]@{Checks=6;Failed=0;AzureContacted=$false}
    } $deployment
} finally {Remove-Module $fixture -ErrorAction SilentlyContinue; Remove-Variable OperationProvisioningTestCalls -Scope Global -ErrorAction SilentlyContinue}
