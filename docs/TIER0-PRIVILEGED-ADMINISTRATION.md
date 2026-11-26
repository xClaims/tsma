# Tier 0 and privileged administration

This is the design boundary for later privileged operations, not an implemented privileged-runbook catalog.

## Protected assets and identities

Place powerful administration assets under the reviewed Tier 0 subtree, such as OU=Tier 0,OU=Admin,DC=ad,DC=example,DC=com. Include execution/reconciliation service accounts able to reset privileged passwords or make broad directory changes, their delegation groups, privileged automation workers, CA/PKI systems, PAM vault infrastructure and identity-governance systems. A Linux vault is not protected merely by placing an unrelated AD object in an OU; protect its OS, hosting, credentials and control plane as well.

Keep DC computer accounts in the domain's Domain Controllers OU. TSMA excludes both roots. Assets outside those roots that confer privilege need explicit protected GUID inventory and underlying permission review. OU placement and blocked GPO inheritance do not themselves prevent AD object modification; AD ACLs and protected GPO management remain separate controls. Enforced GPO links can still apply despite blocked inheritance.

## Protected group membership

| Group | Treatment |
| --- | --- |
| Domain Admins | Domain-wide privileged administration; outside ordinary operations |
| Enterprise Admins | Forest-wide privileged administration; temporary task-specific use under a separate approved process |
| Schema Admins | Schema-changing authority; separate approved process and controlled membership |
| BUILTIN\Administrators on DCs | Privileged domain administration boundary; protect direct and nested membership |
| BUILTIN\Account Operators on DCs | Broad account administration authority; protect it from ordinary runbooks and do not use membership as the routine execution-account delegation model |

Review direct/nested membership, ownership, write-member/control rights, delegated ACLs, service-account password reset rights and alternate paths. Removing privileged membership does not automatically clear historical adminCount or repair an object's inheritance; review deliberately rather than clearing flags solely to bypass TSMA.

## Object changes

- User changes: separate privileged identities from ordinary users; named administrative identities remain attributable to an individual. Never let ordinary operations reset a powerful execution/reconciliation account.
- Group changes: treat privilege-granting application groups and delegation groups as privileged even when not nested in built-in groups.
- Server changes: worker administrators and Azure administrators able to execute/publish code or change Arc extensions can affect credential access. Apply equivalent protection to hypervisors, backups and automation accounts.
- OU moves: review both source and destination ACL/GPO consequences, inventory and protected classifications. Do not move an asset out of an excluded subtree to make a runbook succeed.

## Privileged execution boundaries

Use separate reviewed code, execution credentials, vault mappings and worker/control-plane boundaries for ordinary directory, member-server, domain-level, forest-level and schema operations. Domain Admins, Enterprise Admins and Schema Admins are task-specific authorities, not a universal linear role hierarchy. PIM operator activation is additional access control; it does not grant on-premises privileged group membership.

For unpredictable senior-administrator incident work, use separately governed named administrative identities and established emergency procedures. Do not expose an unrestricted script/command parameter through the ordinary runbook as a shortcut.
