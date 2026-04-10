# cost-alert-setup.ps1
# Example: Set up automated cost anomaly detection with Teams alerting

# Import the toolkit
Import-Module ./azure-toolkit.psd1

# Authenticate
Connect-AzAccount
Set-AzContext -SubscriptionId "your-subscription-id"

# Run a one-time cost anomaly check with alerting enabled
# This compares the last 7 days of spend against a 30-day rolling average
# and sends a Teams notification if any day exceeds the baseline by 25%
Invoke-AzCostAnomalyCheck -ThresholdPercent 25 -LookbackDays 30 -SendAlert

# Get a cost breakdown by resource group for the last 14 days
Get-AzDailyCostSummary -Days 14 -GroupBy "ResourceGroup"

# Monitor a specific resource group against a monthly budget
Watch-AzResourceGroupSpend -ResourceGroupName "rg-production" -MonthlyBudget 5000 -WarningPercent 80

# To run this on a schedule, create an Azure Automation Runbook
# or a scheduled task that calls this script daily
