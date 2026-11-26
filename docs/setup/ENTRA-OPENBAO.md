# Create the Entra API trust and OpenBao JWT role

**Run on:** the management workstation as an authorized Entra application administrator, then the vault administrator's shell. Prerequisites: working Arc identity and OpenBao LDAP role. This is workload authentication, not PIM and not an interactive human sign-in application.

## 1. Prepare a matching Graph module set

In a new PowerShell 7 process, install Authentication and Applications at the same available release version. Do not load an older Applications assembly into a session already using another Authentication version:

~~~powershell
$graphVersion=(Find-PSResource -Name Microsoft.Graph.Authentication -Repository PSGallery).Version.ToString()
Install-PSResource -Name Microsoft.Graph.Authentication,Microsoft.Graph.Applications -Version $graphVersion -Repository PSGallery -Scope CurrentUser
Import-Module Microsoft.Graph.Authentication -RequiredVersion $graphVersion
Import-Module Microsoft.Graph.Applications -RequiredVersion $graphVersion
$tenantId='<your-tenant-guid>'
Connect-MgGraph -TenantId $tenantId -Scopes 'Application.ReadWrite.All','AppRoleAssignment.ReadWrite.All'
Get-MgContext | Select-Object TenantId,Account,Scopes
~~~

Your role/consent administrator must authorize these setup permissions; requesting scopes is not itself authority. These permissions are for the setup administrator, not the Arc worker. If matching packages are unavailable, select a release available for both. Start a new process after assembly-conflict errors.

## 2. Create the dedicated API and direct managed-identity role assignment

Retrieve arcPrincipalId as shown in [Azure setup](AZURE-WORKER.md) or load the exact recorded GUID. It is the machine's Entra service-principal object ID, not its Azure resource ID or worker registration GUID.

For a genuinely new installation, run this entire block as one unit. It refuses duplicate api-tsma-vault display names before creation. If it stops after partial creation, inspect the reported IDs and existing objects before continuing; do not execute creation lines individually or rerun blindly.

~~~powershell
$arcPrincipalId='<actual-arc-principal-guid>'
$trust=& {
    $ErrorActionPreference='Stop'
    if((Get-MgContext).TenantId -ne $tenantId){throw 'Wrong Graph tenant.'}
    $null=[guid]::Parse($arcPrincipalId)
    $workerSp=Get-MgServicePrincipal -ServicePrincipalId $arcPrincipalId -ErrorAction Stop
    $existing=@(Get-MgApplication -Filter "displayName eq 'api-tsma-vault'" -All -ErrorAction Stop)
    if($existing.Count){throw 'Application already exists. Inspect its exact IDs before reuse; do not create another.'}
    $roleId=[guid]::NewGuid()
    $app=New-MgApplication -DisplayName 'api-tsma-vault' -SignInAudience AzureADMyOrg -Api @{RequestedAccessTokenVersion=2} -AppRoles @(@{
        Id=$roleId;AllowedMemberTypes=@('Application');DisplayName='Operation Directory'
        Description='Approved TSMA directory worker authentication'
        IsEnabled=$true;Value='Operation.Directory'
    }) -ErrorAction Stop
    # Capture these IDs in your private deployment record if later steps fail.
    Write-Host ('Created application object '+$app.Id+'; client '+$app.AppId)
    $resourceUri='api://'+$app.AppId
    Update-MgApplication -ApplicationId $app.Id -IdentifierUris @($resourceUri) -ErrorAction Stop
    $apiSp=New-MgServicePrincipal -AppId $app.AppId -AppRoleAssignmentRequired:$true -ErrorAction Stop
    $null=New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $workerSp.Id -PrincipalId $workerSp.Id -ResourceId $apiSp.Id -AppRoleId $roleId -ErrorAction Stop
    [pscustomobject]@{TenantId=$tenantId;ArcPrincipalId=$workerSp.Id;ApplicationObjectId=$app.Id;ApplicationClientId=$app.AppId;ApiServicePrincipalId=$apiSp.Id;ApplicationRoleId=$roleId;ResourceUri=$resourceUri}
}
$trust | Format-List
~~~

Record all values. There is no app client secret or certificate in this trust. App role assignment requires the API service-principal object ID, not the application object ID. Only assign the intended machine; user membership in an operator group is not a substitute. Verify in Enterprise applications -> api-tsma-vault and the worker's app-role assignments using exact IDs. Role propagation/token caching can delay issuance; do not weaken bindings.

For an existing approved application, use Get-MgApplication -ApplicationId and Get-MgServicePrincipal -ServicePrincipalId with your recorded IDs. Verify requested token version 2, identifier URI, enabled Application role and direct assignment. Do not select a random same-display-name object.

## 3. Prepare the nonsecret JWT role JSON

