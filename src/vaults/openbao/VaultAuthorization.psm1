#Requires -Version 7.4
# SPDX-License-Identifier: Apache-2.0
Set-StrictMode -Version Latest
function Test-OperationDirectoryVaultAuthorization {
    <#
    .SYNOPSIS
    Inspect exact worker capabilities and perform harmless denied GET probes.
    .DESCRIPTION
    Request is a code-owned adapter to the existing RunbookVault request helper.
    Only POST sys/capabilities-self and three GETs are issued. Never posts to a
    rotation, configuration, policy or JWT management endpoint.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][scriptblock]$Request)
    $checks=[Collections.Generic.List[object]]::new()
    $expected=[ordered]@{
        'ldap-operation/static-role/operation-directory'='read'
        'ldap-operation/static-cred/operation-directory'='read'
        'sys/capabilities-self'='update'
        'ldap-mes/static-role/mes-validation'='deny'
        'ldap-mes/static-cred/mes-validation'='deny'
        'ldap-operation/config'='deny'
        'ldap-operation/rotate-role/operation-directory'='deny'
        'ldap-operation/rotate-root'='deny'
        'ldap-operation/static-role/other-account'='deny'
        'ldap-operation/static-cred/other-account'='deny'
        'sys/policies/acl/operation-directory-worker'='deny'
        'sys/mounts/ldap-operation'='deny'
    }
    $expected['auth/jwt-arc/config']='deny'
    $expected['auth/jwt-arc/role/operation-directory-worker01']='deny'
    $expected['sys/auth/jwt-arc']='deny'
    $capabilityResponse=$null
    $queryFailure=$null
    try {
        $capabilityResponse=& $Request 'sys/capabilities-self' 'Post' @{paths=[string[]]@($expected.Keys)}
    } catch {
        $message=$_.Exception.Message
        $queryFailure=if($message -match '^RUNBOOK_VAULT_REQUEST_FAILED_([0-9]{3})$'){'CapabilitiesHTTP'+$Matches[1]}else{'CapabilitiesUnavailable'}
    }
    $data=$capabilityResponse
    if($null -ne $capabilityResponse){
        if($capabilityResponse -is [Collections.IDictionary]){
            if($capabilityResponse.Contains('data')){$data=$capabilityResponse['data']}
        }elseif($null -ne $capabilityResponse.PSObject.Properties['data']){$data=$capabilityResponse.data}
    }
    foreach($path in $expected.Keys){
        $entry=$null
        $found=$false
        if($null -ne $data){
            if($data -is [Collections.IDictionary]){
                if($data.Contains($path)){$found=$true;$entry=$data[$path]}
            }elseif($null -ne $data.PSObject.Properties[$path]){
                $found=$true;$entry=$data.PSObject.Properties[$path].Value
            }
        }
        $values=@($entry)
        $valid=$found -and $values.Count -eq 1 -and $values[0] -is [string]
        $passed=$valid -and $values[0] -ceq $expected[$path]
        $observed=if($queryFailure){$queryFailure}elseif(-not $valid){'MissingOrMalformedCapabilities'}else{($values -join ',')}
        $checks.Add([pscustomobject]@{Check='Capabilities';Path=$path;Expected=$expected[$path];Observed=$observed;Passed=[bool]$passed})
    }
    $deniedGets=@('ldap-mes/static-role/mes-validation','ldap-operation/config','auth/jwt-arc/role/operation-directory-worker01')
    foreach($path in $deniedGets){
        $observed='UnexpectedSuccess'
        $passed=$false
        try {
            # Discard response bodies even if an overprivileged token succeeds.
            $null=& $Request $path 'Get' $null
        } catch {
            $message=$_.Exception.Message
            if($message -match '^RUNBOOK_VAULT_REQUEST_FAILED_([0-9]{3})$'){
                $observed='HTTP'+$Matches[1]
                $passed=$Matches[1] -eq '403'
            }else{$observed='RequestUnavailable'}
        }
        $checks.Add([pscustomobject]@{Check='DeniedGET';Path=$path;Expected='HTTP403';Observed=$observed;Passed=[bool]$passed})
    }
    $failed=@($checks | Where-Object { -not $_.Passed }).Count
    [pscustomobject]@{AllPassed=($failed -eq 0);CheckCount=$checks.Count;FailedCount=$failed;Checks=@($checks.ToArray())}
}
Export-ModuleMember -Function Test-OperationDirectoryVaultAuthorization
