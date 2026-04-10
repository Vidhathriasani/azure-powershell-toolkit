# Azure PowerShell Automation Toolkit

A production-grade collection of PowerShell modules and scripts for automating Azure infrastructure operations, cost monitoring, resource governance, and hybrid environment management.

Built for DevOps and Cloud Engineers managing enterprise Azure environments at scale.

![PowerShell](https://img.shields.io/badge/PowerShell-7.4+-blue?logo=powershell)
![Azure](https://img.shields.io/badge/Azure-Az%20Module-0078D4?logo=microsoftazure)
![License](https://img.shields.io/badge/License-MIT-green)
![Tests](https://img.shields.io/badge/Tests-Pester%205.x-orange)
![CI](https://img.shields.io/badge/CI-GitHub%20Actions-2088FF?logo=githubactions)

## Overview

Managing Azure infrastructure across multiple subscriptions, hybrid environments, and distributed teams requires reliable, repeatable automation. This toolkit provides battle-tested PowerShell modules for the operations that consume the most engineering time:

- **Cost Management** — Automated cost anomaly detection and budget alerting
- **Resource Governance** — Tag compliance enforcement and orphaned resource cleanup
- **App Service Operations** — Health checks, certificate monitoring, and autoscale management
- **Hybrid Connectivity** — VPN gateway monitoring and Traffic Manager failover validation
- **Log Management** — Automated log cleanup and retention policy enforcement
- **Deployment Utilities** — Service deployment helpers for distributed on-prem and cloud targets

## Project Structure

```
azure-powershell-toolkit/
├── src/
│   ├── modules/
│   │   ├── AzCostMonitor/          # Cost anomaly detection and budget alerts
│   │   ├── AzResourceGovernance/   # Tag compliance and orphaned resource cleanup
│   │   ├── AzAppServiceOps/        # App Service health, certs, and scaling
│   │   └── AzHybridConnectivity/   # VPN and Traffic Manager monitoring
│   ├── scripts/
│   │   ├── Invoke-LogCleanup.ps1           # Automated log retention enforcement
│   │   ├── Invoke-ResourceAudit.ps1        # Full subscription resource audit
│   │   └── Invoke-ServiceDeployment.ps1    # Distributed service deployment helper
│   └── functions/
│       ├── Send-AlertNotification.ps1      # Teams/Slack/Email alert dispatcher
│       └── Get-AzHealthSummary.ps1         # Aggregated health dashboard data
├── tests/
│   ├── AzCostMonitor.Tests.ps1
│   ├── AzResourceGovernance.Tests.ps1
│   ├── AzAppServiceOps.Tests.ps1
│   └── AzHybridConnectivity.Tests.ps1
├── docs/
│   ├── SETUP.md
│   ├── MODULES.md
│   └── CONTRIBUTING.md
├── examples/
│   ├── cost-alert-setup.ps1
│   ├── tag-compliance-report.ps1
│   └── hybrid-health-check.ps1
├── config/
│   └── toolkit-config.example.json
├── .github/
│   └── workflows/
│       └── ci.yml
├── azure-toolkit.psd1                     # Module manifest
├── azure-toolkit.psm1                     # Root module loader
├── LICENSE
└── README.md
```

## Quick Start

### Prerequisites

- PowerShell 7.4 or later
- Az PowerShell module (`Install-Module Az`)
- Authenticated Azure session (`Connect-AzAccount`)

### Installation

```powershell
# Clone the repository
git clone https://github.com/vidhathriasani/azure-powershell-toolkit.git
cd azure-powershell-toolkit

# Import the toolkit
Import-Module ./azure-toolkit.psd1

# Verify installation
Get-Command -Module azure-toolkit
```

### Configuration

Copy the example config and update with your environment details:

```powershell
Copy-Item ./config/toolkit-config.example.json ./config/toolkit-config.json
# Edit toolkit-config.json with your subscription IDs, thresholds, and notification settings
```

## Module Reference

### AzCostMonitor

Detects cost anomalies by comparing current spend against rolling averages and configured thresholds. Sends alerts when spend exceeds baseline by a configurable percentage.

```powershell
# Check for cost anomalies across all subscriptions
Invoke-AzCostAnomalyCheck -ThresholdPercent 25 -LookbackDays 30

# Generate a daily cost summary report
Get-AzDailyCostSummary -SubscriptionId "xxxx-xxxx" -GroupBy "ResourceGroup"

# Monitor specific resource groups for budget overruns
Watch-AzResourceGroupSpend -ResourceGroupName "rg-production" -MonthlyBudget 5000
```

### AzResourceGovernance

Enforces tagging policies, identifies orphaned resources (unattached disks, unused public IPs, empty resource groups), and generates compliance reports.

```powershell
# Run a tag compliance audit
Invoke-AzTagComplianceAudit -RequiredTags @("Environment", "Owner", "CostCenter")

# Find and report orphaned resources
Find-AzOrphanedResources -SubscriptionId "xxxx-xxxx" -IncludeTypes @("Disk", "PublicIP", "NIC")

# Auto-tag resources based on resource group tags (tag inheritance)
Set-AzTagInheritance -ResourceGroupName "rg-production" -Tags @("Environment", "Owner")
```

### AzAppServiceOps

Monitors App Service health, SSL certificate expiration, autoscale activity, and deployment slot status.

```powershell
# Check SSL certificate expiration across all App Services
Get-AzAppServiceCertStatus -WarningDaysThreshold 30

# Get App Service health summary with response times
Get-AzAppServiceHealth -ResourceGroupName "rg-web-apps" -IncludeSlots

# Review autoscale events for unexpected scaling
Get-AzAutoscaleActivity -AppServicePlanName "asp-production" -Hours 24
```

### AzHybridConnectivity

Monitors VPN gateway tunnel status, Traffic Manager endpoint health, and hybrid DNS resolution.

```powershell
# Check all VPN gateway tunnel connections
Test-AzVpnGatewayHealth -ResourceGroupName "rg-networking"

# Validate Traffic Manager failover readiness
Test-AzTrafficManagerFailover -ProfileName "tm-production" -SimulateFailover

# Monitor hybrid DNS resolution across environments
Test-AzHybridDnsResolution -Domains @("app.internal.corp", "api.internal.corp")
```

## Alerting

The toolkit includes a unified alert dispatcher that supports Microsoft Teams, Slack, and email notifications. Configure your preferred channels in `toolkit-config.json`:

```json
{
  "alerting": {
    "teams_webhook_url": "https://outlook.office.com/webhook/...",
    "slack_webhook_url": "https://hooks.slack.com/services/...",
    "smtp_server": "smtp.office365.com",
    "smtp_from": "alerts@yourdomain.com",
    "smtp_to": ["oncall@yourdomain.com"]
  }
}
```

```powershell
# Send a test alert to all configured channels
Send-AlertNotification -Title "Test Alert" -Message "Toolkit alerting is working" -Severity "Info"
```

## Running Tests

Tests are written with Pester 5.x and can be run locally or in CI:

```powershell
# Install Pester if needed
Install-Module Pester -MinimumVersion 5.0 -Force

# Run all tests
Invoke-Pester ./tests/ -Output Detailed

# Run tests for a specific module
Invoke-Pester ./tests/AzCostMonitor.Tests.ps1 -Output Detailed
```

## CI/CD

The included GitHub Actions workflow runs on every push and pull request:

- PSScriptAnalyzer linting
- Pester test execution
- Module manifest validation
- Code coverage reporting

## Use Cases

| Scenario | Module/Script | What It Does |
|----------|---------------|--------------|
| Monthly Azure bill spiked unexpectedly | AzCostMonitor | Detects anomalies against rolling baseline |
| Untagged resources causing billing confusion | AzResourceGovernance | Audits and enforces tag compliance |
| SSL cert expired on production App Service | AzAppServiceOps | Monitors cert expiration with alerting |
| VPN tunnel dropped between Azure and on-prem | AzHybridConnectivity | Monitors tunnel status with auto-alerting |
| Log storage consuming excessive disk/storage | Invoke-LogCleanup | Enforces retention policies and purges old logs |
| Need a full audit before compliance review | Invoke-ResourceAudit | Generates comprehensive subscription audit report |

## Contributing

See [CONTRIBUTING.md](docs/CONTRIBUTING.md) for guidelines on submitting issues and pull requests.

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.
