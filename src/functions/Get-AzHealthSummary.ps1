function Get-AzHealthSummary {
    <#
    .SYNOPSIS
        Generates an aggregated health dashboard across all monitored Azure services.

    .DESCRIPTION
        Runs health checks across App Services, VPN gateways, and Traffic Manager profiles
        in the specified resource groups and produces a unified summary report.

    .PARAMETER ResourceGroupNames
        Array of resource group names to include in the health check.

    .PARAMETER IncludeCostCheck
        If specified, includes a cost anomaly check in the summary.

    .EXAMPLE
        Get-AzHealthSummary -ResourceGroupNames @("rg-web", "rg-networking")
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$ResourceGroupNames,

        [Parameter()]
        [switch]$IncludeCostCheck
    )

    $summary = [PSCustomObject]@{
        Timestamp     = Get-Date
        OverallStatus = "Healthy"
        AppServices   = @()
        VpnGateways   = @()
        Certificates  = @()
        CostStatus    = $null
        Issues        = @()
    }

    Write-Host "`n=====================================" -ForegroundColor Cyan
    Write-Host "  AZURE HEALTH SUMMARY DASHBOARD" -ForegroundColor Cyan
    Write-Host "  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
    Write-Host "=====================================" -ForegroundColor Cyan

    foreach ($rg in $ResourceGroupNames) {
        Write-Host "`n--- Resource Group: $rg ---" -ForegroundColor White

        # App Service Health
        try {
            $apps = Get-AzAppServiceHealth -ResourceGroupName $rg -ErrorAction SilentlyContinue
            if ($apps) {
                $summary.AppServices += $apps
                $stoppedApps = $apps | Where-Object State -ne "Running"
                if ($stoppedApps) {
                    $summary.OverallStatus = "Degraded"
                    $summary.Issues += "Stopped App Services in ${rg}: $($stoppedApps.AppName -join ', ')"
                }
            }
        }
        catch { Write-Verbose "No App Services in $rg" }

        # VPN Gateway Health
        try {
            $vpn = Test-AzVpnGatewayHealth -ResourceGroupName $rg -ErrorAction SilentlyContinue
            if ($vpn) {
                $summary.VpnGateways += $vpn
                $unhealthy = $vpn | Where-Object Status -ne "Connected"
                if ($unhealthy) {
                    $summary.OverallStatus = "Critical"
                    $summary.Issues += "Unhealthy VPN connections in ${rg}: $($unhealthy.ConnectionName -join ', ')"
                }
            }
        }
        catch { Write-Verbose "No VPN gateways in $rg" }
    }

    # Certificate Check (subscription wide)
    try {
        $certs = Get-AzAppServiceCertStatus -WarningDaysThreshold 30 -ErrorAction SilentlyContinue
        if ($certs) {
            $summary.Certificates = $certs
            $expiring = $certs | Where-Object { $_.Status -in @("EXPIRED", "EXPIRING_SOON") }
            if ($expiring) {
                $summary.OverallStatus = if ($expiring | Where-Object Status -eq "EXPIRED") { "Critical" } else { "Degraded" }
                $summary.Issues += "Certificate issues: $($expiring | ForEach-Object { "$($_.SubjectName) ($($_.Status))" })"
            }
        }
    }
    catch { Write-Verbose "Certificate check skipped" }

    # Cost Check
    if ($IncludeCostCheck) {
        try {
            $cost = Invoke-AzCostAnomalyCheck -ErrorAction SilentlyContinue
            $summary.CostStatus = $cost
            if ($cost -and $cost.AnomaliesFound -gt 0) {
                $summary.Issues += "Cost anomalies detected: $($cost.AnomaliesFound) in last 7 days"
            }
        }
        catch { Write-Verbose "Cost check skipped" }
    }

    # Final Summary
    $statusColor = switch ($summary.OverallStatus) {
        "Healthy"  { "Green" }
        "Degraded" { "Yellow" }
        "Critical" { "Red" }
    }

    Write-Host "`n=====================================" -ForegroundColor $statusColor
    Write-Host "  OVERALL STATUS: $($summary.OverallStatus)" -ForegroundColor $statusColor
    Write-Host "=====================================" -ForegroundColor $statusColor

    if ($summary.Issues.Count -gt 0) {
        Write-Host "`n  Issues:" -ForegroundColor Yellow
        foreach ($issue in $summary.Issues) {
            Write-Host "    ! $issue" -ForegroundColor Yellow
        }
    }

    return $summary
}
