@{
    RootModule        = 'azure-toolkit.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'a3f2b8c1-4d5e-6f7a-8b9c-0d1e2f3a4b5c'
    Author            = 'Vidhathri Asani'
    CompanyName       = 'Community'
    Copyright         = '(c) 2026 Vidhathri Asani. All rights reserved.'
    Description       = 'Production-grade PowerShell toolkit for Azure infrastructure automation, cost monitoring, resource governance, and hybrid connectivity management.'
    PowerShellVersion = '7.4'
    RequiredModules   = @(
        @{ ModuleName = 'Az.Accounts'; ModuleVersion = '2.0.0' },
        @{ ModuleName = 'Az.Resources'; ModuleVersion = '6.0.0' },
        @{ ModuleName = 'Az.Monitor'; ModuleVersion = '4.0.0' },
        @{ ModuleName = 'Az.Network'; ModuleVersion = '6.0.0' },
        @{ ModuleName = 'Az.Websites'; ModuleVersion = '3.0.0' },
        @{ ModuleName = 'Az.CostManagement'; ModuleVersion = '0.3.0' }
    )
    FunctionsToExport = @(
        'Invoke-AzCostAnomalyCheck',
        'Get-AzDailyCostSummary',
        'Watch-AzResourceGroupSpend',
        'Invoke-AzTagComplianceAudit',
        'Find-AzOrphanedResources',
        'Set-AzTagInheritance',
        'Get-AzAppServiceCertStatus',
        'Get-AzAppServiceHealth',
        'Get-AzAutoscaleActivity',
        'Test-AzVpnGatewayHealth',
        'Test-AzTrafficManagerFailover',
        'Test-AzHybridDnsResolution',
        'Send-AlertNotification',
        'Get-AzHealthSummary',
        'Invoke-LogCleanup',
        'Invoke-ResourceAudit',
        'Invoke-ServiceDeployment'
    )
    CmdletsToExport   = @()
    VariablesToExport  = @()
    AliasesToExport    = @()
    PrivateData       = @{
        PSData = @{
            Tags         = @('Azure', 'DevOps', 'Automation', 'Infrastructure', 'CloudOps', 'FinOps', 'Governance')
            LicenseUri   = 'https://github.com/vidhathriasani/azure-powershell-toolkit/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/vidhathriasani/azure-powershell-toolkit'
            ReleaseNotes = 'Initial release with cost monitoring, resource governance, App Service ops, and hybrid connectivity modules.'
        }
    }
}
