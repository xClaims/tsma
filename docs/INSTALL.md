# Install and validate the Windows TSMA runtime

This is the worker-runtime stage of a clean installation. Start with the infrastructure and identities selected for your environment. Start at [Getting started](GETTING-STARTED.md) if Azure, AD, certificates, the worker or vault are not yet prepared.

## Before running these commands

Complete these stages or verify their equivalent in your own environment:

1. [AD accounts/delegation](setup/AD-DIRECTORY.md).
2. [Certificates and LDAPS](setup/CERTIFICATES-LDAPS.md).
3. [OpenBao installation](setup/OPENBAO-SERVER.md) and [LDAP rotation](setup/OPENBAO-LDAP.md).
4. [Azure Automation/Arc worker](setup/AZURE-WORKER.md), including a successful SYSTEM identity job.
5. [Entra/OpenBao trust](setup/ENTRA-OPENBAO.md) and a prepared provider configuration containing your real values.

**Run on:** the actual Windows worker, in an elevated PowerShell 7 terminal. Copy/clone the complete repository to C:\Code\tsma on that machine. Creating files on your workstation does not deploy them to the worker. Keep private configuration outside Git. Administrative scripts do not run through the operator's runbook interface.

## 1. Install protected code

~~~powershell
Set-Location C:\Code\tsma
.\deployment\Install-WindowsWorker.ps1 -WhatIf
.\deployment\Install-WindowsWorker.ps1
~~~

The fixed runtime is C:\ProgramData\TSMA. Let the installer create it; do not pre-create it with a standard user account. New runtime directories are created with protected permissions and local Administrators ownership. Existing runtime paths must already be owned by SYSTEM or local Administrators and allow access only to those principals; the root ACL must also be protected. Unsafe existing ownership/access is rejected before copying code. The script installs the src tree, creates Config/Evidence parents and protects access for SYSTEM/local Administrators. On an approved update, ownership and permissions of trusted retained configuration/evidence are normalized without changing their contents. It does not create Azure resources, grant AD rights, copy example configuration or enable writes. If an installation already exists, stop and use [maintenance/update procedures](OPERATIONS.md); do not add MaintenanceAcknowledged merely to bypass the check.

Verify the files and parent ACLs:

~~~powershell
Test-Path C:\ProgramData\TSMA\src\contracts\RunbookVault.psm1
Test-Path C:\ProgramData\TSMA\src\vaults\openbao\OpenBao.psm1
Get-Acl C:\ProgramData\TSMA | Format-List Owner,AreAccessRulesProtected,AccessToString
Get-Acl C:\ProgramData\TSMA\Config | Format-List Owner,AreAccessRulesProtected,AccessToString
~~~

Ordinary operators must not be local administrators or have write/delete-child rights on the runtime/parents. The supported Arc identity adapter runs as SYSTEM; do not configure a Hybrid Worker custom credential account for this route.

## 2. Install the nonsecret provider configuration

Prepare C:\SecureConfig\OperationDirectory.json from examples/OperationDirectory.example.json as described in [the trust guide](setup/ENTRA-OPENBAO.md). Replace every example vault/domain/app/account value. This file contains no account password, root token or SecretID.

~~~powershell
.\deployment\Set-WorkerVaultConfiguration.ps1 -ConfigurationPath C:\SecureConfig\OperationDirectory.json -WhatIf
.\deployment\Set-WorkerVaultConfiguration.ps1 -ConfigurationPath C:\SecureConfig\OperationDirectory.json
Test-Path C:\ProgramData\TSMA\Config\Vault-OperationDirectory.json
Get-Acl C:\ProgramData\TSMA\Config\Vault-OperationDirectory.json | Format-List Owner,AreAccessRulesProtected,AccessToString
~~~

Expect protected ACLs with SYSTEM and local Administrators only. Existing live config is not overwritten. Validation checks structure and example values; no vault authentication occurs during this command. The filename is provider-neutral even though OpenBao is the currently implemented provider.

## 3. Generate the reviewed directory policy

Use your actual DC, Tier 0 DN, execution account and scope review reference. The review is an accountable approval of directory scope/protected inventory, not a claim to validate a ticket-system approval automatically.

~~~powershell
.\deployment\azure\Initialize-DirectoryGroupMembership.ps1 -DomainController dc01.ad.example.com -Tier0DistinguishedName 'OU=Tier 0,OU=Admin,DC=ad,DC=example,DC=com' -ExecutionAccount svc-op-directory -ScopeReviewReference CHG-YOUR-REVIEW -ReviewDays 7 -MaximumPasswordAgeSeconds 86400 -MinimumRemainingLifetimeSeconds 2100 -WritesEnabled $false -WhatIf
~~~

