#Requires -Version 7.4
# SPDX-License-Identifier: Apache-2.0
Set-StrictMode -Version Latest
function Find-DirectoryJobId {
    param($Value,[int]$Depth=0,[bool]$JobIdValue=$false)
    if($null -eq $Value -or $Depth -gt 3){return}
    if($Value -is [guid]) {if($Value -ne [guid]::Empty){$Value.ToString('D')};return}
    if($Value -is [string]) {
        if($Value.Length -gt 8192){return}
        $id=[guid]::Empty
        if([guid]::TryParse($Value.Trim(),[ref]$id)){if($id -ne [guid]::Empty){$id.ToString('D')};return}
        if($Value.TrimStart().StartsWith('{')) {
            try {$decoded=$Value | ConvertFrom-Json -ErrorAction Stop} catch {return}
            Find-DirectoryJobId -Value $decoded -Depth ($Depth+1) -JobIdValue $JobIdValue
        }
        return
    }
    # Inspect only known job-ID fields; never select arbitrary GUIDs from metadata.
    $names=if($JobIdValue){@('JobId','RunbookJobId','Guid')}else{@('JobId','RunbookJobId')}
    foreach($name in $names) {
        $child=$null
        if($Value -is [Collections.IDictionary]) {
            foreach($key in $Value.Keys){if([string]$key -ieq $name){$child=$Value[$key];break}}
        } else {
            $property=$Value.PSObject.Properties[$name]
            if($null -ne $property){$child=$property.Value}
        }
        if($null -ne $child){Find-DirectoryJobId -Value $child -Depth ($Depth+1) -JobIdValue $true}
    }
}
function Get-DirectoryJobContext {
    <#
    .SYNOPSIS
    Normalize platform job metadata without exposing its contents or guessing IDs.
    #>
    [CmdletBinding()]param([AllowNull()]$Metadata,[AllowNull()][string]$EnvironmentMetadata)
    $found=[Collections.Generic.List[object]]::new()
    foreach($id in @(Find-DirectoryJobId -Value $Metadata)){$found.Add([pscustomobject]@{Id=$id;Source='PSPrivateMetadata'})}
    foreach($id in @(Find-DirectoryJobId -Value $EnvironmentMetadata)){$found.Add([pscustomobject]@{Id=$id;Source='Environment.PSPrivateMetadata'})}
    $ids=@($found | Select-Object -ExpandProperty Id -Unique)
    if($ids.Count -eq 1) {
        return [pscustomobject]@{AzureJobId=$ids[0];AzureJobIdSource=(@($found | Select-Object -ExpandProperty Source -Unique) -join ',');JobCorrelationStatus='Captured'}
    }
    [pscustomobject]@{AzureJobId=$null;AzureJobIdSource=$null;JobCorrelationStatus=$(if($ids.Count -gt 1){'Conflicting'}else{'Unavailable'})}
}
function Get-DirectoryFailureDetail {
    <#
    .SYNOPSIS
    Translate allowlisted reason codes to safe operator messages and actions.
    #>
    [CmdletBinding()]param([string]$Code)
    $messages=@{
        DIRECTORY_USER_DISABLED=@('User account is disabled.','Choose an eligible enabled account; do not enable an account solely to bypass this check.')
        DIRECTORY_GROUP_NOT_SECURITY=@('The requested group is not a security group.','Use an existing eligible AD security group.')
        DIRECTORY_USER_PRIMARY_GROUP_UNSUPPORTED=@('The user does not have the supported Domain Users primary group.','Ask the directory owner to review the account classification; do not change its primary group just to run this operation.')
        DIRECTORY_USER_NOT_FOUND=@('The user could not be found on the configured domain controller.','Check the user sAMAccountName and domain.')
        DIRECTORY_GROUP_NOT_FOUND=@('The group could not be found on the configured domain controller.','Check the group sAMAccountName and domain.')
        DIRECTORY_USER_LOOKUP_FAILED=@('The user lookup failed.','Check DC connectivity and execution-account read permissions; no raw AD diagnostic is emitted.')
        DIRECTORY_GROUP_LOOKUP_FAILED=@('A group lookup failed during target or membership classification.','Check group identity, nesting visibility and DC connectivity.')
        DIRECTORY_PROTECTED_OBJECT=@('The user, group or a parent group is protected.','Use the separately authorized privileged administration process.')
        DIRECTORY_PRIVILEGED_IDENTITY=@('The request involves a privileged identity or privileged parent group.','Use the separately authorized privileged administration process.')
        DIRECTORY_EXCLUDED_SUBTREE=@('The request involves an object beneath an excluded Tier 0 or domain-controller OU.','Do not move the object to bypass the exclusion.')
        DIRECTORY_UNKNOWN_IDENTITY_SCOPE=@('An identity is outside the reviewed domain scope.','Ask the directory owner to review cross-domain membership and scope.')
        DIRECTORY_CLASSIFICATION_LIMIT=@('Group nesting exceeds the supported classification limit.','Review nesting before attempting another change.')
        DIRECTORY_WRITES_NOT_ENABLED=@('Directory writes are disabled for maintenance.','Use Preview=True or ask the platform administrator to restore writable status when maintenance is complete.')
        DIRECTORY_ROTATION_ADMISSION_DENIED=@('The credential is too close to its rotation deadline, stale or ahead of the worker clock.','Check time and vault rotation health, then start a fresh job after rotation.')
        DIRECTORY_ACCOUNT_LOCKED=@('The execution account has an active or unreconciled local lock.','Check the owning run and evidence; do not delete the lock without reconciliation.')
        DIRECTORY_POLICY_INVALID=@('The protected scope policy is invalid or its review has expired.','Ask the platform administrator to review the protected policy.')
        DIRECTORY_EXCLUSION_POLICY_INCOMPLETE=@('Required excluded OU identities do not match the protected policy.','Resolve the OU GUIDs and review policy; do not weaken exclusions.')
        DIRECTORY_UNSAFE_EVIDENCE_PATH=@('The evidence path contains an unsupported filesystem link.','Ask the platform administrator to restore the protected evidence location.')
        DIRECTORY_UNSAFE_EVIDENCE_ACL=@('The evidence directory permissions do not meet the protection policy.','Ask the platform administrator to repair the protected ACLs.')
        DIRECTORY_POLICY_FILE_INVALID=@('The local policy file is missing, unreadable or not valid JSON.','Ask the platform administrator to verify the deployed policy file.')
        DIRECTORY_POLICY_FILE_UNSAFE=@('The policy file is a link or has unsafe permissions.','Ask the platform administrator to restore protected local policy files.')
        DIRECTORY_IDENTITY_INVALID=@('The retrieved execution identity does not match the required directory account.','Review the protected credential mapping; do not substitute an operator credential.')
        DIRECTORY_VAULT_UNAVAILABLE=@('The vault credential or health check failed.','Check Arc authentication, vault availability, mapping and password freshness.')
        DIRECTORY_POSTCHECK_FAILED=@('The membership could not be verified after the write.','Reconcile the recorded run and actual membership before any retry.')
        DIRECTORY_PROVIDER_OR_EVIDENCE_FAILURE=@('A directory, audit or evidence operation failed.','Inspect protected evidence and platform health; do not automatically retry a possibly applied write.')
    }
    if(-not $messages.ContainsKey($Code)){$Code='DIRECTORY_PROVIDER_OR_EVIDENCE_FAILURE'}
    [pscustomobject]@{ReasonCode=$Code;Reason=$messages[$Code][0];RecommendedAction=$messages[$Code][1]}
}
function Get-DirectoryUser {
    param($Identity,$Policy,[pscredential]$Credential,[string[]]$Properties=@())
    $query=@{Identity=$Identity;Server=$Policy.DomainController;Credential=$Credential;ErrorAction='Stop'}
    if($Properties.Count){$query.Properties=$Properties}
    try {Get-ADUser @query}
    catch {if($_.Exception.GetType().FullName -like '*ADIdentityNotFoundException'){throw 'DIRECTORY_USER_NOT_FOUND'};throw 'DIRECTORY_USER_LOOKUP_FAILED'}
}
function Get-DirectoryGroup {
    param($Identity,$Policy,[pscredential]$Credential,[string[]]$Properties=@())
    $query=@{Identity=$Identity;Server=$Policy.DomainController;Credential=$Credential;ErrorAction='Stop'}
    if($Properties.Count){$query.Properties=$Properties}
    try {Get-ADGroup @query}
    catch {if($_.Exception.GetType().FullName -like '*ADIdentityNotFoundException'){throw 'DIRECTORY_GROUP_NOT_FOUND'};throw 'DIRECTORY_GROUP_LOOKUP_FAILED'}
}
function Test-DirectoryObjectSafety {
    param($Object,$Policy,[pscredential]$Credential)
    $argsMap=@{Server=$Policy.DomainController;Credential=$Credential;ErrorAction='Stop'}
    if($Object.adminCount -eq 1 -or $Object.isCriticalSystemObject -eq $true){throw 'DIRECTORY_PROTECTED_OBJECT'}
    $sid=[string]$Object.SID
    if($sid -match '^S-1-5-32-' -or $sid -match '-(498|500|502|512|516|517|518|519|520|521|525|526|527)$'){throw 'DIRECTORY_PRIVILEGED_IDENTITY'}
    if($sid -notmatch ('^'+[regex]::Escape([string]$Policy.DomainSid)+'-[0-9]+$')){throw 'DIRECTORY_UNKNOWN_IDENTITY_SCOPE'}
    if($Object.ObjectGUID.ToString() -in @($Policy.ProtectedObjectGuids)){throw 'DIRECTORY_PROTECTED_OBJECT'}
    foreach($root in $Policy.ExcludedOuGuids) {
        $ou=Get-ADOrganizationalUnit -Identity ([guid]$root) @argsMap
        $bytes=([guid]$Object.ObjectGUID).ToByteArray()
        $filter='(objectGUID='+ (($bytes | ForEach-Object {'\'+$_.ToString('x2')}) -join '') +')'
        if(@(Get-ADObject -LDAPFilter $filter -SearchBase $ou.DistinguishedName -SearchScope Subtree @argsMap).Count){throw 'DIRECTORY_EXCLUDED_SUBTREE'}
    }
}
function Test-DirectoryMembershipSafety {
    param($Object,$Policy,[pscredential]$Credential)
    $pending=[Collections.Generic.Queue[object]]::new();$pending.Enqueue($Object)
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    while($pending.Count) {
        $current=$pending.Dequeue()
        if(-not $seen.Add([string]$current.ObjectGUID)){continue}
        if($seen.Count -gt 256){throw 'DIRECTORY_CLASSIFICATION_LIMIT'}
        Test-DirectoryObjectSafety -Object $current -Policy $Policy -Credential $Credential
        foreach($parent in @($current.memberOf)) {
            if([string]::IsNullOrWhiteSpace($parent)){continue}
            $group=Get-DirectoryGroup -Identity $parent -Policy $Policy -Credential $Credential -Properties adminCount,isCriticalSystemObject,memberOf
            $pending.Enqueue($group)
        }
    }
}
function Get-DirectoryMembershipSnapshot {
    param($Policy,[guid]$GroupObjectGuid,[guid]$MemberObjectGuid,[pscredential]$Credential)
    $argsMap=@{Server=$Policy.DomainController;Credential=$Credential;ErrorAction='Stop'}
    $group=Get-DirectoryGroup -Identity $GroupObjectGuid -Policy $Policy -Credential $Credential -Properties adminCount,isCriticalSystemObject,memberOf
    $user=Get-DirectoryUser -Identity $MemberObjectGuid -Policy $Policy -Credential $Credential -Properties adminCount,isCriticalSystemObject,memberOf,Enabled,primaryGroupID
    if($group.GroupCategory -ne 'Security'){throw 'DIRECTORY_GROUP_NOT_SECURITY'}
    if(-not $user.Enabled){throw 'DIRECTORY_USER_DISABLED'}
    if($user.primaryGroupID -ne 513){throw 'DIRECTORY_USER_PRIMARY_GROUP_UNSUPPORTED'}
    Test-DirectoryMembershipSafety -Object $group -Policy $Policy -Credential $Credential
    Test-DirectoryMembershipSafety -Object $user -Policy $Policy -Credential $Credential
    # Query the link on the same DC without enumerating or truncating a large group's members.
    $escaped=$user.DistinguishedName.Replace('\','\5c').Replace('*','\2a').Replace('(','\28').Replace(')','\29').Replace([string][char]0,'\00')
    $exists=@(Get-ADGroup -LDAPFilter ('(member='+$escaped+')') -SearchBase $group.DistinguishedName -SearchScope Base @argsMap).Count -eq 1
    [pscustomobject]@{Group=$group;User=$user;DirectMember=$exists}
}
function Add-DirectoryMembershipLink {
    param($Snapshot,$Policy,[pscredential]$Credential)
    $connection=$null
    try {
        Add-Type -AssemblyName System.DirectoryServices.Protocols -ErrorAction Stop
        $identifier=[DirectoryServices.Protocols.LdapDirectoryIdentifier]::new($Policy.DomainController,636,$true,$false)
        $connection=[DirectoryServices.Protocols.LdapConnection]::new($identifier)
        $connection.Timeout=[TimeSpan]::FromSeconds(15)
        $connection.AutoBind=$false
        $connection.AuthType=[DirectoryServices.Protocols.AuthType]::Negotiate
        $connection.SessionOptions.ProtocolVersion=3
        $connection.SessionOptions.SecureSocketLayer=$true
        $connection.SessionOptions.ReferralChasing=[DirectoryServices.Protocols.ReferralChasingOptions]::None
        $connection.Bind($Credential.GetNetworkCredential())
        $change=[DirectoryServices.Protocols.DirectoryAttributeModification]::new()
        $change.Name='member';$change.Operation=[DirectoryServices.Protocols.DirectoryAttributeOperation]::Add
        $null=$change.Add([string]$Snapshot.User.DistinguishedName)
        $request=[DirectoryServices.Protocols.ModifyRequest]::new([string]$Snapshot.Group.DistinguishedName,$change)
        $null=$connection.SendRequest($request,[TimeSpan]::FromSeconds(15))
    } finally {if($null -ne $connection){$connection.Dispose()}}
}
function Write-DirectoryOperationRecord {
    param([string]$Path,$Record)
    # Atomic durable replacement of a per-run record. Caller holds the account lock.
    $temporary=$Path+'.next'
    $bytes=[Text.Encoding]::UTF8.GetBytes(($Record | ConvertTo-Json -Depth 8))
    $stream=[IO.File]::Open($temporary,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try {$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
    [IO.File]::Move($temporary,$Path,$true)
    $eventId=switch($Record.State){'VerifiedSuccess'{4101};'RecoveryRequired'{4103};'RejectedBeforeWrite'{4102};default{4100}}
    [Diagnostics.EventLog]::WriteEntry('TSMA',($Record | ConvertTo-Json -Depth 8 -Compress),[Diagnostics.EventLogEntryType]::Information,$eventId)
}
function New-DirectoryAccountLock {
    [CmdletBinding(SupportsShouldProcess)][OutputType([IO.FileStream])]param([string]$Path)
    if(-not $PSCmdlet.ShouldProcess($Path,'Acquire local account lock')){throw 'DIRECTORY_ACCOUNT_LOCK_DECLINED'}
    [IO.File]::Open($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
}
function Close-DirectoryAccountLock {
    param($Lock,[string]$Path,[bool]$Keep)
    $Lock.Dispose()
    if(-not $Keep){[IO.File]::Delete($Path)}
}
function Invoke-DirectoryGroupMember {
    <#
    .SYNOPSIS
    Ensure one eligible user is a direct member of the requested existing group.
    .DESCRIPTION
    Preview defaults true. One account-level local lock; this is not a distributed
    coordinator. Uncertain writes preserve the lock and require reconciliation.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._$ -]{0,127}$')][string]$UserName,
        [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._$ -]{0,127}$')][string]$GroupName,
        [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._/ -]{0,63}$')][string]$ChangeReference,
        [bool]$Preview=$true,
        [Parameter(Mandatory)][pscredential]$Credential,
        [Parameter(Mandatory)]$Policy,
        [Parameter(Mandatory)][DateTimeOffset]$LastRotationUtc,
        [AllowNull()][string]$AzureJobId,
        [AllowNull()][string]$AzureJobIdSource,
        [ValidateSet('Captured','Unavailable','Conflicting')][string]$JobCorrelationStatus='Unavailable')
    if([string]::IsNullOrWhiteSpace($Policy.ExecutionIdentity) -or $Credential.UserName -cne $Policy.ExecutionIdentity){throw 'DIRECTORY_IDENTITY_INVALID'}
    if($Policy.DomainSid -notmatch '^S-1-5-21-[0-9]+-[0-9]+-[0-9]+$' -or $Policy.DomainController -notmatch '^[A-Za-z0-9][A-Za-z0-9.-]+\.[A-Za-z0-9-]+$' -or $Policy.EvidenceDirectory -cne 'C:\ProgramData\TSMA\Evidence\GroupMembership' -or
        @($Policy.ExcludedOuGuids).Count -lt 2 -or [string]::IsNullOrWhiteSpace($Policy.ScopeReviewReference) -or
        [DateTimeOffset]::Parse($Policy.ReviewExpiresUtc) -le [DateTimeOffset]::UtcNow){throw 'DIRECTORY_POLICY_INVALID'}
    foreach($id in @($Policy.ExcludedOuGuids)+@($Policy.ProtectedObjectGuids)){$null=[guid]::Parse($id)}
    if($Policy.WritesEnabled -isnot [bool]){throw 'DIRECTORY_POLICY_INVALID'}
    if(-not $Preview -and -not $Policy.WritesEnabled){throw 'DIRECTORY_WRITES_NOT_ENABLED'}
    if(($Policy.MaximumPasswordAgeSeconds -isnot [int] -and $Policy.MaximumPasswordAgeSeconds -isnot [long]) -or $Policy.MaximumPasswordAgeSeconds -lt 600 -or $Policy.MaximumPasswordAgeSeconds -gt 604800){throw 'DIRECTORY_POLICY_INVALID'}
    if($LastRotationUtc -gt [DateTimeOffset]::UtcNow -or $LastRotationUtc.AddSeconds($Policy.MaximumPasswordAgeSeconds) -le [DateTimeOffset]::UtcNow.AddMinutes(5)){throw 'DIRECTORY_ROTATION_ADMISSION_DENIED'}
    # Resolve both required exclusion roots and pin them to policy GUIDs before admission.
    if($Policy.DomainDistinguishedName -notmatch '^(DC=[A-Za-z0-9-]+,)+DC=[A-Za-z0-9-]+$' -or
        [string]::IsNullOrWhiteSpace($Policy.Tier0DistinguishedName) -or
        -not $Policy.Tier0DistinguishedName.EndsWith(','+$Policy.DomainDistinguishedName,[StringComparison]::OrdinalIgnoreCase)){throw 'DIRECTORY_POLICY_INVALID'}
    foreach($dn in @($Policy.Tier0DistinguishedName,('OU=Domain Controllers,'+$Policy.DomainDistinguishedName))) {
        $root=Get-ADOrganizationalUnit -Identity $dn -Server $Policy.DomainController -Credential $Credential -ErrorAction Stop
        if($root.ObjectGUID.ToString() -notin @($Policy.ExcludedOuGuids)){throw 'DIRECTORY_EXCLUSION_POLICY_INCOMPLETE'}
    }
    $resolvedUser=Get-DirectoryUser -Identity $UserName.Trim() -Policy $Policy -Credential $Credential
    $resolvedGroup=Get-DirectoryGroup -Identity $GroupName.Trim() -Policy $Policy -Credential $Credential
    $MemberObjectGuid=[guid]$resolvedUser.ObjectGUID
    $GroupObjectGuid=[guid]$resolvedGroup.ObjectGUID
    $directory=Get-Item -LiteralPath $Policy.EvidenceDirectory -ErrorAction Stop
    for($cursor=$directory;$null -ne $cursor;$cursor=$cursor.Parent){if($cursor.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'DIRECTORY_UNSAFE_EVIDENCE_PATH'}}
    $acl=Get-Acl -LiteralPath $directory.FullName
    if(-not $acl.AreAccessRulesProtected){throw 'DIRECTORY_UNSAFE_EVIDENCE_ACL'}
    foreach($rule in $acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])) {
        if($rule.AccessControlType -eq 'Allow' -and $rule.IdentityReference.Value -notin @('S-1-5-18','S-1-5-32-544')){throw 'DIRECTORY_UNSAFE_EVIDENCE_ACL'}
    }
    $lockPath=Join-Path $directory.FullName 'directory-account.lock'
    $lock=$null;$attempted=$false;$completed=$false
    $runId=[guid]::NewGuid().ToString();$recordPath=Join-Path $directory.FullName ($runId+'.json')
    $record=[ordered]@{Version=1;Runbook='Add-DirectoryGroupMember';RunId=$runId;AzureJobId=$AzureJobId;AzureJobIdSource=$AzureJobIdSource;JobCorrelationStatus=$JobCorrelationStatus;ChangeReference=$ChangeReference;Preview=$Preview;StartedUtc=[DateTimeOffset]::UtcNow.ToString('o');DC=$Policy.DomainController;MemberObjectGuid=$MemberObjectGuid.ToString();GroupObjectGuid=$GroupObjectGuid.ToString();State='Precheck';MutationAttempted=$false}
    try {
        try {$lock=New-DirectoryAccountLock -Path $lockPath -Confirm:$false}catch{throw 'DIRECTORY_ACCOUNT_LOCKED'}
        $bytes=[Text.Encoding]::UTF8.GetBytes($runId);$lock.Write($bytes,0,$bytes.Length);$lock.Flush($true)
        $snapshot=Get-DirectoryMembershipSnapshot -Policy $Policy -GroupObjectGuid $GroupObjectGuid -MemberObjectGuid $MemberObjectGuid -Credential $Credential
        $record.MemberDN=$snapshot.User.DistinguishedName;$record.GroupDN=$snapshot.Group.DistinguishedName;$record.BeforeDirectMember=$snapshot.DirectMember
        $record.State='Intent';Write-DirectoryOperationRecord -Path $recordPath -Record $record
        if($snapshot.DirectMember){$record.State='AlreadyMember';$completed=$true}
        elseif($Preview){$record.State='Preview';$completed=$true}
        else {
            # Re-resolve eligibility immediately before sending a single mutation.
            $snapshot=Get-DirectoryMembershipSnapshot -Policy $Policy -GroupObjectGuid $GroupObjectGuid -MemberObjectGuid $MemberObjectGuid -Credential $Credential
            if($snapshot.DirectMember){$record.State='AlreadyMember';$completed=$true}
            else {
                if($LastRotationUtc.AddSeconds($Policy.MaximumPasswordAgeSeconds) -le [DateTimeOffset]::UtcNow.AddMinutes(5)){throw 'DIRECTORY_ROTATION_ADMISSION_DENIED'}
                $record.State='WritePending';$record.MutationAttempted=$true
                Write-DirectoryOperationRecord -Path $recordPath -Record $record
                $attempted=$true
                Add-DirectoryMembershipLink -Snapshot $snapshot -Policy $Policy -Credential $Credential
                $after=Get-DirectoryMembershipSnapshot -Policy $Policy -GroupObjectGuid $GroupObjectGuid -MemberObjectGuid $MemberObjectGuid -Credential $Credential
                if(-not $after.DirectMember){throw 'DIRECTORY_POSTCHECK_FAILED'}
                $record.AfterDirectMember=$true;$record.State='VerifiedSuccess';$completed=$true
            }
        }
        $record.CompletedUtc=[DateTimeOffset]::UtcNow.ToString('o')
        Write-DirectoryOperationRecord -Path $recordPath -Record $record
        [pscustomobject]@{RunId=$runId;AzureJobId=$AzureJobId;AzureJobIdSource=$AzureJobIdSource;JobCorrelationStatus=$JobCorrelationStatus;Outcome=$record.State;Preview=$Preview;MemberObjectGuid=$MemberObjectGuid;GroupObjectGuid=$GroupObjectGuid.ToString();MutationAttempted=$attempted;EvidencePath=$recordPath;Utc=$record.CompletedUtc}
    } catch {
        $completed=$false
        $detail=Get-DirectoryFailureDetail -Code $_.Exception.Message
        $record.ReasonCode=$detail.ReasonCode;$record.Reason=$detail.Reason;$record.RecommendedAction=$detail.RecommendedAction
        $record.MutationAttempted=$attempted
        $record.State=if($attempted){'RecoveryRequired'}else{'RejectedBeforeWrite'}
        $record.CompletedUtc=[DateTimeOffset]::UtcNow.ToString('o')
        if($null -ne $lock){try{Write-DirectoryOperationRecord -Path $recordPath -Record $record}catch{Write-Warning ('DIRECTORY_EVIDENCE_UPDATE_FAILED RunId='+$runId)}}
        $failure=[InvalidOperationException]::new(('DIRECTORY_OPERATION_'+$record.State.ToUpperInvariant()+' RunId='+$runId+' ReasonCode='+$detail.ReasonCode+' '+$detail.Reason))
        $failure.Data['DirectoryReasonCode']=$detail.ReasonCode
        $failure.Data['DirectoryRunId']=$runId
        $failure.Data['DirectoryOutcome']=$record.State
        throw $failure
    } finally {
        if($null -ne $lock){Close-DirectoryAccountLock -Lock $lock -Path $lockPath -Keep (-not $completed -and $attempted)}
    }
}
Export-ModuleMember -Function Invoke-DirectoryGroupMember,Get-DirectoryJobContext,Get-DirectoryFailureDetail
