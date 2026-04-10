BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'src' 'modules' 'AzAppServiceOps' 'AzAppServiceOps.ps1'
    . $ModulePath
}

Describe 'Get-AzAppServiceCertStatus' {
    Context 'When certificates are healthy' {
        BeforeAll {
            Mock Get-AzContext { [PSCustomObject]@{ Subscription = [PSCustomObject]@{ Id = 'test-sub' } } }
            Mock Get-AzWebAppCertificate {
                @([PSCustomObject]@{
                    Name = 'cert-prod'; SubjectName = '*.example.com'; Thumbprint = 'ABC123'
                    ExpirationDate = (Get-Date).AddDays(120); ResourceGroupName = 'rg-web'
                })
            }
        }

        It 'Should return OK status for valid certificates' {
            $result = Get-AzAppServiceCertStatus -WarningDaysThreshold 30
            $result[0].Status | Should -Be "OK"
            $result[0].DaysRemaining | Should -BeGreaterThan 30
        }
    }

    Context 'When certificates are expiring soon' {
        BeforeAll {
            Mock Get-AzContext { [PSCustomObject]@{ Subscription = [PSCustomObject]@{ Id = 'test-sub' } } }
            Mock Get-AzWebAppCertificate {
                @([PSCustomObject]@{
                    Name = 'cert-prod'; SubjectName = '*.example.com'; Thumbprint = 'ABC123'
                    ExpirationDate = (Get-Date).AddDays(10); ResourceGroupName = 'rg-web'
                })
            }
        }

        It 'Should flag expiring certificates' {
            $result = Get-AzAppServiceCertStatus -WarningDaysThreshold 30
            $result[0].Status | Should -Be "EXPIRING_SOON"
        }
    }

    Context 'When certificates have expired' {
        BeforeAll {
            Mock Get-AzContext { [PSCustomObject]@{ Subscription = [PSCustomObject]@{ Id = 'test-sub' } } }
            Mock Get-AzWebAppCertificate {
                @([PSCustomObject]@{
                    Name = 'cert-old'; SubjectName = '*.legacy.com'; Thumbprint = 'DEF456'
                    ExpirationDate = (Get-Date).AddDays(-5); ResourceGroupName = 'rg-web'
                })
            }
        }

        It 'Should flag expired certificates' {
            $result = Get-AzAppServiceCertStatus -WarningDaysThreshold 30
            $result[0].Status | Should -Be "EXPIRED"
            $result[0].DaysRemaining | Should -BeLessThan 0
        }
    }
}

Describe 'Get-AzAppServiceHealth' {
    BeforeAll {
        Mock Get-AzWebApp {
            @(
                [PSCustomObject]@{
                    Name = 'app-web-prod'; ResourceGroup = 'rg-web'; State = 'Running'
                    Kind = 'app'; DefaultHostName = 'app-web-prod.azurewebsites.net'
                    HttpsOnly = $true; ServerFarmId = '/sub/rg/providers/farms/asp-prod'; Location = 'eastus'
                },
                [PSCustomObject]@{
                    Name = 'app-api-staging'; ResourceGroup = 'rg-web'; State = 'Stopped'
                    Kind = 'app'; DefaultHostName = 'app-api-staging.azurewebsites.net'
                    HttpsOnly = $true; ServerFarmId = '/sub/rg/providers/farms/asp-staging'; Location = 'eastus'
                }
            )
        }
    }

    It 'Should return health for all apps in resource group' {
        $result = Get-AzAppServiceHealth -ResourceGroupName 'rg-web'
        $result.Count | Should -Be 2
    }

    It 'Should correctly report running and stopped states' {
        $result = Get-AzAppServiceHealth -ResourceGroupName 'rg-web'
        ($result | Where-Object State -eq 'Running').Count | Should -Be 1
        ($result | Where-Object State -eq 'Stopped').Count | Should -Be 1
    }
}
