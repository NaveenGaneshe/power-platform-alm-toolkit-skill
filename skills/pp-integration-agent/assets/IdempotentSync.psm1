<#
    Reference implementation of the "pre-write existence check" idempotency mechanism
    described in references/sync-safety.md (mechanism 2: used when the external platform's
    write API has no documented native idempotent-request support).

    Shape: check for an existing record matching the idempotency key first; only write if
    none is found. This is what makes a retried write safe even when the retry happens
    because a *previous* write's acknowledgement was lost, not because the previous write
    never reached the server -- see tests/IdempotentSync.Tests.ps1 for that exact scenario.
#>

function Invoke-IdempotentWrite {
    <#
        .SYNOPSIS
        Creates a record on an external REST API only if one matching the given
        idempotency key doesn't already exist there.

        .PARAMETER BaseUri
        Base URL of the external platform's API, e.g. https://api.example.test

        .PARAMETER Resource
        The resource/collection path, e.g. 'orders'.

        .PARAMETER IdempotencyKey
        The value generated once per logical transaction and reused on every retry.

        .PARAMETER IdempotencyField
        The field name the existence check filters on and the create request stamps.

        .PARAMETER Body
        The record fields to create, as a hashtable. The idempotency field is added
        automatically; don't include it in Body yourself.

        .PARAMETER Headers
        Extra headers (e.g. Authorization) to send with both requests.

        .OUTPUTS
        An object with `.Record` (the existing or newly created record) and `.Created`
        (boolean -- $false means an existing record was found and nothing was written).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $BaseUri,
        [Parameter(Mandatory)] [string] $Resource,
        [Parameter(Mandatory)] [string] $IdempotencyKey,
        [Parameter(Mandatory)] [string] $IdempotencyField,
        [Parameter(Mandatory)] [hashtable] $Body,
        [hashtable] $Headers = @{}
    )

    $encodedKey = [uri]::EscapeDataString($IdempotencyKey)
    $queryUri = "$BaseUri/$Resource`?`$filter=$IdempotencyField eq '$encodedKey'"

    $existing = Invoke-RestMethod -Method Get -Uri $queryUri -Headers $Headers -ErrorAction Stop

    if ($existing -and $existing.value -and $existing.value.Count -gt 0) {
        return [pscustomobject]@{
            Record  = $existing.value[0]
            Created = $false
        }
    }

    $bodyWithKey = $Body.Clone()
    $bodyWithKey[$IdempotencyField] = $IdempotencyKey

    $created = Invoke-RestMethod -Method Post -Uri "$BaseUri/$Resource" `
        -Body ($bodyWithKey | ConvertTo-Json) -ContentType 'application/json' `
        -Headers $Headers -ErrorAction Stop

    return [pscustomobject]@{
        Record  = $created
        Created = $true
    }
}

Export-ModuleMember -Function Invoke-IdempotentWrite
