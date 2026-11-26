#Requires -Version 7.4
# SPDX-License-Identifier: Apache-2.0
[CmdletBinding()]param([ValidateSet('W32Time','WinRM','CertSvc')][string]$ServiceName='W32Time')
$ErrorActionPreference='Stop'
if(-not $IsWindows){throw 'Windows worker required'}
$s=Get-Service -Name $ServiceName
[pscustomobject]@{Computer=[Environment]::MachineName;Service=$s.Name;Status=[string]$s.Status;Utc=[DateTimeOffset]::UtcNow.ToString('o')}
