#Requires -Version 7.4
# SPDX-License-Identifier: Apache-2.0
[CmdletBinding()]param([ValidateSet('chrony','ssh','docker')][string]$ServiceName='chrony')
$ErrorActionPreference='Stop'
if(-not $IsLinux){throw 'Linux worker required'}
$state=& /usr/bin/systemctl is-active -- ($ServiceName+'.service')
$code=$LASTEXITCODE
if($code -notin @(0,3,4)){throw 'Service state query failed'}
[pscustomobject]@{Computer=[Environment]::MachineName;Service=$ServiceName;Status=[string]$state;Utc=[DateTimeOffset]::UtcNow.ToString('o')}
