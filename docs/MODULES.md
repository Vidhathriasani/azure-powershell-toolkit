# Module Reference

## AzCostMonitor

| Function | Description |
|----------|-------------|
| `Invoke-AzCostAnomalyCheck` | Detects cost anomalies against rolling average baseline |
| `Get-AzDailyCostSummary` | Daily cost report grouped by resource group, service, or type |
| `Watch-AzResourceGroupSpend` | Monitors specific resource group against monthly budget |

## AzResourceGovernance

| Function | Description |
|----------|-------------|
| `Invoke-AzTagComplianceAudit` | Audits resources for required tag compliance |
| `Find-AzOrphanedResources` | Identifies unattached disks, unused IPs, empty resource groups |
| `Set-AzTagInheritance` | Inherits tags from resource group to child resources |

## AzAppServiceOps

| Function | Description |
|----------|-------------|
| `Get-AzAppServiceCertStatus` | Checks SSL certificate expiration dates |
| `Get-AzAppServiceHealth` | Returns App Service health and deployment slot status |
| `Get-AzAutoscaleActivity` | Reviews recent autoscale events |

## AzHybridConnectivity

| Function | Description |
|----------|-------------|
| `Test-AzVpnGatewayHealth` | Checks VPN gateway tunnel status |
| `Test-AzTrafficManagerFailover` | Validates Traffic Manager endpoint health and failover |
| `Test-AzHybridDnsResolution` | Tests DNS resolution for hybrid domains |

## Shared Functions

| Function | Description |
|----------|-------------|
| `Send-AlertNotification` | Unified alert dispatcher (Teams, Slack, Email) |
| `Get-AzHealthSummary` | Aggregated health dashboard across all services |

## Scripts

| Script | Description |
|--------|-------------|
| `Invoke-LogCleanup` | Automated log retention enforcement |
| `Invoke-ResourceAudit` | Full subscription resource audit |
| `Invoke-ServiceDeployment` | Distributed service deployment helper |
