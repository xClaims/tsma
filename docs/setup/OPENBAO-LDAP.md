# Configure AD password management in OpenBao

**Run on:** the vault administrator's private interactive session and a Windows management host with trusted vault HTTPS. Requires the accounts/delegation from [AD setup](AD-DIRECTORY.md) and the public DC CA chain from [certificates](CERTIFICATES-LDAPS.md).

The reconciliation account authenticates OpenBao to AD and can reset only the intended execution account. The Arc worker later reads the execution credential; it cannot configure this engine or request rotation.

## 1. Enable the LDAP secrets engine

In the authenticated bao administrator shell, inspect first:

~~~sh
bao plugin list -detailed secret
bao secrets list -detailed
~~~

Only when ldap-operation/ is absent, enable the installed plugin version. The following version was exercised with this code; substitute the compatible version you selected:

~~~sh
bao secrets enable -path=ldap-operation -plugin-version=v0.1.0 ldap
~~~

plugin not found means resolve the catalog/registration first. Do not switch to the LDAP authentication engine; this is the LDAP secrets engine. Existing mounts are inspected rather than overwritten.

## 2. Write LDAP configuration without logging credentials

On the Windows management host in PowerShell 7, copy the public DC CA chain to C:\SecureConfig\dc-ca-chain.pem. It must be PEM text containing BEGIN CERTIFICATE. For a single-tier CA the public root can be the same trust anchor used for the vault, but verify the chain actually issued the DC certificate.

Use a vault administrator token authorized to configure this mount and the actual reconciliation account password. Do not run this block inside a transcript or print its body/headers. Run the entire block, replacing addresses/DNs:

~~~powershell
& {
    $ErrorActionPreference='Stop'
    $baoAddress='https://bao.example.com:8200'
    $bindCredential=Get-Credential 'svc-pam-rec-dsop@ad.example.com'
    $tokenSecret=Read-Host 'Authorized OpenBao administrator token' -AsSecureString
    $tokenCredential=[pscredential]::new('token',$tokenSecret)
    $headers=@{'X-Vault-Token'=$tokenCredential.GetNetworkCredential().Password}
    $body=$null;$payload=$null
    try {
        $certificate=[string][IO.File]::ReadAllText('C:\SecureConfig\dc-ca-chain.pem')
        if($certificate -notmatch '-----BEGIN CERTIFICATE-----'){throw 'PEM certificate required.'}
        $payload=@{
            schema='ad'
            url='ldaps://dc01.ad.example.com:636'
            binddn=$bindCredential.UserName
            bindpass=$bindCredential.GetNetworkCredential().Password
            userdn='OU=Service Accounts,OU=Tier 0,OU=Admin,DC=ad,DC=example,DC=com'
            userattr='sAMAccountName'
            certificate=$certificate
            insecure_tls=$false
        }
        $body=$payload | ConvertTo-Json -Depth 5 -Compress
        $null=Invoke-RestMethod -Uri ($baoAddress+'/v1/ldap-operation/config') -Method Post -Headers $headers -Body ([Text.Encoding]::UTF8.GetBytes($body)) -ContentType 'application/json' -TimeoutSec 30 -ErrorAction Stop
        'LDAP configuration request succeeded; verify metadata and an authorized rotation separately.'
    } catch {
        $status='transport'
        if($null -ne $_.Exception.PSObject.Properties['Response'] -and $null -ne $_.Exception.Response){$status=[string][int]$_.Exception.Response.StatusCode}
        throw ('LDAP configuration failed; status='+$status+'. Inspect protected server diagnostics without printing the request.')
    } finally {
        if($null -ne $payload){$payload.bindpass=$null;$payload.Clear()}
        $body=$null;$headers.Clear();$tokenCredential=$null
        $tokenSecret.Dispose();$bindCredential.Password.Dispose();$bindCredential=$null
    }
}
~~~

The secrets temporarily exist in process memory; setting variables to null is not a secure-erasure guarantee. HTTPS and administrator workstation protection are still required. User principal name is valid for the AD bind identity when the account/UPN is correct. userdn is the search base, not the bind account name. The API path /v1/ldap-operation/config is a REST endpoint, not a file/folder to browse.

HTTP 204 indicates a successful write. In the bao shell:

~~~sh
bao read ldap-operation/config
~~~

Expect the correct URL, schema, base and attribute; do not publish the full response without reviewing sensitive environment information. The bind password should not be returned. A configuration write alone is not proof of a successful bind/reset.

## 3. Create the static role

First confirm the actual execution DN with Get-ADUser on your management host. In the authorized bao shell, create the role once:

~~~sh
bao write ldap-operation/static-role/operation-directory dn='CN=svc-op-directory,OU=Service Accounts,OU=Tier 0,OU=Admin,DC=ad,DC=example,DC=com' username='svc-op-directory' rotation_period=24h
bao read ldap-operation/static-role/operation-directory
~~~

Initial creation can immediately change the AD password. Do not manage an account currently used by unrelated services. Expect username, correct dn, rotation_period=24h and a recent last_vault_rotation. Never run bao read ldap-operation/static-cred/operation-directory in a recorded terminal: it returns the password. TSMA retrieves it in memory during later probes.

Record last_vault_rotation and later observe it advance after the independent interval without a manual rotation. Keep the vault running, unsealed and time-synchronized. A successful manual rotate-role call does not validate the timer. Reconciliation failure requires an administrator to inspect bind expiry, permissions, policy, TLS and account identity.

Existing installations must use the [coordinated maintenance procedure](../CREDENTIAL-ROTATION.md) to migrate their interval and local safeguards; changing the example does not update a live role.

## 4. Troubleshooting

| Symptom | First checks |
| --- | --- |
| HTTP403 on config | Administrator token/policy and selected mount; worker policy intentionally denies configuration |
| HTTP400 certificate is a map | Use explicit PEM string serialization as above |
| LDAP49 / data52e | Actual bind password/UPN, account state and lockout |
| LDAP32 No Such Object | Target DN, userdn search base, domain/DC and visibility |
| Insufficient access on rotation | Specific reset-password delegation and password policy |
| Rotation overdue | Vault sealed/offline, time drift, bind expiry or scheduled rotation failure |

The worker's exact read policy is installed in the Entra/JWT stage. Continue with [Azure worker setup](AZURE-WORKER.md). Resources: [LDAP secrets documentation](https://openbao.org/docs/secrets/ldap/), [LDAP API](https://openbao.org/api-docs/secret/ldap/).