Replace example values; review then run the same command without WhatIf. The script resolves real domain/account/OU identities, creates a protected DirectoryGroupMembership.json, evidence directory and TSMA Application event source. It grants no AD permission. Include AdditionalProtectedObjectGuids for reviewed powerful identities/application groups outside excluded roots.

Verify the resulting fields:

~~~powershell
$policy=Get-Content C:\ProgramData\TSMA\Config\DirectoryGroupMembership.json -Raw | ConvertFrom-Json
$policy | Select-Object DomainController,DomainDistinguishedName,Tier0DistinguishedName,ExecutionIdentity,MaximumPasswordAgeSeconds,MinimumRemainingLifetimeSeconds,ReviewExpiresUtc,WritesEnabled
Get-Acl C:\ProgramData\TSMA\Config\DirectoryGroupMembership.json | Format-List AreAccessRulesProtected,AccessToString
~~~

Expect WritesEnabled=False. ExecutionIdentity must match the vault mapping; the age limit must match the static-role interval. The policy pins both Tier 0 and Domain Controllers OU GUIDs. Scope review expires deliberately; renew only after scope/inventory review.

## 4. Import and publish diagnostic entry points

On the management workstation/browser, use Automation account -> Runbooks -> Import a runbook. Select each local repository .ps1, type PowerShell, intended Runtime Environment, then review and Publish. Importing source does not automatically deploy its dependencies: those are the files installed on the worker above.

| Runbook | Expected positive result |
| --- | --- |
| Get-WindowsWorkerIdentity | Intended computer, SYSTEM SID S-1-5-18, intended runtime |
| Get-WindowsServiceHealth | Selected local service status; no vault requirement |
| Test-OperationDirectoryAccess | ArcManagedIdentity, mapped AD credential, ADObjectRead=True |
| Test-WindowsOpenBaoLdapAuthentication | Certificate-validated LDAPS bind/read; ADAuthenticated=True |
| Test-OperationDirectoryAuthorization | AllPassed=True and FailedCount=0 for scoped capabilities and actual denied GETs |
| Test-ArcOpenBaoBoundaries | Five rejected JWT cases, after isolated negative roles have been installed |
| Get-WindowsWorkerJobContext | Safe metadata-shape diagnostics; missing Azure job ID is not guessed |

Start each with Run on=Hybrid Worker and the actual group from your worksheet, not the Azure sandbox. The diagnostic probes have no operator-supplied credentials. Inspect Errors/Warnings and Output, not only job status. Retain sanitized results. Configure [named operator access](setup/OPERATOR-ACCESS.md) before testing the same invocation as a nonadministrator.

## 5. First authorized operation

Publish runbooks/windows/Add-DirectoryGroupMember.ps1 using the same supported runtime. With the ordinary acceptance user/group prepared earlier, start Preview=True and a real change reference. Keep writes disabled until the acceptance checklist passes. Then follow [the first-operation procedure](ADD-DIRECTORY-GROUP-MEMBER.md) to enable persistent writes, perform one authorized change and prove AlreadyMember on repeat.

Read [validation](VALIDATION.md) and [maintenance/recovery](OPERATIONS.md) before starting mutation. This package uses a local lock, not a distributed rotation coordinator. When replacing an installed deployment, use the [upgrade procedure](MIGRATION.md) to prevent concurrent consumers.

## 6. Optional finite read-only schedule

After on-demand health succeeds, an authorized Azure administrator may create a finite hourly schedule. On the management workstation, select the correct Az context and use real values:

~~~powershell
Set-Location C:\Code\tsma
$start=[DateTimeOffset]::UtcNow.AddMinutes(15)
.\deployment\azure\New-HealthSchedule.ps1 -SubscriptionId '<your-subscription-guid>' -ResourceGroupName '<your-resource-group>' -AutomationAccountName '<your-account>' -OperatingSystem Windows -WorkerGroupName '<your-worker-group>' -Owner '<accountable-owner>' -AuthorizationReference CHG-HEALTH -StartTime $start -ExpiryTime $start.AddDays(1) -WhatIf
~~~

Review then apply without WhatIf. Confirm the published Get-WindowsServiceHealth job completes on schedule, with the expected Run on group. This is not a schedule for privileged writes or credential rotation. Monitor costs and remove/expire unneeded schedules under normal administration.

For an existing deployment, follow [24-hour rotation migration](CREDENTIAL-ROTATION.md) rather than editing one interval in isolation. The vault role, vault mapping and directory policy must agree.
