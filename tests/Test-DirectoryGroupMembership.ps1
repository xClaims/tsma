#Requires -Version 5.1
# SPDX-License-Identifier: Apache-2.0
<# Offline workflow/guard tests. Loads function ASTs only; real AD, LDAP, event-log
and filesystem mutation adapters are replaced. Production PS7/Windows integration
must still be validated on WORKER01. #>
[CmdletBinding()]param()
$ErrorActionPreference='Stop'
$base=Split-Path $PSScriptRoot -Parent
$tokens=$null;$parseErrors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $base 'src/operations/DirectoryOperations/DirectoryOperations.psm1'),[ref]$tokens,[ref]$parseErrors)
if($parseErrors.Count){throw 'Parse failed'}
$functions=($ast.EndBlock.Statements | Where-Object {$_ -is [Management.Automation.Language.FunctionDefinitionAst]} | ForEach-Object {$_.Extent.Text}) -join "`n"
$module=New-Module -Name DirectoryOperationLogicTests -ScriptBlock ([scriptblock]::Create("Set-StrictMode -Version Latest`n"+$functions+"`nExport-ModuleMember -Function *"))
Import-Module $module -Force
$checks=0
function Assert-Case {param([bool]$Ok,[string]$Name) if(-not $Ok){throw $Name};$script:checks++}
$secret=[Security.SecureString]::new()
foreach($character in 'OFFLINE-ONLY'.ToCharArray()){$secret.AppendChar($character)}
$secret.MakeReadOnly()
$credential=[pscredential]::new('EXAMPLE\svc-op-directory',$secret)
$policy=[pscustomobject]@{ExecutionIdentity='EXAMPLE\svc-op-directory';DomainDistinguishedName='DC=ad,DC=example,DC=com';Tier0DistinguishedName='OU=Tier 0,OU=Admin,DC=ad,DC=example,DC=com';MaximumPasswordAgeSeconds=14400;DomainController='dc01.ad.example.com';DomainSid='S-1-5-21-1-2-3';EvidenceDirectory='C:\ProgramData\TSMA\Evidence\GroupMembership';ExcludedOuGuids=@('11111111-1111-1111-1111-111111111111','22222222-2222-2222-2222-222222222222');ProtectedObjectGuids=@();ScopeReviewReference='REVIEW-1';ReviewExpiresUtc=[DateTimeOffset]::UtcNow.AddDays(1).ToString('o');WritesEnabled=$true}
try {
    & $module {
        $script:State=@{Mode='Success';Writes=0;Reads=0;Records=0;Kept=$false}
        function script:Get-ADOrganizationalUnit {param($Identity,$Server,[pscredential]$Credential,$ErrorAction) if(-not $Credential -or $Server -ne 'dc01.ad.example.com' -or $ErrorAction -ne 'Stop'){throw 'Invalid AD context'};$id=if($Identity -like 'OU=Tier 0*'){'11111111-1111-1111-1111-111111111111'}else{'22222222-2222-2222-2222-222222222222'};[pscustomobject]@{ObjectGUID=[guid]$id;DistinguishedName=$Identity}}
        function script:Get-ADUser {param($Identity,$Server,[pscredential]$Credential,$ErrorAction) if($Identity -ne 'ordinary-user' -or -not $Credential -or $Server -ne 'dc01.ad.example.com' -or $ErrorAction -ne 'Stop'){throw 'Invalid user lookup'};[pscustomobject]@{ObjectGUID=[guid]'33333333-3333-3333-3333-333333333333'}}
        function script:Get-ADGroup {param($Identity,$Server,[pscredential]$Credential,$ErrorAction) if($Identity -ne 'ordinary-group' -or -not $Credential -or $Server -ne 'dc01.ad.example.com' -or $ErrorAction -ne 'Stop'){throw 'Invalid group lookup'};[pscustomobject]@{ObjectGUID=[guid]'44444444-4444-4444-4444-444444444444'}}
        function script:Get-Item {param($LiteralPath,$ErrorAction) if($ErrorAction -ne 'Stop'){throw 'Invalid read'};[pscustomobject]@{FullName=$LiteralPath;Attributes=0;Parent=$null}}
        function script:Get-Acl {param($LiteralPath) if(-not $LiteralPath){throw 'Missing path'};$acl=[pscustomobject]@{AreAccessRulesProtected=$true};$acl | Add-Member ScriptMethod GetAccessRules {param($Explicit,$Inherited,$Type) if(-not $Explicit -or -not $Inherited -or $null -eq $Type){throw 'Invalid ACL inspection'};@()};$acl}
        function script:New-DirectoryAccountLock {[CmdletBinding(SupportsShouldProcess)]param($Path) if(-not $PSCmdlet.ShouldProcess($Path,'Mock lock')){throw 'Mock lock declined'};if(-not $Path.EndsWith('directory-account.lock')){throw 'Wrong lock'};$lock=[pscustomobject]@{};$lock | Add-Member ScriptMethod Write {param($Bytes,$Offset,$Count) if($Count -lt 1 -or $Offset -ne 0 -or $Bytes.Length -ne $Count){throw 'Bad lock record'}};$lock | Add-Member ScriptMethod Flush {param($Durable) if(-not $Durable){throw 'Lock not durable'}};$lock}
        function script:Close-DirectoryAccountLock {param($Lock,$Path,$Keep) if($null -eq $Lock -or -not $Path){throw 'Bad close'};$script:State.Kept=$Keep}
        function script:Get-DirectoryMembershipSnapshot {
            param($Policy,$GroupObjectGuid,$MemberObjectGuid,[pscredential]$Credential)
            if($Policy.DomainController -ne 'dc01.ad.example.com' -or $GroupObjectGuid -ne [guid]'44444444-4444-4444-4444-444444444444' -or $MemberObjectGuid -ne [guid]'33333333-3333-3333-3333-333333333333' -or -not $Credential){throw 'Identity pinning failed'}
            $script:State.Reads++
            if($script:State.Mode -eq 'Reject'){throw 'Protected target'}
            if($script:State.Mode -eq 'Disabled'){throw 'DIRECTORY_USER_DISABLED'}
            $present=$script:State.Mode -eq 'Already' -or ($script:State.Writes -gt 0 -and $script:State.Mode -ne 'Postcheck')
            [pscustomobject]@{Group=[pscustomobject]@{DistinguishedName='CN=ordinary-group,DC=ad,DC=example,DC=com'};User=[pscustomobject]@{DistinguishedName='CN=ordinary-user,DC=ad,DC=example,DC=com'};DirectMember=$present}
        }
        function script:Add-DirectoryMembershipLink {param($Snapshot,$Policy,[pscredential]$Credential) if(-not $Snapshot -or $Policy.DomainController -ne 'dc01.ad.example.com' -or -not $Credential){throw 'Invalid mutation context'};$script:State.Writes++;if($script:State.Mode -eq 'LostResponse'){throw 'SENSITIVE-ERROR-MUST-NOT-ESCAPE'}}
        function script:Write-DirectoryOperationRecord {param($Path,$Record) if(-not $Path -or -not $Record){throw 'Missing evidence'};$script:State.Records++;$script:State.LastRecord=[pscustomobject]@{AzureJobId=$Record.AzureJobId;AzureJobIdSource=$Record.AzureJobIdSource;JobCorrelationStatus=$Record.JobCorrelationStatus};if($script:State.Mode -eq 'Evidence' -and $script:State.Writes -eq 0){throw 'Evidence unavailable'}}
    }
    foreach($mode in @('Success','Already','Preview','MaintenancePreview','Reject','Disabled','LostResponse','Postcheck','Evidence')) {
        & $module {param($Mode) $script:State=@{Mode=$Mode;Writes=0;Reads=0;Records=0;Kept=$false}} $mode
        $policy.WritesEnabled=$mode -ne 'MaintenancePreview'
        $result=$null;$message='';$failureCode=$null
        try {$result=Invoke-DirectoryGroupMember -UserName ordinary-user -GroupName ordinary-group -ChangeReference CHG-1 -Preview:($mode -in @('Preview','MaintenancePreview')) -Credential $credential -Policy $policy -LastRotationUtc ([DateTimeOffset]::UtcNow.AddMinutes(-10)) -AzureJobId '11111111-1111-1111-1111-111111111111' -AzureJobIdSource PSPrivateMetadata -JobCorrelationStatus Captured} catch {$message=$_.Exception.Message;$failureCode=$_.Exception.Data['DirectoryReasonCode']}
        $state=& $module {$script:State}
        if($mode -eq 'Success'){
            Assert-Case ($result.AzureJobId -eq '11111111-1111-1111-1111-111111111111' -and $result.AzureJobIdSource -eq 'PSPrivateMetadata' -and $result.JobCorrelationStatus -eq 'Captured') 'Result job correlation'
            Assert-Case ($state.LastRecord.AzureJobId -eq $result.AzureJobId -and $state.LastRecord.AzureJobIdSource -eq $result.AzureJobIdSource -and $state.LastRecord.JobCorrelationStatus -eq 'Captured') 'Persisted job correlation'
        }
        if($mode -eq 'LostResponse'){Assert-Case ($message -notmatch 'SENSITIVE-ERROR') 'Provider error stays private'}
        if($mode -eq 'Disabled'){Assert-Case ($message -match 'ReasonCode=DIRECTORY_USER_DISABLED' -and $message -match 'User account is disabled' -and $failureCode -eq 'DIRECTORY_USER_DISABLED') 'Disabled account explanation'}
        if($mode -in @('LostResponse','Postcheck')){Assert-Case ($message -like 'DIRECTORY_OPERATION_RECOVERYREQUIRED*' -and $state.Writes -eq 1 -and $state.Kept) $mode}
        elseif($mode -in @('Reject','Disabled','Evidence')){Assert-Case ($message -like 'DIRECTORY_OPERATION_REJECTEDBEFOREWRITE*' -and $state.Writes -eq 0 -and -not $state.Kept) $mode}
        else {$expected=if($mode -eq 'Success'){'VerifiedSuccess'}elseif($mode -eq 'Already'){'AlreadyMember'}else{'Preview'};Assert-Case ($result.Outcome -eq $expected -and $state.Writes -eq [int]($mode -eq 'Success') -and -not $state.Kept) $mode}
    }
    $message='';try{Invoke-DirectoryGroupMember -UserName ordinary-user -GroupName ordinary-group -ChangeReference CHG-2 -Preview $false -Credential $credential -Policy $policy -LastRotationUtc ([DateTimeOffset]::UtcNow.AddHours(-4))}catch{$message=$_.Exception.Message}
    Assert-Case ($message -eq 'DIRECTORY_ROTATION_ADMISSION_DENIED') 'Rotation cutoff'
    $policy.WritesEnabled=$false
    $message='';try{Invoke-DirectoryGroupMember -UserName ordinary-user -GroupName ordinary-group -ChangeReference CHG-3 -Preview $false -Credential $credential -Policy $policy -LastRotationUtc ([DateTimeOffset]::UtcNow.AddMinutes(-1))}catch{$message=$_.Exception.Message}
    Assert-Case ($message -eq 'DIRECTORY_WRITES_NOT_ENABLED') 'Write release gate'
    $policy.WritesEnabled=$true
    foreach($case in @('Identity','Domain','Age','TierRoot')) {
        $copy=$policy | ConvertTo-Json -Depth 8 | ConvertFrom-Json
        switch($case){'Identity'{$copy.ExecutionIdentity='EXAMPLE\other'};'Domain'{$copy.DomainController='http://untrusted'};'Age'{$copy.MaximumPasswordAgeSeconds=0};'TierRoot'{$copy.Tier0DistinguishedName='OU=Tier 0,DC=foreign,DC=example'}}
        $message='';try{Invoke-DirectoryGroupMember -UserName ordinary-user -GroupName ordinary-group -ChangeReference CHG-4 -Preview $true -Credential $credential -Policy $copy -LastRotationUtc ([DateTimeOffset]::UtcNow.AddMinutes(-1))}catch{$message=$_.Exception.Message}
        Assert-Case ($message -in @('DIRECTORY_POLICY_INVALID','DIRECTORY_IDENTITY_INVALID')) ('Configured boundary '+$case)
    }
    foreach($case in @('AdminCount','Builtin','DomainAdmin','Inventory')) {
        $object=[pscustomobject]@{ObjectGUID=[guid]'55555555-5555-5555-5555-555555555555';SID='S-1-5-21-1-2-3-1200';adminCount=0;isCriticalSystemObject=$false}
        switch($case){'AdminCount'{$object.adminCount=1};'Builtin'{$object.SID='S-1-5-32-548'};'DomainAdmin'{$object.SID='S-1-5-21-1-2-3-512'};'Inventory'{$policy.ProtectedObjectGuids=@($object.ObjectGUID.ToString())}}
        $message='';try{Test-DirectoryObjectSafety -Object $object -Policy $policy -Credential $credential}catch{$message=$_.Exception.Message}
        Assert-Case ($message -in @('DIRECTORY_PROTECTED_OBJECT','DIRECTORY_PRIVILEGED_IDENTITY')) $case
        $policy.ProtectedObjectGuids=@()
    }
    & $module {
        function script:Get-ADObject {param($LDAPFilter,$SearchBase,$SearchScope,$Server,[pscredential]$Credential,$ErrorAction) if(-not $LDAPFilter -or -not $SearchBase -or $SearchScope -ne 'Subtree' -or $Server -ne 'dc01.ad.example.com' -or -not $Credential -or $ErrorAction -ne 'Stop'){throw 'Invalid subtree query'};if($script:GuardProtected){[pscustomobject]@{ObjectGUID=[guid]'55555555-5555-5555-5555-555555555555'}}}
        $script:GuardProtected=$true
    }
    $object=[pscustomobject]@{ObjectGUID=[guid]'55555555-5555-5555-5555-555555555555';SID='S-1-5-21-1-2-3-1200';adminCount=0;isCriticalSystemObject=$false;memberOf=@()}
    $message='';try{Test-DirectoryObjectSafety -Object $object -Policy $policy -Credential $credential}catch{$message=$_.Exception.Message}
    Assert-Case ($message -eq 'DIRECTORY_EXCLUDED_SUBTREE') 'Protected subtree'
    & $module {$script:GuardProtected=$false}
    $object.SID='S-1-5-21-4-5-6-1200'
    $message='';try{Test-DirectoryObjectSafety -Object $object -Policy $policy -Credential $credential}catch{$message=$_.Exception.Message}
    Assert-Case ($message -eq 'DIRECTORY_UNKNOWN_IDENTITY_SCOPE') 'Foreign identity denied'
    $object.SID='S-1-5-21-1-2-3-1200';$object.memberOf=@('privileged-parent')
    & $module {
        function script:Get-ADGroup {param($Identity,$Server,[pscredential]$Credential,$Properties,$ErrorAction) if($Identity -ne 'privileged-parent' -or $Server -ne 'dc01.ad.example.com' -or -not $Credential -or -not $Properties -or $ErrorAction -ne 'Stop'){throw 'Unresolved group'};[pscustomobject]@{ObjectGUID=[guid]'66666666-6666-6666-6666-666666666666';SID='S-1-5-21-1-2-3-512';adminCount=0;isCriticalSystemObject=$false;memberOf=@()}}
    }
    $message='';try{Test-DirectoryMembershipSafety -Object $object -Policy $policy -Credential $credential}catch{$message=$_.Exception.Message}
    Assert-Case ($message -eq 'DIRECTORY_PRIVILEGED_IDENTITY') 'Transitive privileged parent'
    $object.memberOf=@('unknown-parent')
    $message='';try{Test-DirectoryMembershipSafety -Object $object -Policy $policy -Credential $credential}catch{$message=$_.Exception.Message}
    Assert-Case ($message -eq 'DIRECTORY_GROUP_LOOKUP_FAILED') 'Unresolved nesting fails closed'
    [pscustomobject]@{Checks=$checks;Failed=0;LiveADContacted=$false;ProductionRuntimeValidated=$false}
} finally {$secret.Dispose();Remove-Module DirectoryOperationLogicTests -ErrorAction SilentlyContinue}
