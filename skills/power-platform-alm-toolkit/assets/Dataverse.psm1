#Requires -Version 7.2
<#
.SYNOPSIS
    Shared Dataverse Web API helpers for the Power Platform Ops Toolkit.
.DESCRIPTION
    Cross-platform (Windows/macOS/Linux) PowerShell 7 module providing:
      - Authentication: client secret, or GitHub Actions OIDC federation (no stored secret)
      - Requests with automatic retry on service-protection limits (429) and transient errors
      - Paging over @odata.nextLink
      - Bulk updates via UpdateMultiple (with per-record PATCH fallback), preview mode and snapshots
      - Run summaries written to the GitHub Actions job summary
    Copy to shared/scripts/Dataverse.psm1 in the toolkit repository.
.NOTES
    Environment variables read by Connect-Dataverse when parameters are omitted:
      DATAVERSE_URL, AZURE_TENANT_ID, AZURE_CLIENT_ID, AZURE_CLIENT_SECRET
    OIDC is used automatically when AZURE_CLIENT_SECRET is empty and the job has `permissions: id-token: write`.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:Conn = $null
$script:ApiVersion = 'v9.2'
$script:RetryStatusCodes = @(429, 502, 503, 504)

function Get-GitHubOidcToken {
    [CmdletBinding()]
    param([string]$Audience = 'api://AzureADTokenExchange')
    if (-not $env:ACTIONS_ID_TOKEN_REQUEST_URL -or -not $env:ACTIONS_ID_TOKEN_REQUEST_TOKEN) {
        throw "No client secret supplied and GitHub OIDC is unavailable. Add 'permissions: id-token: write' to the workflow or set AZURE_CLIENT_SECRET."
    }
    $uri = "$($env:ACTIONS_ID_TOKEN_REQUEST_URL)&audience=$([uri]::EscapeDataString($Audience))"
    $resp = Invoke-RestMethod -Method Get -Uri $uri -Headers @{ Authorization = "Bearer $($env:ACTIONS_ID_TOKEN_REQUEST_TOKEN)" }
    return $resp.value
}

function Get-DataverseAccessToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$EnvironmentUrl,
        [Parameter(Mandatory)][string]$TenantId,
        [Parameter(Mandatory)][string]$ClientId,
        [string]$ClientSecret
    )
    $body = @{
        grant_type = 'client_credentials'
        client_id  = $ClientId
        scope      = "$($EnvironmentUrl.TrimEnd('/'))/.default"
    }
    if ([string]::IsNullOrWhiteSpace($ClientSecret)) {
        $body.client_assertion_type = 'urn:ietf:params:oauth:client-assertion-type:jwt-bearer'
        $body.client_assertion = Get-GitHubOidcToken
    }
    else {
        $body.client_secret = $ClientSecret
    }
    $resp = Invoke-RestMethod -Method Post -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" `
        -ContentType 'application/x-www-form-urlencoded' -Body $body
    return [pscustomobject]@{
        Token     = $resp.access_token
        ExpiresAt = (Get-Date).AddSeconds([int]$resp.expires_in - 300)
    }
}

