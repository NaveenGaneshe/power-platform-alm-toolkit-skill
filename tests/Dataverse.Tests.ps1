#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }
<#
    Unit tests for skills/power-platform-alm-toolkit/assets/Dataverse.psm1.
    All HTTP traffic is mocked; no Dataverse environment or credentials are needed.
    Run:  Invoke-Pester ./tests -Output Detailed
#>

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '../skills/power-platform-alm-toolkit/assets/Dataverse.psm1'
    Import-Module $modulePath -Force

    function Get-FakeResponse {
        param([int]$Status = 200, [string]$Content = '', [hashtable]$Headers = @{})
        [pscustomobject]@{ StatusCode = $Status; Content = $Content; Headers = $Headers }
    }
}

AfterAll {
    Remove-Module Dataverse -Force -ErrorAction SilentlyContinue
}

Describe 'Dataverse module' {
    BeforeEach {
        InModuleScope Dataverse {
            $script:Conn = [pscustomobject]@{
                EnvironmentUrl = 'https://contoso.crm.dynamics.com'
                ApiBase        = 'https://contoso.crm.dynamics.com/api/data/v9.2/'
                TenantId       = 'tenant'
                ClientId       = 'client'
                ClientSecret   = 'secret'
                Token          = 'token'
                ExpiresAt      = (Get-Date).AddHours(1)
            }
        }
        Mock Start-Sleep -ModuleName Dataverse { }
        Mock Write-Host -ModuleName Dataverse { }
    }

    Context 'Connect-Dataverse' {
        It 'fails clearly when the environment URL is missing' {
            { Connect-Dataverse -EnvironmentUrl '' -TenantId 't' -ClientId 'c' -ClientSecret 's' } |
                Should -Throw "*'EnvironmentUrl' is required*"
        }
    }

    Context 'Invoke-DataverseRequest' {
        It 'retries after HTTP 429 and then succeeds' {
            $script:calls = 0
            Mock Invoke-WebRequest -ModuleName Dataverse {
                $script:calls++
                if ($script:calls -eq 1) {
                    return Get-FakeResponse -Status 429 -Content '{"error":{"message":"throttled"}}' -Headers @{ 'Retry-After' = @('1') }
                }
                Get-FakeResponse -Content '{"UserId":"abc"}'
            }
            $result = Invoke-DataverseRequest -Method Get -Path 'WhoAmI'
            $result.UserId | Should -Be 'abc'
            Should -Invoke Invoke-WebRequest -ModuleName Dataverse -Times 2 -Exactly
            Should -Invoke Start-Sleep -ModuleName Dataverse -Times 1 -Exactly -ParameterFilter { $Seconds -eq 1 }
        }

        It 'throws the Dataverse error message on a non-retryable failure' {
            Mock Invoke-WebRequest -ModuleName Dataverse {
                Get-FakeResponse -Status 400 -Content '{"error":{"message":"Bad column name"}}'
            }
            { Invoke-DataverseRequest -Method Get -Path 'accounts' } | Should -Throw '*HTTP 400*Bad column name*'
            Should -Invoke Invoke-WebRequest -ModuleName Dataverse -Times 1 -Exactly
        }

        It 'gives up after the maximum number of attempts' {
            Mock Invoke-WebRequest -ModuleName Dataverse { Get-FakeResponse -Status 503 -Content '{"error":{"message":"busy"}}' }
            { Invoke-DataverseRequest -Method Get -Path 'accounts' -MaxAttempts 3 } | Should -Throw '*HTTP 503*'
            Should -Invoke Invoke-WebRequest -ModuleName Dataverse -Times 3 -Exactly
        }
    }

    Context 'Get-DataverseRecords' {
        It 'follows @odata.nextLink across pages' {
            Mock Invoke-WebRequest -ModuleName Dataverse {
                if ($Uri -like '*page=2*') { return Get-FakeResponse -Content '{"value":[{"accountid":"3"}]}' }
                Get-FakeResponse -Content '{"value":[{"accountid":"1"},{"accountid":"2"}],"@odata.nextLink":"https://contoso.crm.dynamics.com/api/data/v9.2/accounts?page=2"}'
            }
            $rows = @(Get-DataverseRecords -EntitySet 'accounts' -Query '$select=accountid')
            $rows.Count | Should -Be 3
            $rows[2].accountid | Should -Be '3'
        }

        It 'stops early when -Top is reached' {
            Mock Invoke-WebRequest -ModuleName Dataverse {
                Get-FakeResponse -Content '{"value":[{"id":"1"},{"id":"2"}],"@odata.nextLink":"https://contoso.crm.dynamics.com/api/data/v9.2/accounts?page=2"}'
            }
            @(Get-DataverseRecords -EntitySet 'accounts' -Top 1).Count | Should -Be 1
            Should -Invoke Invoke-WebRequest -ModuleName Dataverse -Times 1 -Exactly
        }
    }

    Context 'Update-DataverseRecordsBulk' {
        BeforeEach {
            $script:supportsUpdateMultiple = $true
            Mock Invoke-WebRequest -ModuleName Dataverse {
                if ($Uri -like '*EntityDefinitions*') {
                    return Get-FakeResponse -Content '{"LogicalName":"account","EntitySetName":"accounts","PrimaryIdAttribute":"accountid","PrimaryNameAttribute":"name"}'
                }
                if ($Uri -like '*sdkmessagefilters*') {
                    if ($script:supportsUpdateMultiple) { return Get-FakeResponse -Content '{"value":[{"sdkmessagefilterid":"1"}]}' }
                    return Get-FakeResponse -Content '{"value":[]}'
                }
                Get-FakeResponse -Status 204
            }
            $script:changes = @(
                @{ accountid = '1'; statecode = 1; statuscode = 2 },
                @{ accountid = '2'; statecode = 1; statuscode = 2 },
                @{ accountid = '3'; statecode = 1; statuscode = 2 }
            )
        }

        It 'sends nothing in preview mode' {
            $s = Update-DataverseRecordsBulk -LogicalName 'account' -Changes $script:changes -Preview
            $s.Mode | Should -BeLike 'Preview*'
            $s.Succeeded | Should -Be 0
            Should -Invoke Invoke-WebRequest -ModuleName Dataverse -Times 0 -ParameterFilter { $Method -in 'Post', 'Patch' }
        }

        It 'treats -WhatIf as preview' {
            $s = Update-DataverseRecordsBulk -LogicalName 'account' -Changes $script:changes -WhatIf
            $s.Mode | Should -BeLike 'Preview*'
            Should -Invoke Invoke-WebRequest -ModuleName Dataverse -Times 0 -ParameterFilter { $Method -in 'Post', 'Patch' }
        }

        It 'uses UpdateMultiple in batches when the table supports it' {
            $s = Update-DataverseRecordsBulk -LogicalName 'account' -Changes $script:changes -BatchSize 2
            $s.Succeeded | Should -Be 3
            $s.Failed | Should -Be 0
            Should -Invoke Invoke-WebRequest -ModuleName Dataverse -Times 2 -Exactly -ParameterFilter {
                $Method -eq 'Post' -and $Uri -like '*accounts/Microsoft.Dynamics.CRM.UpdateMultiple'
            }
        }

        It 'falls back to PATCH with If-Match * when UpdateMultiple is unsupported' {
            $script:supportsUpdateMultiple = $false
            $s = Update-DataverseRecordsBulk -LogicalName 'account' -Changes $script:changes
            $s.Mode | Should -BeLike 'PATCH per row*'
            $s.Succeeded | Should -Be 3
            Should -Invoke Invoke-WebRequest -ModuleName Dataverse -Times 3 -Exactly -ParameterFilter {
                $Method -eq 'Patch' -and $Headers['If-Match'] -eq '*'
            }
        }

        It 'records a failed batch without stopping the run' {
            Mock Invoke-WebRequest -ModuleName Dataverse -ParameterFilter { $Uri -like '*UpdateMultiple' } {
                Get-FakeResponse -Status 400 -Content '{"error":{"message":"Invalid statuscode"}}'
            }
            $s = Update-DataverseRecordsBulk -LogicalName 'account' -Changes $script:changes -BatchSize 2
            $s.Failed | Should -Be 3
            $s.Errors.Count | Should -Be 2
            $s.Errors[0].Error | Should -BeLike '*Invalid statuscode*'
        }
    }

    Context 'Save-DataverseSnapshot' {
        It 'writes the rows to a JSON file' {
            $file = Save-DataverseSnapshot -Records @(@{ accountid = '1'; statecode = 0 }) -Directory $TestDrive -Name 'accounts'
            Test-Path $file | Should -BeTrue
            (Get-Content $file -Raw | ConvertFrom-Json).accountid | Should -Be '1'
        }
    }
}
