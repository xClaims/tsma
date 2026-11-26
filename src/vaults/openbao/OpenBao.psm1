#Requires -Version 7.4
# SPDX-License-Identifier: Apache-2.0
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '../../platforms/azure/ArcIdentity.ps1')
$script:Vault=$null
function Initialize-RunbookVault {
    <#
    .SYNOPSIS
    Load validated nonsecret configuration for the selected vault provider.
    #>
    [CmdletBinding()]param([Parameter(Mandatory)][string]$ConfigurationPath)
    $script:Vault=$null
    try {
        $c=Get-Content -LiteralPath $ConfigurationPath -Raw -ErrorAction Stop | ConvertFrom-Json
        $uri=[uri]$c.Address
        if ($c.Provider -ne 'OpenBao' -or $uri.Scheme -ne 'https' -or $uri.UserInfo -or $uri.Query -or $uri.Fragment -or $uri.AbsolutePath -ne '/') { throw 'invalid' }
        if ($c.AuthMount -notmatch '^[\w-]+$' -or $c.Mount -notmatch '^[\w-]+$' ) { throw 'invalid' }
        if ($c.TimeoutSeconds -lt 1 -or $c.TimeoutSeconds -gt 60 -or $c.MaximumPasswordAgeSeconds -lt 60 -or $c.MaximumPasswordAgeSeconds -gt 604800) { throw 'invalid' }
        if($c.Authentication -ne 'ArcManagedIdentity' -or $c.JwtRole -notmatch '^[\w-]+$' -or
            $c.ManagedIdentityResource -notmatch '^api://[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'){throw 'invalid'}
        foreach($a in $c.Accounts.PSObject.Properties) {
            if ($a.Name -notmatch '^[\w-]+$' -or $a.Value.Role -notmatch '^[\w-]+$' -or [string]::IsNullOrWhiteSpace($a.Value.UserName) -or [string]::IsNullOrWhiteSpace($a.Value.CredentialUserName) -or [string]::IsNullOrWhiteSpace($a.Value.DistinguishedName)) { throw 'invalid' }
        }
        $script:Vault=@{Config=$c;Authentication=$c.Authentication;Address=$uri.AbsoluteUri.TrimEnd('/');Token=$null;Expires=[DateTimeOffset]::MinValue}
    } catch { throw 'RUNBOOK_VAULT_CONFIG_INVALID' }
}
function Invoke-VaultRequest {
    param([string]$Endpoint,[ValidateSet('Get','Post')][string]$Method='Get',[hashtable]$Payload,[switch]$Anonymous)
    $headers=@{}; $body=$null; $argsMap=$null
    try {
        if(-not $Anonymous){ Connect-WorkerVault; $headers['X-Vault-Token']=$script:Vault.Token }
        $argsMap=@{Uri=$script:Vault.Address+'/v1/'+$Endpoint;Method=$Method;Headers=$headers;TimeoutSec=[int]$script:Vault.Config.TimeoutSeconds;MaximumRedirection=0;ErrorAction='Stop';Verbose=$false;Debug=$false}
        if($null -ne $Payload){$body=ConvertTo-Json $Payload -Compress; $argsMap.Body=[Text.Encoding]::UTF8.GetBytes($body);$argsMap.ContentType='application/json'}
        Invoke-RestMethod @argsMap
    } catch {
        $status='transport'
        if($null -ne $_.Exception.PSObject.Properties['Response'] -and $null -ne $_.Exception.Response){$status=[string][int]$_.Exception.Response.StatusCode}
        throw ('RUNBOOK_VAULT_REQUEST_FAILED_'+$status)
    } finally { $headers.Clear();$body=$null;if($Payload){$Payload.Clear()};if($null -ne $argsMap -and $argsMap.ContainsKey('Body')){[Array]::Clear($argsMap.Body,0,$argsMap.Body.Length)} }
}
function Connect-WorkerVault {
    if($null -eq $script:Vault){throw 'RUNBOOK_VAULT_UNINITIALIZED'}
    if($script:Vault.Token -and [DateTimeOffset]::UtcNow -lt $script:Vault.Expires){return}
    $login=$null;$secret=$null
    try {
        $secret=Get-ArcIdentityToken -Configuration $script:Vault.Config
        $payload=@{role=$script:Vault.Config.JwtRole;jwt=$secret}
        if([string]::IsNullOrWhiteSpace($secret)){throw 'invalid'}
        $login=Invoke-VaultRequest -Endpoint ('auth/'+$script:Vault.Config.AuthMount+'/login') -Method Post -Anonymous -Payload $payload
        if($login.auth.lease_duration -gt 300){throw 'invalid'}
        if(-not $login.auth.client_token -or 'root' -in $login.auth.policies -or $login.auth.lease_duration -le 10){throw 'invalid'}
        $script:Vault.Token=[string]$login.auth.client_token
        $script:Vault.Expires=[DateTimeOffset]::UtcNow.AddSeconds($login.auth.lease_duration-10)
    } catch { $script:Vault.Token=$null;throw 'RUNBOOK_VAULT_AUTH_FAILED' }
    finally {$secret=$null;$login=$null}
}
function Get-AccountMapping {
    param([string]$Reference)
    if($null -eq $script:Vault){throw 'RUNBOOK_VAULT_UNINITIALIZED'}
    $p=$script:Vault.Config.Accounts.PSObject.Properties[$Reference]
    if($null -eq $p){throw 'RUNBOOK_VAULT_REFERENCE_DENIED'}
    $p.Value
}
function Wait-RotationTimestamp {
    param([DateTimeOffset]$Last)
    $seconds=($Last-[DateTimeOffset]::UtcNow).TotalSeconds
    if($seconds -gt 2){throw 'RUNBOOK_VAULT_CLOCK_AHEAD'}
    if($seconds -gt 0){Start-Sleep -Milliseconds ([int][math]::Ceiling($seconds*1000)+10)}
    if($Last -gt [DateTimeOffset]::UtcNow){throw 'RUNBOOK_VAULT_CLOCK_AHEAD'}
}
function Test-RunbookVault {
    <#
    .SYNOPSIS
    Verify mapped account identity, rotation period and credential freshness.
    #>
    [CmdletBinding()]param([string]$Reference='OperationDirectory')
    $a=Get-AccountMapping $Reference
    $r=Invoke-VaultRequest -Endpoint ($script:Vault.Config.Mount+'/static-role/'+$a.Role)
    try {
        if($r.data.username -cne $a.UserName -or $r.data.dn -ine $a.DistinguishedName){throw 'invalid'}
        $period=[string]$r.data.rotation_period
        $expected=[int]$script:Vault.Config.MaximumPasswordAgeSeconds
        if($period -ne [string]$expected -and $period -ne ($expected.ToString()+'s') -and -not ($expected -eq 14400 -and $period -eq '4h')){throw 'invalid'}
        $last=[DateTimeOffset]::Parse($r.data.last_vault_rotation).ToUniversalTime()
    } catch {throw 'RUNBOOK_VAULT_METADATA_INVALID'}
    Wait-RotationTimestamp $last
    if([DateTimeOffset]::UtcNow -ge $last.AddSeconds($expected)){throw 'RUNBOOK_VAULT_ROTATION_OVERDUE'}
    [pscustomobject]@{Reference=$Reference;Healthy=$true;LastRotationUtc=$last.ToString('o');PasswordAgeLimitSeconds=$expected}
}
function Get-RunbookCredential {
    <#
    .SYNOPSIS
    Retrieve a mapped execution credential without writing it to job output.
    #>
    [CmdletBinding()]
    [OutputType([Management.Automation.PSCredential])]
    param([string]$Reference='OperationDirectory')
    $a=Get-AccountMapping $Reference
    $null=Test-RunbookVault $Reference
    $r=$null
    try {
        $r=Invoke-VaultRequest -Endpoint ($script:Vault.Config.Mount+'/static-cred/'+$a.Role)
        if($r.data.username -cne $a.UserName -or $r.data.password -isnot [string] -or [string]::IsNullOrEmpty($r.data.password)){throw 'invalid'}
        $last=[DateTimeOffset]::Parse($r.data.last_vault_rotation).ToUniversalTime()
        Wait-RotationTimestamp $last
        if([DateTimeOffset]::UtcNow -ge $last.AddSeconds([int]$script:Vault.Config.MaximumPasswordAgeSeconds)){throw 'invalid'}
        $secure=[Security.SecureString]::new()
        foreach($character in $r.data.password.ToCharArray()){$secure.AppendChar($character)}
        $secure.MakeReadOnly()
        [pscredential]::new($a.CredentialUserName,$secure)
    } catch {throw 'RUNBOOK_VAULT_CREDENTIAL_UNAVAILABLE'}
    finally {$r=$null}
}
function Close-RunbookVault {
    <#
    .SYNOPSIS
    Forget local vault state; does not rotate passwords or revoke sessions.
    #>
    [CmdletBinding()]param()
    # Forget token locally. It expires server-side; this is not rotation/check-in.
    if($null -ne $script:Vault){$script:Vault.Token=$null;$script:Vault=$null}
}
Export-ModuleMember -Function Initialize-RunbookVault,Test-RunbookVault,Get-RunbookCredential,Close-RunbookVault
