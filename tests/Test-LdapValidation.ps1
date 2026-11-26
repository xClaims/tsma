#Requires -Version 7.4
# SPDX-License-Identifier: Apache-2.0
[CmdletBinding()]param()
$ErrorActionPreference='Stop'
$base=Split-Path $PSScriptRoot -Parent
$module=Import-Module (Join-Path $base 'src/operations/LdapValidation/LdapValidation.psm1') -Force -PassThru
$checks=0
function Assert-Check {param([bool]$Ok,[string]$Name) if(-not $Ok){throw $Name};$script:checks++}
function Assert-Denied {param([scriptblock]$Action,[string]$Expected) try{& $Action|Out-Null}catch{Assert-Check ($_.Exception.Message -eq $Expected) $Expected;return};throw ('Expected '+$Expected)}
$secret=[Security.SecureString]::new()
foreach($c in 'TEST-ONLY-NOT-A-REAL-PASSWORD'.ToCharArray()){$secret.AppendChar($c)}
$secret.MakeReadOnly()
$credential=[pscredential]::new('EXAMPLE\svc-op-directory',$secret)
$readParameters=@{DomainController='dc01.ad.example.com';DistinguishedName='CN=svc-op-directory,OU=Service Accounts,OU=Tier 0,OU=Admin,DC=ad,DC=example,DC=com';UserName='svc-op-directory';ExecutionIdentity='EXAMPLE\svc-op-directory'}
try {
    & $module {
        $script:Fixture=@{Failure='';Disposed=0;Bound=0;Read=0;WrongObject=$false}
        function script:Get-ValidationLdapConnection {
            $connection=[pscustomobject]@{Timeout=$null;AutoBind=$true;AuthType=$null;SessionOptions=[pscustomobject]@{ProtocolVersion=0;SecureSocketLayer=$false;ReferralChasing=$null}}
            $connection | Add-Member ScriptMethod Bind {
                param([Net.NetworkCredential]$BindIdentity)
                if(-not $this.SessionOptions.SecureSocketLayer -or $this.AutoBind -or $this.AuthType -ne 'Basic' -or $this.SessionOptions.ReferralChasing -ne 'None' -or $BindIdentity.UserName -ne 'CN=svc-op-directory,OU=Service Accounts,OU=Tier 0,OU=Admin,DC=ad,DC=example,DC=com' -or $BindIdentity.SecurePassword.Length -eq 0){throw 'Invalid bind contract'}
                $script:Fixture.Bound++
                if($script:Fixture.Failure -eq 'Bind'){throw 'SENSITIVE-DIAGNOSTIC-DO-NOT-LOG'}
            }
            $connection | Add-Member ScriptMethod SendRequest {
                param($Request,$Timeout)
                $script:Fixture.Read++
                if($Request -isnot [DirectoryServices.Protocols.SearchRequest] -or $Request.DistinguishedName -ne 'CN=svc-op-directory,OU=Service Accounts,OU=Tier 0,OU=Admin,DC=ad,DC=example,DC=com' -or $Request.Scope -ne 'Base' -or $Request.Filter -ne '(objectClass=user)' -or $Request.SizeLimit -ne 1 -or $Timeout.TotalSeconds -ne 15 -or $Request.Attributes.Count -ne 2){throw 'Invalid read contract'}
                if($script:Fixture.Failure -eq 'Read'){throw 'SENSITIVE-DIAGNOSTIC-DO-NOT-LOG'}
                $dn=if($script:Fixture.WrongObject){'CN=other,DC=ad,DC=example,DC=com'}else{$Request.DistinguishedName}
                [pscustomobject]@{ResultCode='Success';Entries=@([pscustomobject]@{DistinguishedName=$dn;Attributes=@{sAMAccountName=@('svc-op-directory')}})}
            }
            $connection | Add-Member ScriptMethod Dispose {$script:Fixture.Disposed++}
            $connection
        }
    }
    $r=Invoke-ValidationLdapRead -Credential $credential @readParameters
    Assert-Check ($r.ADAuthenticated -and $r.ObjectRead -and -not $r.DirectoryChangesRequested) 'Successful explicit bind and base read'
    Assert-Check ((& $module {$script:Fixture.Disposed}) -eq 1) 'Success disposed'
    & $module {$script:Fixture.Failure='Bind'}
    Assert-Denied {Invoke-ValidationLdapRead -Credential $credential @readParameters} 'RUNBOOK_LDAPS_BIND_FAILED'
    Assert-Check ((& $module {$script:Fixture.Read}) -eq 1) 'No read after failed bind'
    Assert-Check ((& $module {$script:Fixture.Disposed}) -eq 2) 'Bind failure disposed'
    & $module {$script:Fixture.Failure='Read'}
    Assert-Denied {Invoke-ValidationLdapRead -Credential $credential @readParameters} 'RUNBOOK_LDAPS_READ_FAILED'
    Assert-Check ((& $module {$script:Fixture.Disposed}) -eq 3) 'Read failure disposed'
    & $module {$script:Fixture.Failure='';$script:Fixture.WrongObject=$true}
    Assert-Denied {Invoke-ValidationLdapRead -Credential $credential @readParameters} 'RUNBOOK_LDAPS_READ_FAILED'
    $wrong=[pscredential]::new('EXAMPLE\another-account',$secret)
    Assert-Denied {Invoke-ValidationLdapRead -Credential $wrong @readParameters} 'RUNBOOK_LDAPS_SETUP_FAILED'
    Assert-Check ((& $module {$script:Fixture.Bound}) -eq 4) 'Unexpected identity never bound'
    [pscustomobject]@{Checks=$checks;Failed=0;LiveLdapTested=$false}
} finally {$credential=$null;$secret.Dispose();Remove-Module LdapValidation -ErrorAction SilentlyContinue}
