# Create the Azure Automation account and Windows Arc worker

**Run on:** the management workstation for Azure resources, and the Windows worker for agent/runtime installation. This procedure does not depend on a pre-existing Automation account or saved GUID.

## 1. Install administrative tools and select the subscription

Use a new PowerShell 7 terminal. Install modules only from a repository you have verified; answer the trust prompt deliberately. Mixing loaded Az/Graph assembly versions can require a new process, not Remove-Module.

~~~powershell
Install-PSResource -Name Az.Accounts,Az.Resources,Az.Automation -Repository PSGallery -Scope CurrentUser
Import-Module Az.Accounts
Import-Module Az.Resources
Import-Module Az.Automation
$tenantId='<your-tenant-guid>'
$subscriptionId='<your-subscription-guid>'
Connect-AzAccount -Tenant $tenantId -Subscription $subscriptionId
Get-AzContext | Select-Object Tenant,Subscription,Account
~~~

Copy IDs from Azure portal -> Microsoft Entra ID Overview and Subscriptions. They are different GUIDs. Do not copy documentation example IDs. Register these namespaces using an authorized subscription administrator:

~~~powershell
Register-AzResourceProvider -ProviderNamespace Microsoft.Automation
Register-AzResourceProvider -ProviderNamespace Microsoft.HybridCompute
Get-AzResourceProvider -ProviderNamespace Microsoft.Automation | Select-Object ProviderNamespace,RegistrationState
Get-AzResourceProvider -ProviderNamespace Microsoft.HybridCompute | Select-Object ProviderNamespace,RegistrationState
~~~

Wait until Registered before deployment; rerun the read checks. Microsoft.Automation is not an installable PowerShell module. Use [resource-provider documentation](https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/resource-providers-and-types) when authority or registration is blocked.

## 2. Create an account and worker group

The shipped helper creates a new resource group, Automation account and empty Hybrid Worker group. It does not enable paid auxiliary services or register servers. On your workstation, from the repository:

~~~powershell
Set-Location C:\Code\tsma
$location='westus' # Choose an available approved region.
$regionCode='wus' # Naming abbreviation corresponding to that region.
$serviceOwner='Identity Operations' # Replace with your accountable team/person.
$costCenter='YOUR-REAL-COST-CODE'
.\deployment\azure\Deploy-OperationControlPlane.ps1 -SubscriptionId $subscriptionId -Service Directory -Location $location -RegionCode $regionCode -ServiceOwner $serviceOwner -CostCenter $costCenter -WhatIf
~~~

Review, then run the same command without WhatIf. This creates rg-operation-directory-prd-<region>-001, aa-operation-directory-prd-<region>-001 and hwg-operation-directory-prd-<region>-001. These are naming defaults, not existing resources in your tenant and not a production-readiness claim. A different approved region needs a consistent RegionCode.

Read and record the resulting account resource ID and group; do not invent an Automation account ID from a display name:

~~~powershell
$resourceGroup='rg-operation-directory-prd-'+$regionCode+'-001'
$automationAccount='aa-operation-directory-prd-'+$regionCode+'-001'
$workerGroup='hwg-operation-directory-prd-'+$regionCode+'-001'
$accountId=(Get-AzResource -ResourceGroupName $resourceGroup -Name $automationAccount -ResourceType Microsoft.Automation/automationAccounts).ResourceId
Get-AzAutomationHybridRunbookWorkerGroup -ResourceGroupName $resourceGroup -AutomationAccountName $automationAccount
$accountId
~~~

If you already own an appropriate dedicated account/group, inspect and record its actual IDs instead. Do not apply the new-resource helper as a migration shortcut. Add a budget/alerts before recurring jobs.

## 3. Onboard the Windows member server to Arc

In Azure portal -> Azure Arc -> Machines -> Add/Create -> Add a single server, select your subscription, intended resource group, region and Windows operating system. Generate/download the onboarding PowerShell script. Review it, verify its source/signature as applicable, transfer to the worker and run elevated in an interactive terminal. The script installs the Connected Machine agent and connects it using an authorized account. Do not paste script-generated tokens or service-principal secrets into a repository.

