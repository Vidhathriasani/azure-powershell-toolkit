function Invoke-AzCostAnomalyCheck {
    <#
    .SYNOPSIS
        Detects cost anomalies by comparing current spend against a rolling average baseline.

    .DESCRIPTION
        Queries Azure Cost Management for daily spend data, computes a rolling average over the
        specified lookback window, and flags any day where actual spend exceeds the baseline
        by more than the configured threshold percentage. Optionally sends alerts via the
        toolkit's unified notification system.

    .PARAMETER SubscriptionId
        Target subscription ID. If omitted, uses the current Az context subscription.

    .PARAMETER ThresholdPercent
        Percentage above the rolling average that triggers an anomaly flag. Default: 25.

    .PARAMETER LookbackDays
        Number of days to use for computing the rolling average baseline. Default: 30.

    .PARAMETER SendAlert
        If specified, sends an alert notification for detected anomalies.

    .EXAMPLE
        Invoke-AzCostAnomalyCheck -ThresholdPercent 20 -LookbackDays 14

    .EXAMPLE
        Invoke-AzCostAnomalyCheck -SubscriptionId "xxxx-xxxx" -SendAlert
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$SubscriptionId,

        [Parameter()]
        [int]$ThresholdPercent = 25,

        [Parameter()]
        [int]$LookbackDays = 30,

        [Parameter()]
        [switch]$SendAlert
    )

    begin {
        if (-not $SubscriptionId) {
            $context = Get-AzContext
            $SubscriptionId = $context.Subscription.Id
            Write-Verbose "Using current context subscription: $SubscriptionId"
        }

        $scope = "/subscriptions/$SubscriptionId"
        $endDate = (Get-Date).ToString('yyyy-MM-dd')
        $startDate = (Get-Date).AddDays(-($LookbackDays + 7)).ToString('yyyy-MM-dd')
    }

    process {
        Write-Host "Analyzing cost data for subscription $SubscriptionId..." -ForegroundColor Cyan
        Write-Host "Lookback window: $LookbackDays days | Anomaly threshold: ${ThresholdPercent}%" -ForegroundColor Gray

        try {
            $costQuery = @{
                Type       = "ActualCost"
                Timeframe  = "Custom"
                TimePeriod = @{
                    From = $startDate
                    To   = $endDate
                }
                Dataset    = @{
                    Granularity = "Daily"
                    Aggregation = @{
                        totalCost = @{
                            name     = "Cost"
                            function = "Sum"
                        }
                    }
                }
            }

            $costData = Invoke-AzCostManagementQuery -Scope $scope -Type $costQuery.Type `
                -Timeframe "Custom" -TimePeriodFrom $startDate -TimePeriodTo $endDate `
                -DatasetGranularity "Daily" -DatasetAggregation $costQuery.Dataset.Aggregation

            if (-not $costData -or -not $costData.Row) {
                Write-Warning "No cost data returned. Verify subscription access and Cost Management permissions."
                return
            }

            $dailyCosts = $costData.Row | ForEach-Object {
                [PSCustomObject]@{
                    Date = [datetime]$_[1]
                    Cost = [decimal]$_[0]
                }
            } | Sort-Object Date

            # Compute rolling average (excluding the last 7 days for baseline)
            $baselineCosts = $dailyCosts | Select-Object -First $LookbackDays
            $recentCosts = $dailyCosts | Select-Object -Last 7

            if ($baselineCosts.Count -eq 0) {
                Write-Warning "Insufficient baseline data for anomaly detection."
                return
            }

            $rollingAverage = ($baselineCosts | Measure-Object -Property Cost -Average).Average
            $anomalyThreshold = $rollingAverage * (1 + ($ThresholdPercent / 100))

            Write-Host "`nBaseline rolling average: `$$([math]::Round($rollingAverage, 2))/day" -ForegroundColor White
            Write-Host "Anomaly threshold (${ThresholdPercent}% above): `$$([math]::Round($anomalyThreshold, 2))/day" -ForegroundColor White

            $anomalies = @()
            foreach ($day in $recentCosts) {
                $status = if ($day.Cost -gt $anomalyThreshold) { "ANOMALY" } else { "Normal" }
                $deviation = if ($rollingAverage -gt 0) {
                    [math]::Round((($day.Cost - $rollingAverage) / $rollingAverage) * 100, 1)
                } else { 0 }

                $result = [PSCustomObject]@{
                    Date      = $day.Date.ToString('yyyy-MM-dd')
                    DailyCost = [math]::Round($day.Cost, 2)
                    Baseline  = [math]::Round($rollingAverage, 2)
                    Deviation = "${deviation}%"
                    Status    = $status
                }

                if ($status -eq "ANOMALY") {
                    $anomalies += $result
                }

                $color = if ($status -eq "ANOMALY") { "Red" } else { "Green" }
                Write-Host "  $($result.Date): `$$($result.DailyCost) ($($result.Deviation) from baseline) [$status]" -ForegroundColor $color
            }

            if ($anomalies.Count -gt 0 -and $SendAlert) {
                $alertMessage = "Detected $($anomalies.Count) cost anomalies in the last 7 days.`n"
                $alertMessage += ($anomalies | ForEach-Object { "$($_.Date): `$$($_.DailyCost) ($($_.Deviation) above baseline)" }) -join "`n"

                Send-AlertNotification -Title "Azure Cost Anomaly Detected" `
                    -Message $alertMessage -Severity "Warning"
            }

            return [PSCustomObject]@{
                SubscriptionId  = $SubscriptionId
                BaselineAverage = [math]::Round($rollingAverage, 2)
                Threshold       = [math]::Round($anomalyThreshold, 2)
                AnomaliesFound  = $anomalies.Count
                Anomalies       = $anomalies
                RecentCosts     = $recentCosts
            }
        }
        catch {
            Write-Error "Failed to query cost data: $_"
        }
    }
}

function Get-AzDailyCostSummary {
    <#
    .SYNOPSIS
        Generates a daily cost summary grouped by resource group, service, or resource type.

    .PARAMETER SubscriptionId
        Target subscription ID.

    .PARAMETER Days
        Number of days to include in the summary. Default: 7.

    .PARAMETER GroupBy
        Grouping dimension: ResourceGroup, ServiceName, or ResourceType. Default: ResourceGroup.

    .EXAMPLE
        Get-AzDailyCostSummary -Days 14 -GroupBy "ServiceName"
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$SubscriptionId,

        [Parameter()]
        [int]$Days = 7,

        [Parameter()]
        [ValidateSet("ResourceGroup", "ServiceName", "ResourceType")]
        [string]$GroupBy = "ResourceGroup"
    )

    if (-not $SubscriptionId) {
        $SubscriptionId = (Get-AzContext).Subscription.Id
    }

    $scope = "/subscriptions/$SubscriptionId"
    $endDate = (Get-Date).ToString('yyyy-MM-dd')
    $startDate = (Get-Date).AddDays(-$Days).ToString('yyyy-MM-dd')

    Write-Host "Fetching cost summary for last $Days days grouped by $GroupBy..." -ForegroundColor Cyan

    try {
        $results = Invoke-AzCostManagementQuery -Scope $scope -Type "ActualCost" `
            -Timeframe "Custom" -TimePeriodFrom $startDate -TimePeriodTo $endDate `
            -DatasetGranularity "None" `
            -DatasetGrouping @(@{ Type = "Dimension"; Name = $GroupBy })

        if (-not $results -or -not $results.Row) {
            Write-Warning "No cost data returned."
            return
        }

        $summary = $results.Row | ForEach-Object {
            [PSCustomObject]@{
                GroupName = $_[1]
                Cost      = [math]::Round([decimal]$_[0], 2)
                Currency  = $_[2]
            }
        } | Sort-Object Cost -Descending

        $totalCost = ($summary | Measure-Object -Property Cost -Sum).Sum

        Write-Host "`nCost Summary ($startDate to $endDate)" -ForegroundColor White
        Write-Host ("=" * 60) -ForegroundColor Gray

        foreach ($item in $summary) {
            $percentage = if ($totalCost -gt 0) { [math]::Round(($item.Cost / $totalCost) * 100, 1) } else { 0 }
            $bar = "#" * [math]::Min([math]::Floor($percentage / 2), 30)
            Write-Host "  $($item.GroupName.PadRight(35)) `$$($item.Cost.ToString().PadLeft(10))  $bar ${percentage}%" -ForegroundColor White
        }

        Write-Host ("=" * 60) -ForegroundColor Gray
        Write-Host "  TOTAL:$(' ' * 28) `$$([math]::Round($totalCost, 2))" -ForegroundColor Yellow

        return $summary
    }
    catch {
        Write-Error "Failed to fetch cost summary: $_"
    }
}

function Watch-AzResourceGroupSpend {
    <#
    .SYNOPSIS
        Monitors a specific resource group against a monthly budget threshold.

    .PARAMETER ResourceGroupName
        Name of the resource group to monitor.

    .PARAMETER MonthlyBudget
        Monthly budget in USD. Alerts when current month spend exceeds this value.

    .PARAMETER WarningPercent
        Percentage of budget that triggers a warning. Default: 80.

    .EXAMPLE
        Watch-AzResourceGroupSpend -ResourceGroupName "rg-production" -MonthlyBudget 5000
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ResourceGroupName,

        [Parameter(Mandatory)]
        [decimal]$MonthlyBudget,

        [Parameter()]
        [int]$WarningPercent = 80
    )

    $subscriptionId = (Get-AzContext).Subscription.Id
    $scope = "/subscriptions/$subscriptionId"
    $startDate = (Get-Date -Day 1).ToString('yyyy-MM-dd')
    $endDate = (Get-Date).ToString('yyyy-MM-dd')
    $daysInMonth = [DateTime]::DaysInMonth((Get-Date).Year, (Get-Date).Month)
    $daysElapsed = (Get-Date).Day

    Write-Host "Monitoring spend for resource group: $ResourceGroupName" -ForegroundColor Cyan
    Write-Host "Monthly budget: `$$MonthlyBudget | Warning at ${WarningPercent}%" -ForegroundColor Gray

    try {
        $results = Invoke-AzCostManagementQuery -Scope $scope -Type "ActualCost" `
            -Timeframe "Custom" -TimePeriodFrom $startDate -TimePeriodTo $endDate `
            -DatasetGranularity "None" `
            -DatasetFilter @{
                Dimensions = @{
                    Name     = "ResourceGroup"
                    Operator = "In"
                    Values   = @($ResourceGroupName)
                }
            }

        $currentSpend = if ($results -and $results.Row) {
            [math]::Round([decimal]$results.Row[0][0], 2)
        } else { 0 }

        $projectedSpend = if ($daysElapsed -gt 0) {
            [math]::Round(($currentSpend / $daysElapsed) * $daysInMonth, 2)
        } else { 0 }

        $budgetUsedPercent = if ($MonthlyBudget -gt 0) {
            [math]::Round(($currentSpend / $MonthlyBudget) * 100, 1)
        } else { 0 }

        $status = if ($budgetUsedPercent -ge 100) {
            "OVER_BUDGET"
        } elseif ($budgetUsedPercent -ge $WarningPercent) {
            "WARNING"
        } else {
            "OK"
        }

        $statusColor = switch ($status) {
            "OVER_BUDGET" { "Red" }
            "WARNING"     { "Yellow" }
            "OK"          { "Green" }
        }

        Write-Host "`n  Resource Group:   $ResourceGroupName" -ForegroundColor White
        Write-Host "  Current Spend:    `$$currentSpend ($daysElapsed of $daysInMonth days)" -ForegroundColor White
        Write-Host "  Projected Spend:  `$$projectedSpend" -ForegroundColor White
        Write-Host "  Budget Used:      ${budgetUsedPercent}%" -ForegroundColor $statusColor
        Write-Host "  Status:           $status" -ForegroundColor $statusColor

        return [PSCustomObject]@{
            ResourceGroup    = $ResourceGroupName
            CurrentSpend     = $currentSpend
            MonthlyBudget    = $MonthlyBudget
            ProjectedSpend   = $projectedSpend
            BudgetUsedPct    = $budgetUsedPercent
            DaysElapsed      = $daysElapsed
            DaysInMonth      = $daysInMonth
            Status           = $status
        }
    }
    catch {
        Write-Error "Failed to query resource group spend: $_"
    }
}
