# hybrid-health-check.ps1
# Example: Run a full health check across hybrid Azure and on-prem infrastructure

Import-Module ./azure-toolkit.psd1
Connect-AzAccount

# Run the aggregated health dashboard across key resource groups
$healthSummary = Get-AzHealthSummary `
    -ResourceGroupNames @("rg-web-prod", "rg-networking", "rg-data-prod") `
    -IncludeCostCheck

# Check VPN gateway tunnels to on-prem
Write-Host "`n--- VPN Gateway Health ---"
Test-AzVpnGatewayHealth -ResourceGroupName "rg-networking" -SendAlert

# Validate Traffic Manager failover readiness
Write-Host "`n--- Traffic Manager Failover Test ---"
Test-AzTrafficManagerFailover `
    -ProfileName "tm-production" `
    -ResourceGroupName "rg-networking" `
    -SimulateFailover

# Test hybrid DNS resolution
Write-Host "`n--- Hybrid DNS Resolution ---"
Test-AzHybridDnsResolution `
    -Domains @("app.internal.corp", "api.internal.corp", "db.internal.corp") `
    -DnsServers @("10.0.0.4", "10.0.0.5")

# Check SSL certificates
Write-Host "`n--- SSL Certificate Status ---"
Get-AzAppServiceCertStatus -WarningDaysThreshold 30 -SendAlert

# If overall status is not healthy, send a summary alert
if ($healthSummary.OverallStatus -ne "Healthy") {
    $issueList = $healthSummary.Issues -join "`n"
    Send-AlertNotification `
        -Title "Infrastructure Health Alert: $($healthSummary.OverallStatus)" `
        -Message "Issues detected:`n$issueList" `
        -Severity $(if ($healthSummary.OverallStatus -eq "Critical") { "Critical" } else { "Warning" })
}
