# Setup Guide

## Prerequisites

1. **PowerShell 7.4+**: Download from [GitHub](https://github.com/PowerShell/PowerShell/releases)
2. **Az PowerShell Module**: Install with `Install-Module Az -Scope CurrentUser`
3. **Pester 5.x** (for running tests): Install with `Install-Module Pester -MinimumVersion 5.0`

## Installation

```powershell
git clone https://github.com/yourusername/azure-powershell-toolkit.git
cd azure-powershell-toolkit
Import-Module ./azure-toolkit.psd1
```

## Authentication

The toolkit uses your existing Azure session. Authenticate before running any commands:

```powershell
Connect-AzAccount
Set-AzContext -SubscriptionId "your-subscription-id"
```

For service principal authentication (CI/CD):

```powershell
$credential = New-Object System.Management.Automation.PSCredential($appId, $securePassword)
Connect-AzAccount -ServicePrincipal -Credential $credential -TenantId $tenantId
```

## Configuration

1. Copy the example config: `Copy-Item ./config/toolkit-config.example.json ./config/toolkit-config.json`
2. Update with your subscription IDs, webhook URLs, and SMTP settings
3. The config file is gitignored by default to prevent leaking secrets

## Verify Installation

```powershell
Get-Command -Module azure-toolkit
```

This should list all exported functions from the toolkit.
