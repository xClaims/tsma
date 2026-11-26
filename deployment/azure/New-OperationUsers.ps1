#Requires -Version 7.4
# SPDX-License-Identifier: Apache-2.0
<#
.SYNOPSIS
Create cloud-only Azure Automation project users from a reviewed CSV.
.DESCRIPTION
Requires an existing Graph connection in the specified tenant. Does not grant
licenses, group membership, Entra roles or Azure RBAC. Existing users are reported
without modification. Prompts for a separate initial password per new account.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')]
param(
    [Parameter(Mandatory)][guid]$TenantId,
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9.-]+[A-Za-z0-9]$')][string]$UpnDomain,
    [string]$CsvPath = (Join-Path $PSScriptRoot 'Operation-Users.example.csv')
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$graphModules = @('Microsoft.Graph.Authentication','Microsoft.Graph.Users','Microsoft.Graph.Identity.DirectoryManagement')
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
    throw 'No common installed Graph version exists for Authentication, Users and Identity.DirectoryManagement. Install a matching set, then start a fresh pwsh -NoProfile process.'
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
    throw 'Graph module import failed before provisioning. Start a fresh pwsh -NoProfile process with matching Graph modules; no users were created by this invocation.'
}
$context = Get-MgContext
if ($null -eq $context -or $context.TenantId -ne $TenantId.ToString()) {
    throw 'Connect Microsoft Graph to the intended tenant before provisioning.'
}
$domains = @(Get-MgDomain -All -Property Id,IsVerified,AuthenticationType)
$domain = @($domains | Where-Object { $_.Id -ieq $UpnDomain })
if ($domain.Count -ne 1 -or -not $domain[0].IsVerified -or $domain[0].AuthenticationType -ne 'Managed') {
    throw 'Use a verified managed UPN domain, preferably the tenant onmicrosoft.com domain.'
}
$rows = @(Import-Csv -LiteralPath $CsvPath)
if ($rows.Count -eq 0) { throw 'The user CSV is empty.' }
$required = @('UserName','DisplayName','AssignedTo','Purpose','SuggestedGroup')
$columns = @($rows[0].PSObject.Properties.Name)
foreach ($name in $required) {
    if ($columns -notcontains $name) { throw "CSV column missing: $name" }
}
$seen = @{}
foreach ($row in $rows) {
    foreach ($name in $required) {
        if ([string]::IsNullOrWhiteSpace($row.$name)) { throw "CSV has an empty $name value." }
    }
    if ($row.UserName -notmatch '^azaut-(dir|srv|pub|adm|aud)-[0-9]{2,3}$') {
        throw 'Use azaut-<role>-<number>, for example azaut-dir-01; roles: dir, srv, pub, adm, aud.'
    }
    if ($row.DisplayName.Length -gt 256 -or $row.Purpose.Length -gt 128) { throw 'DisplayName or Purpose is too long.' }
    if ($seen.ContainsKey($row.UserName)) { throw "Duplicate username: $($row.UserName)" }
    $seen[$row.UserName] = $true
}
# Resolve all existing objects before starting writes. A conflicting source/type
# must not be silently repurposed as an Operation identity.
$existing = @{}
foreach ($row in $rows) {
    $upn = $row.UserName + '@' + $UpnDomain.ToLowerInvariant()
    $escapedUpn = $upn.Replace("'", "''")
    $found = @(Get-MgUser -Filter "userPrincipalName eq '$escapedUpn'" -All -Property Id,DisplayName,UserPrincipalName,UserType,OnPremisesSyncEnabled)
    if ($found.Count -gt 1) { throw "Ambiguous UPN: $upn" }
    if ($found.Count -eq 1) {
        if ($found[0].UserType -ne 'Member' -or $found[0].OnPremisesSyncEnabled -eq $true) {
            throw "Existing user is not a cloud-only member: $upn"
        }
        $existing[$upn] = $found[0]
    }
}
foreach ($row in $rows) {
    $upn = $row.UserName + '@' + $UpnDomain.ToLowerInvariant()
    if ($existing.ContainsKey($upn)) {
        $user = $existing[$upn]
        [pscustomobject]@{UserPrincipalName=$upn; ObjectId=$user.Id; Status='ExistingUnchanged'; AssignedTo=$row.AssignedTo; SuggestedGroup=$row.SuggestedGroup}
        continue
    }
    if (-not $PSCmdlet.ShouldProcess($upn, 'Create enabled cloud-only user; no permissions or licenses')) {
        [pscustomobject]@{UserPrincipalName=$upn; ObjectId=$null; Status='NotCreated'; AssignedTo=$row.AssignedTo; SuggestedGroup=$row.SuggestedGroup}
        continue
    }
    $initialPassword = $null
    $plainPassword = $null
    $body = $null
    try {
        $initialPassword = Read-Host "Enter a unique initial password for $upn (hidden)" -AsSecureString
        if ($initialPassword.Length -lt 16) { throw 'Use an initial password of at least 16 characters.' }
        $plainPassword = ConvertFrom-SecureString -SecureString $initialPassword -AsPlainText
        $body = @{
            accountEnabled = $true
            displayName = $row.DisplayName
            mailNickname = $row.UserName
            userPrincipalName = $upn
            userType = 'Member'
            department = 'Operation Automation'
            jobTitle = $row.Purpose
            passwordProfile = @{
                password = $plainPassword
                forceChangePasswordNextSignIn = $true
            }
        }
        try {
            $user = New-MgUser -BodyParameter $body -ErrorAction Stop
        } catch {
            # Do not propagate SDK error/request objects that could contain the password body.
            throw "User creation failed for $upn. Verify the user in Entra before retrying; no request body is printed."
        }
        [pscustomobject]@{UserPrincipalName=$upn; ObjectId=$user.Id; Status='Created'; AssignedTo=$row.AssignedTo; SuggestedGroup=$row.SuggestedGroup}
    } finally {
        if ($null -ne $body) {
            $body.passwordProfile.password = $null
            $body.Clear()
        }
        $plainPassword = $null
        if ($null -ne $initialPassword) { $initialPassword.Dispose() }
    }
}
