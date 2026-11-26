#Requires -Version 7.4
# SPDX-License-Identifier: Apache-2.0
<#
.SYNOPSIS
Provision an empty production-named Operation Automation account and worker group.
.DESCRIPTION
Does not register workers, grant access, create schedules or deploy mutation runbooks.
Uses the caller's selected Azure context; never silently changes subscriptions.
#>
[CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')]
param(
    [Parameter(Mandatory)][guid]$SubscriptionId,
    [ValidateSet('Directory','Server')][string]$Service='Directory',
    [string]$Location='westus',
    [ValidatePattern('^[a-z0-9]{2,10}$')][string]$RegionCode='wus',
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ServiceOwner,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$CostCenter
)
$ErrorActionPreference='Stop'
Import-Module Az.Accounts -ErrorAction Stop
Import-Module Az.Resources -ErrorAction Stop
$context=Get-AzContext
if($null -eq $context -or $context.Subscription.Id -ne $SubscriptionId.ToString()){
    throw 'Select the intended Azure subscription before deployment.'
}
$category=$Service.ToLowerInvariant()
$suffix='operation-'+$category+'-prd-'+$RegionCode+'-001'
$resourceGroup='rg-'+$suffix
$account='aa-'+$suffix
$workerGroup='hwg-'+$suffix
if($account.Length -gt 50){throw 'Automation account name exceeds the service limit.'}
$tags=@{Workload='OperationAutomation';Environment='Production';ServiceOwner=$ServiceOwner;CostCenter=$CostCenter;ManagedBy='RepositoryDeployment'}
if($PSCmdlet.ShouldProcess($resourceGroup,('Deploy empty '+$Service+' Automation control plane'))){
    $null=New-AzResourceGroup -Name $resourceGroup -Location $Location -Tag $tags
    New-AzResourceGroupDeployment -ResourceGroupName $resourceGroup -Mode Incremental -TemplateFile (Join-Path $PSScriptRoot 'operation-control-plane.json') -accountName $account -workerGroupName $workerGroup -location $Location -resourceTags $tags
}