function Connect-Dataverse {
    <#
    .SYNOPSIS Authenticates to a Dataverse environment and caches the connection for this session.
    #>
    [CmdletBinding()]
    param(
        [string]$EnvironmentUrl = $env:DATAVERSE_URL,
        [string]$TenantId = $env:AZURE_TENANT_ID,
        [string]$ClientId = $env:AZURE_CLIENT_ID,
        [string]$ClientSecret = $env:AZURE_CLIENT_SECRET
    )
    foreach ($pair in @(@('EnvironmentUrl', $EnvironmentUrl), @('TenantId', $TenantId), @('ClientId', $ClientId))) {
        if ([string]::IsNullOrWhiteSpace($pair[1])) { throw "Connect-Dataverse: '$($pair[0])' is required (parameter or environment variable)." }
    }
    $EnvironmentUrl = $EnvironmentUrl.TrimEnd('/')
    $tok = Get-DataverseAccessToken -EnvironmentUrl $EnvironmentUrl -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret
    $script:Conn = [pscustomobject]@{
        EnvironmentUrl = $EnvironmentUrl
        ApiBase        = "$EnvironmentUrl/api/data/$($script:ApiVersion)/"
        TenantId       = $TenantId
        ClientId       = $ClientId
        ClientSecret   = $ClientSecret
        Token          = $tok.Token
        ExpiresAt      = $tok.ExpiresAt
    }
    $who = Invoke-DataverseRequest -Method Get -Path 'WhoAmI'
    Write-Host "Connected to $EnvironmentUrl as user $($who.UserId)"
    return $who
}

function Get-DataverseHeaders {
    if (-not $script:Conn) { throw 'Not connected. Call Connect-Dataverse first.' }
    if ((Get-Date) -ge $script:Conn.ExpiresAt) {
        $tok = Get-DataverseAccessToken -EnvironmentUrl $script:Conn.EnvironmentUrl -TenantId $script:Conn.TenantId `
            -ClientId $script:Conn.ClientId -ClientSecret $script:Conn.ClientSecret
        $script:Conn.Token = $tok.Token
        $script:Conn.ExpiresAt = $tok.ExpiresAt
    }
    return @{
        'Authorization'    = "Bearer $($script:Conn.Token)"
        'OData-MaxVersion' = '4.0'
        'OData-Version'    = '4.0'
        'Accept'           = 'application/json'
        'Prefer'           = 'odata.include-annotations="*", odata.maxpagesize=5000'
    }
}

function Invoke-DataverseRequest {
    <#
    .SYNOPSIS Sends one Web API request with retry on 429/502/503/504. -Path is relative to the API base or an absolute URL.
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('Get', 'Post', 'Patch', 'Delete', 'Put')][string]$Method = 'Get',
        [Parameter(Mandatory)][string]$Path,
        $Body,
        [hashtable]$Headers = @{},
        [int]$MaxAttempts = 5
    )
    $uri = if ($Path -match '^https://') { $Path } else { "$($script:Conn.ApiBase)$($Path.TrimStart('/'))" }
    $json = if ($null -ne $Body) { $Body | ConvertTo-Json -Depth 20 -Compress } else { $null }

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        $h = Get-DataverseHeaders
        foreach ($k in $Headers.Keys) { $h[$k] = $Headers[$k] }
        $params = @{ Method = $Method; Uri = $uri; Headers = $h; SkipHttpErrorCheck = $true }
        if ($json) { $params.Body = [Text.Encoding]::UTF8.GetBytes($json); $params.ContentType = 'application/json; charset=utf-8' }

        $resp = Invoke-WebRequest @params
        $status = [int]$resp.StatusCode

        if ($status -ge 200 -and $status -lt 300) {
            if ([string]::IsNullOrWhiteSpace($resp.Content)) {
                $entityId = $resp.Headers['OData-EntityId'] | Select-Object -First 1
                return [pscustomobject]@{ StatusCode = $status; EntityId = $entityId }
            }
            return $resp.Content | ConvertFrom-Json -Depth 50
        }

        if ($status -in $script:RetryStatusCodes -and $attempt -lt $MaxAttempts) {
            $retryAfter = $resp.Headers['Retry-After'] | Select-Object -First 1
            $wait = if ($retryAfter) { [int]$retryAfter } else { [math]::Min(60, [math]::Pow(2, $attempt)) }
            Write-Warning "HTTP $status on $Method $uri. Waiting $wait s (attempt $attempt of $MaxAttempts)."
            Start-Sleep -Seconds $wait
            continue
        }

        $message = try { ($resp.Content | ConvertFrom-Json).error.message } catch { $resp.Content }
        throw "Dataverse $Method $uri failed with HTTP ${status}: $message"
    }
}

function Get-DataverseRecords {
    <#
    .SYNOPSIS Returns all rows for an OData query, following @odata.nextLink.
    .EXAMPLE Get-DataverseRecords -EntitySet accounts -Query '$select=accountid,name&$filter=statecode eq 0'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$EntitySet,
        [string]$Query,
        [int]$Top = 0
    )
    $next = if ($Query) { "$EntitySet`?$Query" } else { $EntitySet }
    $results = [System.Collections.Generic.List[object]]::new()
    while ($next) {
        $page = Invoke-DataverseRequest -Method Get -Path $next
        foreach ($row in $page.value) {
            $results.Add($row)
            if ($Top -gt 0 -and $results.Count -ge $Top) { return $results.ToArray() }
        }
        $next = if ($page.PSObject.Properties.Name -contains '@odata.nextLink') { $page.'@odata.nextLink' } else { $null }
    }
    return $results.ToArray()
}

function Get-DataverseEntityMetadata {
    <#
    .SYNOPSIS Resolves a table's logical name to entity set name and primary id column.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$LogicalName)
    $m = Invoke-DataverseRequest -Method Get -Path "EntityDefinitions(LogicalName='$LogicalName')?`$select=LogicalName,EntitySetName,PrimaryIdAttribute,PrimaryNameAttribute"
    return [pscustomobject]@{
        LogicalName          = $m.LogicalName
        EntitySetName        = $m.EntitySetName
        PrimaryIdAttribute   = $m.PrimaryIdAttribute
        PrimaryNameAttribute = $m.PrimaryNameAttribute
    }
}

function Test-DataverseMessageSupport {
    <#
    .SYNOPSIS True when the table supports a message such as UpdateMultiple or CreateMultiple.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$LogicalName,
        [Parameter(Mandatory)][string]$MessageName
    )
    $q = "`$select=sdkmessagefilterid&`$filter=primaryobjecttypecode eq '$LogicalName' and sdkmessageid/name eq '$MessageName'"
    $rows = @(Get-DataverseRecords -EntitySet 'sdkmessagefilters' -Query $q -Top 1)
    return ($rows.Count -gt 0)
}

