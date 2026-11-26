#Requires -Version 7.4
# SPDX-License-Identifier: Apache-2.0
Set-StrictMode -Version Latest
function Get-ValidationLdapConnection {
    param([string]$DomainController)
    $identifier=[DirectoryServices.Protocols.LdapDirectoryIdentifier]::new($DomainController,636,$true,$false)
    [DirectoryServices.Protocols.LdapConnection]::new($identifier)
}
function Invoke-ValidationLdapRead {
    <#
    .SYNOPSIS
    Bind to the configured DC using the mapped account and read its own object.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)][pscredential]$Credential,
        [Parameter(Mandatory)][string]$DomainController,
        [Parameter(Mandatory)][string]$DistinguishedName,
        [Parameter(Mandatory)][string]$UserName,
        [Parameter(Mandatory)][string]$ExecutionIdentity)
    $ErrorActionPreference='Stop'
    $connection=$null
    $networkCredential=$null
    $stage='Setup'
    $target=$DistinguishedName
    try {
        if($Credential.UserName -cne $ExecutionIdentity){throw 'Unexpected identity'}
        Add-Type -AssemblyName System.DirectoryServices.Protocols -ErrorAction Stop
        $connection=Get-ValidationLdapConnection -DomainController $DomainController
        $connection.Timeout=[TimeSpan]::FromSeconds(15)
        $connection.AutoBind=$false
        $connection.AuthType=[DirectoryServices.Protocols.AuthType]::Basic
        $connection.SessionOptions.ProtocolVersion=3
        $connection.SessionOptions.SecureSocketLayer=$true
        $connection.SessionOptions.ReferralChasing=[DirectoryServices.Protocols.ReferralChasingOptions]::None
        # Use standard Windows certificate/hostname validation. Never install an accept-all callback.
        # An explicit nonempty credential prevents ambient SYSTEM/machine-account fallback.
        $networkCredential=[Net.NetworkCredential]::new($target,$Credential.Password)
        $stage='Bind'
        $connection.Bind($networkCredential)
        $stage='Read'
        $request=[DirectoryServices.Protocols.SearchRequest]::new($target,'(objectClass=user)',[DirectoryServices.Protocols.SearchScope]::Base,[string[]]@('distinguishedName','sAMAccountName'))
        $request.SizeLimit=1
        $request.TimeLimit=[TimeSpan]::FromSeconds(10)
        $response=$connection.SendRequest($request,[TimeSpan]::FromSeconds(15))
        if($response.ResultCode -ne [DirectoryServices.Protocols.ResultCode]::Success -or $response.Entries.Count -ne 1){throw 'Unexpected result'}
        $entry=$response.Entries[0]
        if($entry.DistinguishedName -ine $target -or $null -eq $entry.Attributes['sAMAccountName'] -or [string]$entry.Attributes['sAMAccountName'][0] -cne $UserName){throw 'Unexpected object'}
        [pscustomobject]@{DomainController=$DomainController;Port=636;TlsRequired=$true;ADAuthenticationTested=$true;ADAuthenticated=$true;ObjectRead=$true;Target=$target;AttributesRead=@('distinguishedName','sAMAccountName');DirectoryChangesRequested=$false}
    } catch {
        # Deliberately omit raw provider/LDAP exceptions and server diagnostics.
        throw ('RUNBOOK_LDAPS_'+$stage.ToUpperInvariant()+'_FAILED')
    } finally {
        if($null -ne $connection){$connection.Dispose()}
        $networkCredential=$null
    }
}
Export-ModuleMember -Function Invoke-ValidationLdapRead
