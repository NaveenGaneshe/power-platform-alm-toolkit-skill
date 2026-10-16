#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }
<#
    Unit tests for skills/pp-integration-agent/assets/IdempotentSync.psm1.
    All HTTP traffic is mocked; no external platform or credentials are needed.

    The second test covers the scenario raised in review: a write that actually commits
    on the external platform, but whose acknowledgement is lost before the caller learns
    it succeeded, followed by a retry with the same idempotency key. It asserts that only
    one record ever exists, not that "no error occurred."

    Run:  Invoke-Pester ./tests -Output Detailed
#>

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '../skills/pp-integration-agent/assets/IdempotentSync.psm1'
    Import-Module $modulePath -Force
}

AfterAll {
    Remove-Module IdempotentSync -Force -ErrorAction SilentlyContinue
}

Describe 'Invoke-IdempotentWrite' {
    BeforeEach {
        $script:MockStore = @()
        $script:PostCallCount = 0
    }

    Context 'happy path: retry before anything happened' {
        It 'creates exactly one record when no matching key exists yet' {
            Mock Invoke-RestMethod -ModuleName IdempotentSync {
                param($Method, $Uri, $Body, $ContentType, $Headers)
                if ($Method -eq 'Get') {
                    $match = $script:MockStore | Where-Object { $_.externalRef -eq 'key-1' }
                    return [pscustomobject]@{ value = @($match) }
                }
                $script:PostCallCount++
                $record = $Body | ConvertFrom-Json
                $record | Add-Member -NotePropertyName id -NotePropertyValue ([guid]::NewGuid().ToString())
                $script:MockStore += $record
                return $record
            }

            $result = Invoke-IdempotentWrite -BaseUri 'https://api.example.test' -Resource 'orders' `
                -IdempotencyKey 'key-1' -IdempotencyField 'externalRef' -Body @{ amount = 100 }

            $result.Created | Should -BeTrue
            $script:MockStore.Count | Should -Be 1
            $script:PostCallCount | Should -Be 1
        }
    }

    Context 'the hard case: lost acknowledgement, then a retry with the same key' {
        It 'does not create a duplicate when the first write committed but the caller never heard back' {
            # Attempt 1's POST actually lands in the backend (the mock store gets mutated),
            # but the mocked call throws afterward -- as if the connection dropped between
            # the server committing the write and the response reaching the caller.
            Mock Invoke-RestMethod -ModuleName IdempotentSync {
                param($Method, $Uri, $Body, $ContentType, $Headers)
                if ($Method -eq 'Get') {
                    $match = $script:MockStore | Where-Object { $_.externalRef -eq 'key-1' }
                    return [pscustomobject]@{ value = @($match) }
                }
                $script:PostCallCount++
                $record = $Body | ConvertFrom-Json
                $record | Add-Member -NotePropertyName id -NotePropertyValue ([guid]::NewGuid().ToString())
                $script:MockStore += $record
                if ($script:PostCallCount -eq 1) {
                    throw 'Simulated network timeout: response lost after the write committed'
                }
                return $record
            }

            # Attempt 1: the write commits server-side, but this call throws -- the caller
            # has no way to know the write actually succeeded.
            {
                Invoke-IdempotentWrite -BaseUri 'https://api.example.test' -Resource 'orders' `
                    -IdempotencyKey 'key-1' -IdempotencyField 'externalRef' -Body @{ amount = 100 }
            } | Should -Throw

            # Sanity check: the "server" really did commit it, same as in production this
            # would have happened whether or not the caller found out.
            $script:MockStore.Count | Should -Be 1

            # Attempt 2: the processing flow retries with the SAME idempotency key, per
            # references/sync-safety.md's requirement that a retry reuse the original key.
            $retryResult = Invoke-IdempotentWrite -BaseUri 'https://api.example.test' -Resource 'orders' `
                -IdempotencyKey 'key-1' -IdempotencyField 'externalRef' -Body @{ amount = 100 }

            $retryResult.Created | Should -BeFalse
            $script:MockStore.Count | Should -Be 1
            $script:PostCallCount | Should -Be 1
        }
    }

    Context 'when the existence check itself cannot find the prior write' {
        It 'still creates a duplicate -- the mechanism is only as reliable as the check' {
            # Same key, same retry -- but this mock simulates an external platform whose
            # query endpoint never actually matches on the idempotency field (an
            # eventual-consistency lag, or a filter that silently isn't implemented).
            # This is the explicit caveat in references/sync-safety.md: mechanism 2 is
            # only safe "as long as the check itself is reliable."
            Mock Invoke-RestMethod -ModuleName IdempotentSync {
                param($Method, $Uri, $Body, $ContentType, $Headers)
                $record = $Body | ConvertFrom-Json
                $record | Add-Member -NotePropertyName id -NotePropertyValue ([guid]::NewGuid().ToString())
                $script:MockStore += $record
                $record
            } -ParameterFilter { $Method -eq 'Post' }

            Mock Invoke-RestMethod -ModuleName IdempotentSync {
                [pscustomobject]@{ value = @() }  # no existence check ever finds anything
            } -ParameterFilter { $Method -eq 'Get' }

            Invoke-IdempotentWrite -BaseUri 'https://api.example.test' -Resource 'orders' `
                -IdempotencyKey 'key-2' -IdempotencyField 'externalRef' -Body @{ amount = 50 } | Out-Null
            Invoke-IdempotentWrite -BaseUri 'https://api.example.test' -Resource 'orders' `
                -IdempotencyKey 'key-2' -IdempotencyField 'externalRef' -Body @{ amount = 50 } | Out-Null

            # This is the failure mode the mandatory idempotency key exists to prevent.
            $script:MockStore.Count | Should -Be 2
        }
    }
}
