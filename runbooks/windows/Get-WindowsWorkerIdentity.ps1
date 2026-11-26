#Requires -Version 7.4
# SPDX-License-Identifier: Apache-2.0
[CmdletBinding()]param()
$ErrorActionPreference='Stop'
if(-not $IsWindows){throw 'Windows worker required'}
[pscustomobject]@{Computer=[Environment]::MachineName;Identity=[Security.Principal.WindowsIdentity]::GetCurrent().Name;IdentitySid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;PowerShell=$PSVersionTable.PSVersion.ToString();Utc=[DateTimeOffset]::UtcNow.ToString('o')}
