# SPDX-License-Identifier: Apache-2.0
function Get-ArcIdentityToken {
    param([Parameter(Mandatory)]$Configuration)
    # Fixed local Arc endpoint; no proxy, redirect, environment override or fallback.
    if(-not $IsWindows -or [Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne 'S-1-5-18'){throw 'RUNBOOK_ARC_IDENTITY_UNAVAILABLE'}
    $handler=$null;$client=$null;$request=$null;$response=$null;$challenge=$null;$reply=$null
    try {
        $handler=[Net.Http.HttpClientHandler]::new()
        $handler.UseProxy=$false;$handler.AllowAutoRedirect=$false
        $client=[Net.Http.HttpClient]::new($handler)
        $client.Timeout=[TimeSpan]::FromSeconds([int]$Configuration.TimeoutSeconds)
        $resource=[uri]::EscapeDataString($Configuration.ManagedIdentityResource)
        $endpoint='http://localhost:40342/metadata/identity/oauth2/token?api-version=2020-06-01&resource='+$resource
        $request=[Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::Get,$endpoint)
        $request.Headers.Add('Metadata','true')
        $response=$client.SendAsync($request).GetAwaiter().GetResult()
        if([int]$response.StatusCode -ne 401){throw 'invalid'}
        $headers=@($response.Headers.WwwAuthenticate)
        if($headers.Count -ne 1 -or $headers[0].Scheme -ine 'Basic'){throw 'invalid'}
        $parameter=[string]$headers[0].Parameter
        if($parameter -notmatch '^realm="?([^"\r\n]+)"?$'){throw 'invalid'}
        $challengePath=[IO.Path]::GetFullPath($Matches[1])
        $tokenRoot=Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'AzureConnectedMachineAgent\tokens'
        $tokenRoot=[IO.Path]::GetFullPath($tokenRoot)
        if([IO.Path]::GetDirectoryName($challengePath) -ine $tokenRoot){throw 'invalid'}
        # Reject links in the challenge file and all ancestors.
        $item=Get-Item -LiteralPath $challengePath -ErrorAction Stop
        if($item.PSIsContainer -or $item.Length -gt 16384){throw 'invalid'}
        for($cursor=$item;$null -ne $cursor;$cursor=if($cursor -is [IO.FileInfo]){$cursor.Directory}else{$cursor.Parent}) {
            if($cursor.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'invalid'}
        }
        $challenge=[IO.File]::ReadAllText($challengePath).Trim()
        if([string]::IsNullOrWhiteSpace($challenge) -or $challenge -match '[\r\n]'){throw 'invalid'}
        $response.Dispose();$response=$null;$request.Dispose();$request=$null
        $request=[Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::Get,$endpoint)
        $request.Headers.Add('Metadata','true')
        $request.Headers.Authorization=[Net.Http.Headers.AuthenticationHeaderValue]::new('Basic',$challenge)
        $response=$client.SendAsync($request).GetAwaiter().GetResult()
        if([int]$response.StatusCode -ne 200){throw 'invalid'}
        $reply=$response.Content.ReadAsStringAsync().GetAwaiter().GetResult() | ConvertFrom-Json
        if($reply.access_token -isnot [string] -or [string]::IsNullOrWhiteSpace($reply.access_token) -or $reply.token_type -ine 'Bearer'){throw 'invalid'}
        return [string]$reply.access_token
    } catch {throw 'RUNBOOK_ARC_IDENTITY_UNAVAILABLE'}
    finally {
        $challenge=$null;$reply=$null
        if($null -ne $response){$response.Dispose()}
        if($null -ne $request){$request.Dispose()}
        if($null -ne $client){$client.Dispose()}elseif($null -ne $handler){$handler.Dispose()}
    }
}
