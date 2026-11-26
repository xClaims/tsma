#Requires -Version 7.4
# SPDX-License-Identifier: Apache-2.0
[CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')]
param([Parameter(Mandatory)][string]$AutomationAccountId,[Parameter(Mandatory)][string]$ArcMachineId,[Parameter(Mandatory)][ValidateSet('Windows','Linux')][string]$OperatingSystem,[Parameter(Mandatory)][guid]$WorkerId,[ValidatePattern('^[A-Za-z][A-Za-z0-9_-]{0,63}$')][string]$WorkerGroupName)
$ErrorActionPreference='Stop'
Import-Module Az.Accounts
if($AutomationAccountId -notmatch '^/subscriptions/([^/]+)/resourceGroups/[^/]+/providers/Microsoft.Automation/automationAccounts/[^/]+$'){throw 'Invalid Automation account ID'}
$subscriptionId=$Matches[1]
if($ArcMachineId -notmatch '^/subscriptions/([^/]+)/resourceGroups/[^/]+/providers/Microsoft.HybridCompute/machines/[^/]+$' -or $Matches[1] -ne $subscriptionId){throw 'Arc machine must be in the same subscription for this deployment script'}
if((Get-AzContext).Subscription.Id -ne $subscriptionId){throw 'Azure context does not match resource IDs'}
function Invoke-CheckedArm {
    param([string]$Path,[string]$Method,[string]$Payload)
    $argsMap=@{Path=$Path;Method=$Method;ErrorAction='Stop'}
    if($Payload){$argsMap.Payload=$Payload}
    $response=Invoke-AzRestMethod @argsMap
    if([int]$response.StatusCode -notin @(200,201,202)){throw ('ARM request failed with status '+$response.StatusCode)}
    $response
}
$account=(Invoke-CheckedArm -Path ($AutomationAccountId+'?api-version=2023-11-01') -Method GET).Content | ConvertFrom-Json
$machine=(Invoke-CheckedArm -Path ($ArcMachineId+'?api-version=2024-07-10') -Method GET).Content | ConvertFrom-Json
if($machine.identity.type -notlike '*SystemAssigned*' -or $machine.properties.status -ne 'Connected'){throw 'Connected Arc machine with system-assigned identity required'}
if($machine.properties.osType -ine $OperatingSystem){throw 'Arc OS does not match worker group'}
$url=$account.properties.automationHybridServiceUrl
if(-not $url -or ([uri]$url).Scheme -ne 'https'){throw 'Automation hybrid service URL unavailable'}
$group=if($WorkerGroupName){$WorkerGroupName}elseif($OperatingSystem -eq 'Windows'){'windows-operations'}else{'linux-operations'}
$workerPath=$AutomationAccountId+'/hybridRunbookWorkerGroups/'+$group+'/hybridRunbookWorkers/'+$WorkerId
$extensionPath=$ArcMachineId+'/extensions/HybridWorkerExtension'
if($PSCmdlet.ShouldProcess($ArcMachineId,('Register '+$group+' worker and install Hybrid Worker extension'))) {
    $worker=@{properties=@{vmResourceId=$ArcMachineId}} | ConvertTo-Json -Depth 5
    $null=Invoke-CheckedArm -Path ($workerPath+'?api-version=2023-11-01') -Method PUT -Payload $worker
    $extension=@{location=$machine.location;properties=@{publisher='Microsoft.Azure.Automation.HybridWorker';type=('HybridWorkerFor'+$OperatingSystem);typeHandlerVersion='1.1';autoUpgradeMinorVersion=$true;enableAutomaticUpgrade=$true;settings=@{AutomationAccountURL=$url}}} | ConvertTo-Json -Depth 8
    $null=Invoke-CheckedArm -Path ($extensionPath+'?api-version=2024-07-10') -Method PUT -Payload $extension
    [pscustomobject]@{WorkerId=$WorkerId;Group=$group;Status='Submitted; verify extension provisioning and heartbeat before jobs'}
}
# Persist and reuse WorkerId. No schedules or operator role assignments are created.