Use the normal supported identity configuration. If a generated script selects a preview TPM-backed key store that your subscription has not enabled, regenerate/review the onboarding options instead of registering a preview feature merely to clear the error. Consult the current [agent connect options](https://learn.microsoft.com/en-us/azure/azure-arc/servers/azcmagent-connect).

Verify locally on the worker:

~~~powershell
& "$env:ProgramFiles\AzureConnectedMachineAgent\azcmagent.exe" show
~~~

In Azure, the machine must show Connected and a system-assigned managed identity. Network requirements and onboarding steps are documented in [Arc onboarding](https://learn.microsoft.com/en-us/azure/azure-arc/servers/onboard-portal). Do not continue from a certificate/time error without fixing the clock/trust problem.

Back on the management workstation, read the exact Arc resource and principal ID:

~~~powershell
$arcMachineName='WORKER01' # The actual Arc resource name you just created.
$arcMachineId=(Get-AzResource -ResourceGroupName $resourceGroup -Name $arcMachineName -ResourceType Microsoft.HybridCompute/machines).ResourceId
$arc=(Invoke-AzRestMethod -Path ($arcMachineId+'?api-version=2024-07-10') -Method GET).Content | ConvertFrom-Json
$arcPrincipalId=[string]$arc.identity.principalId
if([string]::IsNullOrWhiteSpace($arcPrincipalId)){throw 'Arc system-assigned principal missing.'}
[pscustomobject]@{ArcResourceId=$arcMachineId;ArcPrincipalId=$arcPrincipalId;Status=$arc.properties.status}
~~~

Record both IDs in your private worksheet. The Arc principal is not the Automation account's managed identity or the human operator.

## 4. Register the Hybrid Worker

For a new registration generate one GUID, record it, then reuse it on retries. An existing registration must reuse its already recorded GUID and group. Review other account/group registrations first.

~~~powershell
$workerId=[guid]::NewGuid().ToString()
$workerId # Record once in your private deployment worksheet.
.\deployment\azure\Register-ArcWorker.ps1 -AutomationAccountId $accountId -ArcMachineId $arcMachineId -OperatingSystem Windows -WorkerId $workerId -WorkerGroupName $workerGroup -WhatIf
~~~

After review, run the same registration command without WhatIf, using the same workerId. Verify HybridWorkerExtension provisioning Succeeded on the Arc machine and the machine's current heartbeat in the Automation account's Hybrid worker groups -> your group -> Hybrid Workers. Submitted does not mean healthy. This is the extension-based worker, not the retired agent-based registration model. See [Hybrid Worker deployment](https://learn.microsoft.com/en-us/azure/automation/extension-based-hybrid-runbook-worker-install).

## 5. Install the execution runtime and AD tools

On the worker, install the selected currently supported PowerShell 7 runtime using Microsoft's [Windows installation instructions](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-windows). Choose a runtime supported by both TSMA and Azure; match the Automation Runtime Environment later. Install RSAT-AD-PowerShell on Windows Server using an elevated administrative shell:

~~~powershell
Install-WindowsFeature RSAT-AD-PowerShell
Import-Module ActiveDirectory
Get-ADDomain -Server dc01.ad.example.com | Select-Object DNSRoot,NetBIOSName
~~~

Replace the DC. For a 7.4 deployment set the documented machine environment variable to that executable; do not point a 7.4 variable at a different installed major/minor version:

~~~powershell
$pwshPath='C:\Program Files\PowerShell\7\pwsh.exe'
$version=& $pwshPath -NoProfile -Command '$PSVersionTable.PSVersion.ToString()'
if(([version]$version).Major -ne 7 -or ([version]$version).Minor -ne 4){throw 'Install/select a real 7.4 executable for this example, or follow the supported 7.6 path instead.'}
[Environment]::SetEnvironmentVariable('powershell_7_4_path',$pwshPath,'Machine')
~~~

Use powershell_7_6_path when choosing a supported 7.6 deployment. Apply environment changes through a planned restart of the worker service or reboot with no jobs running. Service selection depends on the installed extension; a planned worker reboot is the simplest unambiguous refresh. Recheck extension/heartbeat afterward. See [runtime setup](https://learn.microsoft.com/en-us/azure/automation/automation-hrw-run-runbooks).

## 6. Create runtime environment, import and run the first job

In the Automation account -> Runtime Environments -> Create, select PowerShell and the matching supported version. Use a name such as PowerShell-74 or PowerShell-76 (a period is not valid in that environment name). Review/create. Worker modules are installed locally; a cloud Runtime Environment package import does not automatically install the local ActiveDirectory module.

Open Runbooks -> Import a runbook, select runbooks/windows/Get-WindowsWorkerIdentity.ps1, type PowerShell, name Get-WindowsWorkerIdentity. Associate the intended Runtime Environment explicitly, review the source, Publish. Start -> Run on Hybrid Worker -> choose your group. Inspect Jobs -> Output and Errors. Expect the intended host and IdentitySid=S-1-5-18. This probe has no vault inputs. Then import/publish/run Get-WindowsServiceHealth the same way.

If the job remains queued, inspect current heartbeat/extension/runtime and host availability. If only an operator sees a no-active-workers warning while an administrator does not, verify worker read permissions rather than resetting registration blindly. A successful identity probe is the exit condition before [Entra/OpenBao trust](ENTRA-OPENBAO.md).