function Save-DataverseSnapshot {
    <#
    .SYNOPSIS Writes rows to a timestamped JSON file so a change can be reviewed or reverted.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Records,
        [Parameter(Mandatory)][string]$Directory,
        [Parameter(Mandatory)][string]$Name
    )
    New-Item -ItemType Directory -Force -Path $Directory | Out-Null
    $file = Join-Path $Directory ("{0}-{1}.json" -f $Name, (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $Records | ConvertTo-Json -Depth 20 | Set-Content -Path $file -Encoding utf8
    Write-Host "Snapshot written: $file ($($Records.Count) rows)"
    return $file
}

function Update-DataverseRecordsBulk {
    <#
    .SYNOPSIS
        Updates many rows. Each item in -Changes must contain the primary id column plus only the columns to change.
        Uses UpdateMultiple in batches when supported, otherwise PATCH per row with If-Match: * (never creates rows).
        With -Preview (or the standard -WhatIf), nothing is sent and a preview summary is returned.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$LogicalName,
        [Parameter(Mandatory)][AllowEmptyCollection()][hashtable[]]$Changes,
        [ValidateRange(1, 1000)][int]$BatchSize = 200,
        [switch]$Preview,
        [switch]$BypassCustomPlugins
    )
    $meta = Get-DataverseEntityMetadata -LogicalName $LogicalName
    $idCol = $meta.PrimaryIdAttribute
    $summary = [pscustomobject]@{ Table = $LogicalName; Requested = $Changes.Count; Succeeded = 0; Failed = 0; Mode = ''; Errors = [System.Collections.Generic.List[object]]::new() }

    if ($Preview -or -not $PSCmdlet.ShouldProcess("$($Changes.Count) row(s) in table '$LogicalName'", 'Update')) {
        $summary.Mode = 'Preview (no changes sent)'
        return $summary
    }
    if ($Changes.Count -eq 0) { $summary.Mode = 'Nothing to do'; return $summary }

    $extra = @{}
    if ($BypassCustomPlugins) { $extra['MSCRM.BypassCustomPluginExecution'] = 'true' }

    if (Test-DataverseMessageSupport -LogicalName $LogicalName -MessageName 'UpdateMultiple') {
        $summary.Mode = "UpdateMultiple (batch size $BatchSize)"
        for ($i = 0; $i -lt $Changes.Count; $i += $BatchSize) {
            $slice = @($Changes[$i..([math]::Min($i + $BatchSize, $Changes.Count) - 1)])
            $targets = foreach ($c in $slice) {
                $t = @{ '@odata.type' = "Microsoft.Dynamics.CRM.$LogicalName" }
                foreach ($k in $c.Keys) { $t[$k] = $c[$k] }
                $t
            }
            try {
                Invoke-DataverseRequest -Method Post -Path "$($meta.EntitySetName)/Microsoft.Dynamics.CRM.UpdateMultiple" `
                    -Body @{ Targets = @($targets) } -Headers $extra | Out-Null
                $summary.Succeeded += $slice.Count
            }
            catch {
                # Standard tables roll back the whole batch on any error.
                $summary.Failed += $slice.Count
                $summary.Errors.Add([pscustomobject]@{ Batch = [int]($i / $BatchSize) + 1; Ids = ($slice | ForEach-Object { $_[$idCol] }) -join ','; Error = $_.Exception.Message })
            }
            Write-Host ("Progress: {0}/{1}" -f [math]::Min($i + $BatchSize, $Changes.Count), $Changes.Count)
        }
    }
    else {
        $summary.Mode = 'PATCH per row (UpdateMultiple not supported on this table)'
        $h = @{ 'If-Match' = '*' } + $extra
        foreach ($c in $Changes) {
            $id = $c[$idCol]
            $body = @{}
            foreach ($k in $c.Keys) { if ($k -ne $idCol) { $body[$k] = $c[$k] } }
            try {
                Invoke-DataverseRequest -Method Patch -Path "$($meta.EntitySetName)($id)" -Body $body -Headers $h | Out-Null
                $summary.Succeeded++
            }
            catch {
                $summary.Failed++
                $summary.Errors.Add([pscustomobject]@{ Ids = $id; Error = $_.Exception.Message })
            }
        }
    }
    return $summary
}

function Write-OperationSummary {
    <#
    .SYNOPSIS Writes a markdown summary to the console and, in GitHub Actions, to the job summary page.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Facts,
        [object[]]$Errors = @()
    )
    $lines = @("## $Title", '', '| Item | Value |', '|---|---|')
    foreach ($k in $Facts.Keys) { $lines += "| $k | $($Facts[$k]) |" }
    if ($Errors.Count -gt 0) {
        $lines += '', '### Problems', ''
        foreach ($e in ($Errors | Select-Object -First 50)) { $lines += "- $($e | ConvertTo-Json -Compress)" }
        if ($Errors.Count -gt 50) { $lines += "- ...and $($Errors.Count - 50) more (see the results artifact)" }
    }
    $md = $lines -join [Environment]::NewLine
    Write-Host $md
    if ($env:GITHUB_STEP_SUMMARY) { Add-Content -Path $env:GITHUB_STEP_SUMMARY -Value $md -Encoding utf8 }
}

Export-ModuleMember -Function Connect-Dataverse, Invoke-DataverseRequest, Get-DataverseRecords, Get-DataverseEntityMetadata,
    Test-DataverseMessageSupport, Save-DataverseSnapshot, Update-DataverseRecordsBulk, Write-OperationSummary, Get-DataverseAccessToken
