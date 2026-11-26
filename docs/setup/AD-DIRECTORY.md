# Prepare AD identities and directory permissions

**Run on:** a domain administration workstation/DC with the ActiveDirectory module, using an authorized AD administrator. No Azure or vault credentials are used in this stage. This does not grant rights to Domain Admins, Enterprise Admins, Schema Admins, DCs, or other Tier 0 targets.

The first TSMA operation needs only user/group lookup and permission to write a security group's member attribute. It does not yet implement the entire ordinary helpdesk operation catalog. Do not grant Full Control, built-in Account Operators membership, or domain-wide administrator rights for convenience.

## 1. Select the real domain and protected paths

If you have no domain, finish the AD DS infrastructure task in [prerequisites](../PREREQUISITES.md). For an existing domain, choose existing approved OUs or create a reviewed structure. These commands are examples for a new deployment; inspect existing objects first.

~~~powershell
Import-Module ActiveDirectory
$dc='dc01.ad.example.com' # Replace with your DC.
$domain=Get-ADDomain -Server $dc
$domainDn=$domain.DistinguishedName
$adminDn='OU=Admin,'+$domainDn
$tier0Dn='OU=Tier 0,'+$adminDn
$serviceDn='OU=Service Accounts,'+$tier0Dn
$groupsDn='OU=Groups,'+$tier0Dn
$acceptanceDn='OU=TSMA Acceptance,'+$domainDn
~~~

In Active Directory Users and Computers (dsa.msc), enable View -> Advanced Features. Create missing Admin, Tier 0, Service Accounts and Groups OUs at the selected paths. Create an ordinary TSMA Acceptance OU outside Tier 0 for initial authorized examples. Keep accidental-deletion protection enabled. No existing computer, account or OU needs to be moved by this procedure.

The execution/reconciliation account objects and delegation groups belong in protected administration OUs because controlling their credentials or membership can affect many other objects. Protect the worker and vault infrastructure as Tier 0 according to your architecture. Domain Controllers stays a separate excluded OU.

## 2. Create two distinct accounts

Check for existing names before creation. If a name exists, inspect its DN, purpose, group membership and owner; do not repurpose it silently.

~~~powershell
Get-ADUser -Filter "SamAccountName -eq 'svc-op-directory' -or SamAccountName -eq 'svc-pam-rec-dsop'" -Server $dc -Properties MemberOf,Enabled |
    Select-Object SamAccountName,DistinguishedName,Enabled,MemberOf
~~~

Only when the intended names are unused, run each creation deliberately. Passwords are prompted, not stored in source or command history:

~~~powershell
$initial=Read-Host 'Unique initial password for svc-op-directory' -AsSecureString
try {
    New-ADUser -Name 'svc-op-directory' -SamAccountName 'svc-op-directory' -UserPrincipalName ('svc-op-directory@'+$domain.DNSRoot) -Path $serviceDn -Server $dc -AccountPassword $initial -Enabled $true -Description 'TSMA ordinary directory execution; password managed by OpenBao'
} finally { $initial.Dispose() }

$initial=Read-Host 'Different password for svc-pam-rec-dsop' -AsSecureString
try {
    New-ADUser -Name 'svc-pam-rec-dsop' -SamAccountName 'svc-pam-rec-dsop' -UserPrincipalName ('svc-pam-rec-dsop@'+$domain.DNSRoot) -Path $serviceDn -Server $dc -AccountPassword $initial -Enabled $true -Description 'PAM reconciliation for the TSMA directory execution account'
} finally { $initial.Dispose() }
~~~

Record owners and recovery procedures. Restrict interactive/RDP logon through your service-account policy while preserving required network authentication. Decide password-expiry handling deliberately: OpenBao rotates the execution password, while the initial reconciliation password also needs an owned renewal/recovery process. Entra/Arc managed identity removes worker bootstrap secrets, not the LDAP bind credential stored in the vault.

## 3. Create the execution/delegation group chain

Create missing Global security group GG-TSMA-DirectoryExec and Domain Local security group DL-TSMA-GroupMemberW in the protected groups OU. For a new installation:

