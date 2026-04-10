BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'src' 'modules' 'AzCostMonitor' 'AzCostMonitor.ps1'
    . $ModulePath
}

Describe 'Invoke-AzCostAnomalyCheck' {
    BeforeAll {
        Mock Get-AzContext {
            [PSCustomObject]@{
                Subscription = [PSCustomObject]@{ Id = 'test-sub-id' }
            }
        }
    }

    Context 'When cost data is available' {
        BeforeAll {
            $mockRows = @()
            for ($i = 37; $i -ge 0; $i--) {
                $date = (Get-Date).AddDays(-$i).ToString('yyyy-MM-dd')
                $cost = if ($i -le 2) { 200 } else { 100 }  # Spike last 3 days
                $mockRows += @(, @($cost, $date, "USD"))
            }

            Mock Invoke-AzCostManagementQuery {
                [PSCustomObject]@{ Row = $mockRows }
            }
        }

        It 'Should detect anomalies when spend exceeds threshold' {
            $result = Invoke-AzCostAnomalyCheck -ThresholdPercent 25 -LookbackDays 30
            $result | Should -Not -BeNullOrEmpty
            $result.AnomaliesFound | Should -BeGreaterThan 0
        }

        It 'Should return baseline average' {
            $result = Invoke-AzCostAnomalyCheck -ThresholdPercent 25 -LookbackDays 30
            $result.BaselineAverage | Should -BeGreaterThan 0
        }

        It 'Should use default subscription when none specified' {
            $result = Invoke-AzCostAnomalyCheck -ThresholdPercent 25
            $result.SubscriptionId | Should -Be 'test-sub-id'
        }
    }

    Context 'When no cost data is returned' {
        BeforeAll {
            Mock Invoke-AzCostManagementQuery { $null }
        }

        It 'Should handle empty results gracefully' {
            $result = Invoke-AzCostAnomalyCheck -ThresholdPercent 25
            $result | Should -BeNullOrEmpty
        }
    }
}

Describe 'Get-AzDailyCostSummary' {
    BeforeAll {
        Mock Get-AzContext {
            [PSCustomObject]@{
                Subscription = [PSCustomObject]@{ Id = 'test-sub-id' }
            }
        }
    }

    Context 'When grouped by ResourceGroup' {
        BeforeAll {
            Mock Invoke-AzCostManagementQuery {
                [PSCustomObject]@{
                    Row = @(
                        @(500, "rg-web", "USD"),
                        @(300, "rg-data", "USD"),
                        @(100, "rg-networking", "USD")
                    )
                }
            }
        }

        It 'Should return sorted cost summary' {
            $result = Get-AzDailyCostSummary -Days 7 -GroupBy "ResourceGroup"
            $result | Should -Not -BeNullOrEmpty
            $result.Count | Should -Be 3
            $result[0].Cost | Should -BeGreaterOrEqual $result[1].Cost
        }
    }
}

Describe 'Watch-AzResourceGroupSpend' {
    BeforeAll {
        Mock Get-AzContext {
            [PSCustomObject]@{
                Subscription = [PSCustomObject]@{ Id = 'test-sub-id' }
            }
        }
    }

    Context 'When spend is within budget' {
        BeforeAll {
            Mock Invoke-AzCostManagementQuery {
                [PSCustomObject]@{ Row = @(, @(2000, "USD")) }
            }
        }

        It 'Should return OK status when under budget' {
            $result = Watch-AzResourceGroupSpend -ResourceGroupName "rg-test" -MonthlyBudget 10000
            $result.Status | Should -Be "OK"
        }
    }

    Context 'When spend exceeds budget' {
        BeforeAll {
            Mock Invoke-AzCostManagementQuery {
                [PSCustomObject]@{ Row = @(, @(11000, "USD")) }
            }
        }

        It 'Should return OVER_BUDGET status' {
            $result = Watch-AzResourceGroupSpend -ResourceGroupName "rg-test" -MonthlyBudget 10000
            $result.Status | Should -Be "OVER_BUDGET"
        }
    }
}
