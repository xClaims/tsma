#Requires -Version 5.1
# SPDX-License-Identifier: Apache-2.0
[CmdletBinding()]param()
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$checks=0
foreach($file in Get-ChildItem -LiteralPath $root -Recurse -File -Filter '*.md' | Where-Object {$_.FullName -notmatch '[\\/]\.git[\\/]'}) {
    $content=Get-Content -LiteralPath $file.FullName -Raw
    foreach($match in [regex]::Matches($content,'\[[^\]]+\]\(([^)]+)\)')) {
        $link=$match.Groups[1].Value
        if($link -match '^(https?://|mailto:|#)'){continue}
        $relative=($link -split '#')[0]
        if(-not (Test-Path -LiteralPath (Join-Path $file.DirectoryName $relative))){throw ('Broken documentation link: '+$file.Name+' -> '+$link)};$checks++
    }
    foreach($match in [regex]::Matches($content,'(?ms)^~~~powershell\s*\r?\n(.*?)^~~~')) {
        $tokens=$null;$errors=$null
        $null=[Management.Automation.Language.Parser]::ParseInput($match.Groups[1].Value,[ref]$tokens,[ref]$errors)
        if($errors.Count){throw ('Documentation PowerShell parse error: '+$file.Name)};$checks++
    }
}
foreach($relative in @('docs/GETTING-STARTED.md','docs/PREREQUISITES.md','docs/setup/AD-DIRECTORY.md','docs/setup/CERTIFICATES-LDAPS.md','docs/setup/OPENBAO-SERVER.md','docs/setup/OPENBAO-LDAP.md','docs/setup/AZURE-WORKER.md','docs/setup/ENTRA-OPENBAO.md','docs/setup/OPERATOR-ACCESS.md','docs/RESOURCES.md','examples/DeploymentWorksheet.example.json')) {
    $item=Get-Item -LiteralPath (Join-Path $root $relative) -ErrorAction Stop
    if($item.Length -lt 100){throw ('Community resource is empty: '+$relative)};$checks++
}
[pscustomobject]@{Checks=$checks;Failed=0;ExternalLinksFetched=$false}