On the workstation, create C:\SecureConfig if necessary and prepare OpenBaoJwtRole.json from the example using the actual IDs (reload trust from your private record if using a new session):

~~~powershell
Set-Location C:\Code\tsma
$role=Get-Content .\examples\OpenBaoJwtRole.example.json -Raw | ConvertFrom-Json
$role.bound_audiences=@($trust.ApplicationClientId)
$role.bound_claims.tid=$trust.TenantId
$role.bound_claims.oid=$trust.ArcPrincipalId
$role | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath C:\SecureConfig\OpenBaoJwtRole.json -Encoding utf8
~~~

Check the file before use. Keep roles=Operation.Directory, ver=2.0, no default policy and five-minute maximum token lifetime. The requested Arc resource is api://<client-id>, but the v2 audience bound by OpenBao is the client-ID GUID without api://. Binding audience alone is insufficient; bind tenant and exact machine oid as well.

## 4. Install the worker policy and JWT role

Transfer the JSON and deployment/openbao/operation-directory-worker-policy.hcl to /opt/tsma/openbao on the vault host using an interactive scp session. These are nonsecret policy files; do not transfer any worker token. Then:

~~~sh
cd /opt/tsma/openbao
sudo docker compose -p tsma-vault cp ./OpenBaoJwtRole.json openbao:/tmp/OpenBaoJwtRole.json
sudo docker compose -p tsma-vault cp ./operation-directory-worker-policy.hcl openbao:/tmp/operation-directory-worker-policy.hcl
sudo docker compose -p tsma-vault exec openbao sh
bao login
bao auth list -detailed
bao plugin list -detailed auth
~~~

The remaining bao commands run inside that authenticated administrator container shell. Only if jwt-arc/ is absent and jwt is available:

~~~sh
bao auth enable -path=jwt-arc jwt
~~~

Replace TENANT_GUID below with the real tenant, then configure the exact issuer and policy:

~~~sh
bao write auth/jwt-arc/config oidc_discovery_url='https://login.microsoftonline.com/TENANT_GUID/v2.0' bound_issuer='https://login.microsoftonline.com/TENANT_GUID/v2.0' jwt_supported_algs=RS256
bao policy write operation-directory-worker /tmp/operation-directory-worker-policy.hcl
bao write auth/jwt-arc/role/operation-directory-worker01 @/tmp/OpenBaoJwtRole.json
bao read auth/jwt-arc/role/operation-directory-worker01
bao policy read operation-directory-worker
~~~

Do not overwrite an established mount's issuer blindly. The worker policy permits only metadata and credentials for ldap-operation/static-role/operation-directory and ldap-operation/static-cred/operation-directory, plus sys/capabilities-self update. No root/default policy, other-account access, password rotation, auth configuration or policy management is granted. The five-minute token expires independently of the 24-hour AD password timer.

## 5. Prepare the worker's provider configuration

Copy examples/OperationDirectory.example.json to C:\SecureConfig\OperationDirectory.json on the worker. Replace Address, ManagedIdentityResource (api://<actual-client-id>), account UserName/CredentialUserName/DistinguishedName, and any deliberately renamed role/mount values. Keep JwtRole=operation-directory-worker01 for the supplied code-owned probes. This is a role label, not a requirement that your actual host be named WORKER01; the oid binding pins your actual machine. MaximumPasswordAgeSeconds=86400 corresponds to the 24-hour static role. MinimumRemainingLifetimeSeconds=2100 requires more than 35 minutes remaining before credential use.

The workstation and worker are separate machines: transfer this nonsecret configuration deliberately; creating it on one does not create it on the other. The worker needs no administrator token, reconciliation password or SecretID. Install this file through [the protected worker procedure](../INSTALL.md).

## 6. Isolated negative identity roles

After the real role succeeds, make four copies of its JSON on the management host. For arc-deny-audience replace bound_audiences with a different unused GUID. For arc-deny-tenant replace bound_claims.tid; for arc-deny-identity replace bound_claims.oid. For arc-deny-issuer add bound_claims.iss='https://issuer.invalid/'. Retain all other bindings, scoped policy and short lifetime. Transfer/install each under its matching auth/jwt-arc/role/arc-deny-* name, never modifying the real role.

Test-ArcOpenBaoBoundaries uses the genuine worker token against those negative roles, plus a signature-altered token against the real role. A successful HTTP request is not success: all five cases must reject. Remove temporary negative roles after acceptance unless deliberately retained for controlled regression checks.

Resources: [OpenBao JWT API](https://openbao.org/docs/api/auth/jwt/), [Microsoft application roles](https://learn.microsoft.com/en-us/entra/identity-platform/howto-add-app-roles-in-apps), [Arc managed identity](https://learn.microsoft.com/en-us/azure/azure-arc/servers/managed-identity-authentication).
