#Requires -Version 7.4
# SPDX-License-Identifier: Apache-2.0
<#
.SYNOPSIS
Add AzAUT cloud-only users to their reviewed SuggestedGroup memberships.
.DESCRIPTION
Reads Operation-Users.example.csv. Resolves every selected user and group before
writing. Requires an existing Graph connection. Does not create users/groups,
remove memberships, assign licenses, or create Azure/Entra role assignments.
#>
[CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')]
param(
    [Parameter(Mandatory)][guid]$TenantId,
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9.-]+[A-Za-z0-9]$')][string]$UpnDomain,
    [string]$CsvPath = (Join-Path $PSScriptRoot 'Operation-Users.example.csv'),
    [ValidatePattern('^azaut-(dir|srv|pub|adm|aud)-[0-9]{2,3}$')][string[]]$UserName
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$graphModules = @('Microsoft.Graph.Authentication','Microsoft.Graph.Users','Microsoft.Graph.Groups')
$installedGraph = @(Get-Module -ListAvailable -Name $graphModules)
$loadedAuthentication = @(Get-Module -Name Microsoft.Graph.Authentication)
if ($loadedAuthentication.Count -gt 1) {
    throw 'Multiple Graph Authentication versions are loaded. Start a fresh pwsh -NoProfile process.'
}
$commonVersions = @(
    $installedGraph | Where-Object Name -eq Microsoft.Graph.Authentication |
        Select-Object -ExpandProperty Version -Unique |
        Sort-Object -Descending |
        Where-Object {
            $candidate = $_
            @($graphModules | Where-Object {
                $moduleName = $_
                -not @($installedGraph | Where-Object { $_.Name -eq $moduleName -and $_.Version -eq $candidate }).Count
            }).Count -eq 0
        }
)
if ($loadedAuthentication.Count -eq 1) {
    $selectedVersion = $loadedAuthentication[0].Version
    if ($commonVersions -notcontains $selectedVersion) {
        throw 'The loaded Graph Authentication version is not installed for all three required modules. Install a matching set, then start a fresh pwsh -NoProfile process.'
    }
} elseif ($commonVersions.Count) {
    $selectedVersion = $commonVersions[0]
} else {
    throw 'No common installed Graph version exists for Authentication, Users and Groups. Install a matching set, then start a fresh pwsh -NoProfile process.'
}
foreach ($moduleName in $graphModules) {
    $loaded = @(Get-Module -Name $moduleName)
    if (@($loaded | Where-Object Version -ne $selectedVersion).Count) {
        throw 'Conflicting Graph modules are loaded. Start a fresh pwsh -NoProfile process and import a matching set.'
    }
}
try {
    foreach ($moduleName in $graphModules) {
        Import-Module -Name $moduleName -RequiredVersion $selectedVersion -ErrorAction Stop
    }
} catch {
    throw 'Graph module import failed before membership updates. Start a fresh pwsh -NoProfile process with matching Graph modules; no memberships were changed by this invocation.'
}
$context = Get-MgContext
if ($null -eq $context -or $context.TenantId -ne $TenantId.ToString()) {
    throw 'Connect Microsoft Graph to the intended tenant before changing memberships.'
}
if ($context.Environment -ne 'Global') {
    throw 'This script uses Microsoft Graph Global endpoints. Other clouds require reviewed endpoint configuration.'
}
$roleGroups = @{
    dir='sg-operation-directory-operators'
    srv='sg-operation-server-operators'
    pub='sg-operation-runbook-publishers'
    adm='sg-operation-platform-administrators'
    aud='sg-operation-automation-auditors'
}
$rows = @(Import-Csv -LiteralPath $CsvPath)
if (-not $rows.Count) { throw 'The user CSV is empty.' }
foreach ($column in @('UserName','SuggestedGroup','AssignedTo')) {
    if (@($rows[0].PSObject.Properties.Name) -notcontains $column) { throw "CSV column missing: $column" }
}
$seen = @{}
foreach ($row in $rows) {
    if ($row.UserName -notmatch '^azaut-(dir|srv|pub|adm|aud)-[0-9]{2,3}$') {
        throw "Invalid AzAUT username: $($row.UserName)"
    }
    $role = $Matches[1]
    if ($row.SuggestedGroup -cne $roleGroups[$role]) {
        throw "SuggestedGroup does not match the approved role mapping for $($row.UserName)."
    }
    if ($seen.ContainsKey($row.UserName)) { throw "Duplicate username in CSV: $($row.UserName)" }
    $seen[$row.UserName]=$true
}
if ($UserName) {
    foreach ($requestedName in $UserName) {
        if (-not $seen.ContainsKey($requestedName)) { throw "Requested user is not in the CSV: $requestedName" }
    }
    $rows = @($rows | Where-Object { $UserName -contains $_.UserName })
}
# Complete preflight for all selected rows before any membership write.
$plan = [Collections.Generic.List[object]]::new()
$groupCache = @{}
foreach ($row in $rows) {
    $upn=$row.UserName+'@'+$UpnDomain.ToLowerInvariant()
    $escapedUpn=$upn.Replace("'","''")
    $users=@(Get-MgUser -Filter "userPrincipalName eq '$escapedUpn'" -All -Property Id,UserPrincipalName,UserType,OnPremisesSyncEnabled,AccountEnabled)
    if ($users.Count -ne 1) { throw "Expected one existing user: $upn. Run user provisioning or resolve the conflict first." }
    $user=$users[0]
    if ($user.UserType -ne 'Member' -or $user.OnPremisesSyncEnabled -eq $true -or -not $user.AccountEnabled) {
        throw "User must be an enabled cloud-only member: $upn"
    }
    $groupName=$row.SuggestedGroup
    if (-not $groupCache.ContainsKey($groupName)) {
        $groups=@(Get-MgGroup -Filter "displayName eq '$groupName'" -All -Property Id,DisplayName,SecurityEnabled,MailEnabled,GroupTypes,OnPremisesSyncEnabled,IsAssignableToRole)
        if ($groups.Count -ne 1) { throw "Expected one existing group: $groupName. Complete Phase 3 or resolve duplicate names first." }
        $group=$groups[0]
        if (-not $group.SecurityEnabled -or $group.MailEnabled -or $group.OnPremisesSyncEnabled -eq $true -or @($group.GroupTypes).Count -gt 0 -or $group.IsAssignableToRole -eq $true) {
            throw "Group must be a cloud-only assigned security group without Entra role-assignability: $groupName"
        }
        $members=@(Get-MgGroupMember -GroupId $group.Id -All)
        $groupCache[$groupName]=@{Group=$group;MemberIds=@($members | ForEach-Object Id)}
    }
    if ([string]::IsNullOrWhiteSpace($row.AssignedTo) -or $row.AssignedTo -eq 'Unassigned') {
        Write-Warning "$upn has no accountable individual recorded. Update AssignedTo/access records; this label does not enforce ownership."
    }
    $entry=$groupCache[$groupName]
    $plan.Add([pscustomobject]@{
        UserPrincipalName=$upn;UserId=$user.Id;GroupName=$groupName
        GroupId=$entry.Group.Id;AssignedTo=$row.AssignedTo
        Present=($entry.MemberIds -contains $user.Id)
    })
}
foreach ($item in $plan) {
    $status='AlreadyMember'
    if (-not $item.Present) {
        if ($PSCmdlet.ShouldProcess(($item.UserPrincipalName+' -> '+$item.GroupName),'Add direct group membership')) {
            $requestFailed=$false
            try {
                $null=New-MgGroupMemberByRef -GroupId $item.GroupId -BodyParameter @{
                    '@odata.id'='https://graph.microsoft.com/v1.0/directoryObjects/'+$item.UserId
                } -Confirm:$false -ErrorAction Stop
            } catch {
                $requestFailed=$true
            }
            try {
                $after=@(Get-MgGroupMember -GroupId $item.GroupId -All | Where-Object Id -eq $item.UserId)
            } catch {
                throw "Membership verification failed for $($item.UserPrincipalName) in $($item.GroupName). Inspect Entra before rerunning; earlier additions remain."
            }
            if ($after.Count) {
                $status=if($requestFailed){'PresentAfterRequestError'}else{'Added'}
            } elseif ($requestFailed) {
                throw "Membership request failed for $($item.UserPrincipalName) in $($item.GroupName). Inspect permissions and Entra before rerunning; earlier additions remain."
            } else {
                $status='PendingVerification'
                Write-Warning "Membership submitted but not visible yet for $($item.UserPrincipalName). Allow replication and rerun to verify."
            }
        } else {
            $status='NotAdded'
        }
    }
    [pscustomobject]@{
        UserPrincipalName=$item.UserPrincipalName;UserId=$item.UserId
        GroupName=$item.GroupName;GroupId=$item.GroupId
        AssignedTo=$item.AssignedTo;Status=$status
    }
}
