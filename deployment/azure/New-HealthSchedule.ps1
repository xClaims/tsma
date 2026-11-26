#Requires -Version 7.4
# SPDX-License-Identifier: Apache-2.0
[CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')]
param(
    [Parameter(Mandatory)][guid]$SubscriptionId,
    [Parameter(Mandatory)][string]$ResourceGroupName,
    [Parameter(Mandatory)][string]$AutomationAccountName,
    [Parameter(Mandatory)][ValidateSet('Windows','Linux')][string]$OperatingSystem,
    [Parameter(Mandatory)][string]$Owner,
    [Parameter(Mandatory)][string]$AuthorizationReference,
    [Parameter(Mandatory)][DateTimeOffset]$StartTime,
    [Parameter(Mandatory)][DateTimeOffset]$ExpiryTime,
    [Parameter(Mandatory)][string]$WorkerGroupName
)
$ErrorActionPreference='Stop'
Import-Module Az.Accounts
Import-Module Az.Automation
if((Get-AzContext).Subscription.Id -ne $SubscriptionId.ToString()){throw 'Select intended subscription first'}
if($StartTime -lt [DateTimeOffset]::UtcNow.AddMinutes(10) -or $ExpiryTime -le $StartTime -or $ExpiryTime -gt $StartTime.AddDays(7)){throw 'Use a start at least ten minutes ahead and expiry within seven days'}
$group=$WorkerGroupName
$runbook='Get-'+$OperatingSystem+'ServiceHealth'
$schedule='tsma-health-'+$OperatingSystem.ToLowerInvariant()
$common=@{ResourceGroupName=$ResourceGroupName;AutomationAccountName=$AutomationAccountName}
$rb=Get-AzAutomationRunbook @common -Name $runbook
if($rb.State -ne 'Published'){throw 'Publish and validate the health runbook first'}
$null=Get-AzAutomationHybridRunbookWorkerGroup @common -Name $group
$existing=@(Get-AzAutomationSchedule @common | Where-Object Name -eq $schedule)
if($existing.Count){throw 'Schedule already exists; review instead of creating duplicate links'}
if($PSCmdlet.ShouldProcess($schedule,'Create finite hourly local-health schedule and link to platform worker group')) {
    $null=New-AzAutomationSchedule @common -Name $schedule -StartTime $StartTime -ExpiryTime $ExpiryTime -HourInterval 1 -TimeZone 'UTC' -Description ('Owner='+$Owner+'; Authorization='+$AuthorizationReference+'; read-only health')
    Register-AzAutomationScheduledRunbook @common -RunbookName $runbook -ScheduleName $schedule -RunOn $group
}
# Non-mutating probes only. No password retrieval, rotation or privileged handler.
