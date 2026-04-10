# tag-compliance-report.ps1
# Example: Run a tag compliance audit and export results

Import-Module ./azure-toolkit.psd1
Connect-AzAccount

# Define your organization's required tags
$requiredTags = @("Environment", "Owner", "CostCenter", "Project")

# Run the audit and export non-compliant resources to CSV
$auditResult = Invoke-AzTagComplianceAudit `
    -RequiredTags $requiredTags `
    -ExportPath "./tag-compliance-$(Get-Date -Format 'yyyy-MM-dd').csv"

Write-Host "`nCompliance: $($auditResult.CompliancePercent)%"

# Fix compliance by inheriting tags from resource groups
# This applies missing tags from the RG level down to child resources
if ($auditResult.CompliancePercent -lt 100) {
    $resourceGroups = $auditResult.NonCompliantItems |
        Select-Object -ExpandProperty ResourceGroup -Unique

    foreach ($rg in $resourceGroups) {
        Write-Host "Applying tag inheritance for $rg..."
        Set-AzTagInheritance -ResourceGroupName $rg -Tags $requiredTags -WhatIf
        # Remove -WhatIf to actually apply the changes
    }
}

# Find orphaned resources that are wasting money
$orphaned = Find-AzOrphanedResources -IncludeTypes @("All")
Write-Host "Estimated monthly savings from cleanup: `$$($orphaned | Measure-Object -Property EstMonthlyCost -Sum | Select-Object -ExpandProperty Sum)"