~~~powershell
New-ADGroup -Name 'GG-TSMA-DirectoryExec' -SamAccountName 'GG-TSMA-DirectoryExec' -GroupScope Global -GroupCategory Security -Path $groupsDn -Server $dc
New-ADGroup -Name 'DL-TSMA-GroupMemberW' -SamAccountName 'DL-TSMA-GroupMemberW' -GroupScope DomainLocal -GroupCategory Security -Path $groupsDn -Server $dc
Add-ADGroupMember -Identity 'GG-TSMA-DirectoryExec' -Members 'svc-op-directory' -Server $dc
Add-ADGroupMember -Identity 'DL-TSMA-GroupMemberW' -Members 'GG-TSMA-DirectoryExec' -Server $dc
~~~

Execution identity -> Global role group -> Domain Local permission group -> target ACL. Protect these group memberships from ordinary operators. Do not nest either group in a built-in privileged group.

## 4. Delegate group-member modification

In dsa.msc, right-click the ordinary TSMA Acceptance OU -> Delegate Control:

1. Add DL-TSMA-GroupMemberW.
2. Choose Create a custom task to delegate.
3. Select Only the following objects in the folder -> Group objects. Leave create/delete object options unselected.
4. Select property-specific permissions and grant Write Members (the member property). Do not grant all properties, ownership, ACL changes or Full Control.
5. Review the resulting Advanced Security entry: it applies to descendant Group objects in the intended ordinary OU.

Repeat only for ordinary managed OU scopes reviewed by your AD owner when expanding service coverage. This does not change TSMA's exclusion-based target policy; actual AD permissions still bound where the credential can write. Avoid a blanket domain-root grant that inherits into protected assets. GPO Block Inheritance does not block these directory ACLs.

## 5. Delegate reconciliation on one execution account

Open svc-op-directory -> Properties -> Security -> Advanced -> Add. Select svc-pam-rec-dsop, Allow, Applies to This object only, and grant the Reset password extended right. Keep existing normal read permissions; add only the specific read access required if your environment restricts it. Do not grant write-member, write-DACL, ownership, reset rights on all Tier 0 users, or privileged group membership.

Check effective access using AD Administrative Center/Advanced Security and retain the resulting ACL review. The later successful initial/static-role rotation and fresh authentication demonstrate actual reset capability. Reads alone do not establish that permission. Password-policy restrictions can still prevent reset.

## 6. Create ordinary acceptance objects

Use an authorized isolated OU. New-ADUser prompts for the password; the group is ordinary and not used by applications:

~~~powershell
$initial=Read-Host 'Unique password for the acceptance user' -AsSecureString
try {
    New-ADUser -Name 'tsma-acceptance-user' -SamAccountName 'tsma-acceptance-user' -Path $acceptanceDn -Server $dc -AccountPassword $initial -Enabled $true
} finally { $initial.Dispose() }
New-ADGroup -Name 'TSMA-Acceptance-Group' -SamAccountName 'TSMA-Acceptance-Group' -GroupScope Global -GroupCategory Security -Path $acceptanceDn -Server $dc
Get-ADGroupMember -Identity 'DL-TSMA-GroupMemberW' -Server $dc
Get-ADUser -Identity 'svc-op-directory' -Server $dc -Properties MemberOf | Select-Object SamAccountName,DistinguishedName,MemberOf
~~~

Do not grant these objects production application entitlements. Keep them enabled/ordinary for the positive path. A separate disabled user can exercise rejection later. Preserve identities/DNs in the private worksheet, then proceed to [certificates and LDAPS](CERTIFICATES-LDAPS.md).

Resources: [AD DS delegation](https://learn.microsoft.com/en-us/windows-server/identity/ad-ds/plan/delegating-administration-by-using-ou-objects), [New-ADUser](https://learn.microsoft.com/en-us/powershell/module/activedirectory/new-aduser), [New-ADGroup](https://learn.microsoft.com/en-us/powershell/module/activedirectory/new-adgroup).
