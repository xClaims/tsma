#Requires -Version 7.4
# SPDX-License-Identifier: Apache-2.0
[CmdletBinding()]param()
$ErrorActionPreference='Stop'
if(-not $IsLinux){throw 'Linux worker required'}
$uid=& /usr/bin/id -u
if($LASTEXITCODE -ne 0){throw 'Identity lookup failed'}
[pscustomobject]@{Computer=[Environment]::MachineName;Identity=[Environment]::UserName;Uid=$uid;PowerShell=$PSVersionTable.PSVersion.ToString();Utc=[DateTimeOffset]::UtcNow.ToString('o')}
