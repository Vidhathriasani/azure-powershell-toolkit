function Invoke-AzTagComplianceAudit {
    <#
    .SYNOPSIS
        Audits all resources in a subscription for required tag compliance.

    .DESCRIPTION
        Scans resources across all resource groups and reports which resources are missing
        required tags. Generates a compliance percentage and optionally exports results to CSV.

    .PARAMETER RequiredTags
        Array of tag names that every resource must have.

    .PARAMETER SubscriptionId
        Target subscription. Uses current context if omitted.

    .PARAMETER ExportPath
        If specified, exports the audit results to a CSV file.

    .PARAMETER ExcludeTypes
        Resource types to exclude from the audit (e.g., hidden or system managed resources).

    .EXAMPLE
        Invoke-AzTagComplianceAudit -RequiredTags @("Environment", "Owner", "CostCenter")

    .EXAMPLE
        Invoke-AzTagComplianceAudit -RequiredTags @("Owner") -ExportPath "./audit-results.csv"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$RequiredTags,

        [Parameter()]
        [string]$SubscriptionId,

        [Parameter()]
        [string]$ExportPath,

        [Parameter()]
        [string[]]$ExcludeTypes = @(
            "Microsoft.Insights/activityLogAlerts",
            "Microsoft.AlertsManagement/smartDetectorAlertRules"
        )
    )

    if (-not $SubscriptionId) {
        $SubscriptionId = (Get-AzContext).Subscription.Id
    }

    Write-Host "Running tag compliance audit..." -ForegroundColor Cyan
    Write-Host "Required tags: $($RequiredTags -join ', ')" -ForegroundColor Gray
    Write-Host "Subscription: $SubscriptionId" -ForegroundColor Gray

    try {
        Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop | Out-Null

        $resources = Get-AzResource | Where-Object {
            $_.ResourceType -notin $ExcludeTypes
        }

        $totalResources = $resources.Count
        $compliantCount = 0
        $nonCompliant = @()

        foreach ($resource in $resources) {
            $missingTags = @()

            foreach ($tag in $RequiredTags) {
                if (-not $resource.Tags -or -not $resource.Tags.ContainsKey($tag)) {
                    $missingTags += $tag
                }
            }

            if ($missingTags.Count -eq 0) {
                $compliantCount++
            }
            else {
                $nonCompliant += [PSCustomObject]@{
                    ResourceName  = $resource.Name
                    ResourceType  = $resource.ResourceType
                    ResourceGroup = $resource.ResourceGroupName
                    MissingTags   = ($missingTags -join ', ')
                    Location      = $resource.Location
                }
            }
        }

        $compliancePercent = if ($totalResources -gt 0) {
            [math]::Round(($compliantCount / $totalResources) * 100, 1)
        } else { 100 }

        $complianceColor = if ($compliancePercent -ge 90) { "Green" }
            elseif ($compliancePercent -ge 70) { "Yellow" }
            else { "Red" }

        Write-Host "`nTag Compliance Report" -ForegroundColor White
        Write-Host ("=" * 50) -ForegroundColor Gray
        Write-Host "  Total Resources:     $totalResources" -ForegroundColor White
        Write-Host "  Compliant:           $compliantCount" -ForegroundColor Green
        Write-Host "  Non-Compliant:       $($nonCompliant.Count)" -ForegroundColor Red
        Write-Host "  Compliance Rate:     ${compliancePercent}%" -ForegroundColor $complianceColor

        if ($nonCompliant.Count -gt 0) {
            Write-Host "`nTop non-compliant resources:" -ForegroundColor Yellow
            $nonCompliant | Select-Object -First 10 | ForEach-Object {
                Write-Host "  $($_.ResourceName) ($($_.ResourceType)) | Missing: $($_.MissingTags)" -ForegroundColor Red
            }
        }

        if ($ExportPath) {
            $nonCompliant | Export-Csv -Path $ExportPath -NoTypeInformation
            Write-Host "`nFull report exported to: $ExportPath" -ForegroundColor Green
        }

        return [PSCustomObject]@{
            SubscriptionId   = $SubscriptionId
            TotalResources   = $totalResources
            CompliantCount   = $compliantCount
            NonCompliantCount = $nonCompliant.Count
            CompliancePercent = $compliancePercent
            NonCompliantItems = $nonCompliant
        }
    }
    catch {
        Write-Error "Tag compliance audit failed: $_"
    }
}

function Find-AzOrphanedResources {
    <#
    .SYNOPSIS
        Identifies orphaned Azure resources that may be incurring unnecessary costs.

    .DESCRIPTION
        Scans for unattached managed disks, unused public IP addresses, empty resource groups,
        and disconnected network interfaces. These are common sources of waste in Azure.

    .PARAMETER SubscriptionId
        Target subscription. Uses current context if omitted.

    .PARAMETER IncludeTypes
        Types of orphaned resources to check. Valid values: Disk, PublicIP, NIC, EmptyRG, All.

    .EXAMPLE
        Find-AzOrphanedResources -IncludeTypes @("Disk", "PublicIP")

    .EXAMPLE
        Find-AzOrphanedResources -IncludeTypes @("All")
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$SubscriptionId,

        [Parameter()]
        [ValidateSet("Disk", "PublicIP", "NIC", "EmptyRG", "All")]
        [string[]]$IncludeTypes = @("All")
    )

    if (-not $SubscriptionId) {
        $SubscriptionId = (Get-AzContext).Subscription.Id
    }

    $checkAll = $IncludeTypes -contains "All"
    $orphaned = @()
    $estimatedMonthlySavings = 0

    Write-Host "Scanning for orphaned resources in subscription $SubscriptionId..." -ForegroundColor Cyan

    # Unattached Managed Disks
    if ($checkAll -or $IncludeTypes -contains "Disk") {
        Write-Host "  Checking unattached managed disks..." -ForegroundColor Gray
        try {
            $disks = Get-AzDisk | Where-Object { $_.DiskState -eq 'Unattached' }
            foreach ($disk in $disks) {
                $monthlyCost = switch ($disk.Sku.Name) {
                    "Premium_LRS"    { [math]::Round($disk.DiskSizeGB * 0.135, 2) }
                    "StandardSSD_LRS" { [math]::Round($disk.DiskSizeGB * 0.075, 2) }
                    default          { [math]::Round($disk.DiskSizeGB * 0.04, 2) }
                }
                $estimatedMonthlySavings += $monthlyCost

                $orphaned += [PSCustomObject]@{
                    Type           = "Unattached Disk"
                    Name           = $disk.Name
                    ResourceGroup  = $disk.ResourceGroupName
                    Location       = $disk.Location
                    SizeGB         = $disk.DiskSizeGB
                    Sku            = $disk.Sku.Name
                    EstMonthlyCost = $monthlyCost
                    CreatedDate    = $disk.TimeCreated
                }
            }
            Write-Host "    Found $($disks.Count) unattached disks" -ForegroundColor $(if ($disks.Count -gt 0) { "Yellow" } else { "Green" })
        }
        catch { Write-Warning "Failed to check disks: $_" }
    }

    # Unused Public IPs
    if ($checkAll -or $IncludeTypes -contains "PublicIP") {
        Write-Host "  Checking unused public IP addresses..." -ForegroundColor Gray
        try {
            $publicIPs = Get-AzPublicIpAddress | Where-Object { -not $_.IpConfiguration }
            foreach ($pip in $publicIPs) {
                $monthlyCost = if ($pip.Sku.Name -eq "Standard") { 3.65 } else { 0 }
                $estimatedMonthlySavings += $monthlyCost

                $orphaned += [PSCustomObject]@{
                    Type           = "Unused Public IP"
                    Name           = $pip.Name
                    ResourceGroup  = $pip.ResourceGroupName
                    Location       = $pip.Location
                    IpAddress      = $pip.IpAddress
                    Sku            = $pip.Sku.Name
                    EstMonthlyCost = $monthlyCost
                    CreatedDate    = ""
                }
            }
            Write-Host "    Found $($publicIPs.Count) unused public IPs" -ForegroundColor $(if ($publicIPs.Count -gt 0) { "Yellow" } else { "Green" })
        }
        catch { Write-Warning "Failed to check public IPs: $_" }
    }

    # Disconnected NICs
    if ($checkAll -or $IncludeTypes -contains "NIC") {
        Write-Host "  Checking disconnected network interfaces..." -ForegroundColor Gray
        try {
            $nics = Get-AzNetworkInterface | Where-Object { -not $_.VirtualMachine }
            foreach ($nic in $nics) {
                $orphaned += [PSCustomObject]@{
                    Type           = "Disconnected NIC"
                    Name           = $nic.Name
                    ResourceGroup  = $nic.ResourceGroupName
                    Location       = $nic.Location
                    PrivateIP      = $nic.IpConfigurations[0].PrivateIpAddress
                    Sku            = ""
                    EstMonthlyCost = 0
                    CreatedDate    = ""
                }
            }
            Write-Host "    Found $($nics.Count) disconnected NICs" -ForegroundColor $(if ($nics.Count -gt 0) { "Yellow" } else { "Green" })
        }
        catch { Write-Warning "Failed to check NICs: $_" }
    }

    # Empty Resource Groups
    if ($checkAll -or $IncludeTypes -contains "EmptyRG") {
        Write-Host "  Checking empty resource groups..." -ForegroundColor Gray
        try {
            $resourceGroups = Get-AzResourceGroup
            $emptyRGs = @()
            foreach ($rg in $resourceGroups) {
                $resources = Get-AzResource -ResourceGroupName $rg.ResourceGroupName
                if ($resources.Count -eq 0) {
                    $emptyRGs += $rg
                    $orphaned += [PSCustomObject]@{
                        Type           = "Empty Resource Group"
                        Name           = $rg.ResourceGroupName
                        ResourceGroup  = $rg.ResourceGroupName
                        Location       = $rg.Location
                        Sku            = ""
                        EstMonthlyCost = 0
                        CreatedDate    = ""
                    }
                }
            }
            Write-Host "    Found $($emptyRGs.Count) empty resource groups" -ForegroundColor $(if ($emptyRGs.Count -gt 0) { "Yellow" } else { "Green" })
        }
        catch { Write-Warning "Failed to check resource groups: $_" }
    }

    Write-Host "`nOrphaned Resource Summary" -ForegroundColor White
    Write-Host ("=" * 50) -ForegroundColor Gray
    Write-Host "  Total orphaned resources: $($orphaned.Count)" -ForegroundColor $(if ($orphaned.Count -gt 0) { "Yellow" } else { "Green" })
    Write-Host "  Estimated monthly savings: `$$([math]::Round($estimatedMonthlySavings, 2))" -ForegroundColor Yellow

    return $orphaned
}

function Set-AzTagInheritance {
    <#
    .SYNOPSIS
        Inherits specified tags from a resource group to all child resources missing those tags.

    .PARAMETER ResourceGroupName
        The resource group whose tags should be inherited by child resources.

    .PARAMETER Tags
        Array of tag names to inherit. Only applies to resources missing these tags.

    .PARAMETER WhatIf
        Preview changes without applying them.

    .EXAMPLE
        Set-AzTagInheritance -ResourceGroupName "rg-production" -Tags @("Environment", "Owner")
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$ResourceGroupName,

        [Parameter(Mandatory)]
        [string[]]$Tags
    )

    try {
        $rg = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction Stop
        $rgTags = $rg.Tags

        if (-not $rgTags) {
            Write-Warning "Resource group '$ResourceGroupName' has no tags to inherit."
            return
        }

        $resources = Get-AzResource -ResourceGroupName $ResourceGroupName
        $updatedCount = 0

        Write-Host "Applying tag inheritance from '$ResourceGroupName' to $($resources.Count) resources..." -ForegroundColor Cyan

        foreach ($resource in $resources) {
            $tagsToApply = @{}
            $currentTags = if ($resource.Tags) { $resource.Tags } else { @{} }

            foreach ($tagName in $Tags) {
                if ($rgTags.ContainsKey($tagName) -and -not $currentTags.ContainsKey($tagName)) {
                    $tagsToApply[$tagName] = $rgTags[$tagName]
                }
            }

            if ($tagsToApply.Count -gt 0) {
                if ($PSCmdlet.ShouldProcess($resource.Name, "Apply tags: $($tagsToApply.Keys -join ', ')")) {
                    $mergedTags = $currentTags + $tagsToApply
                    Set-AzResource -ResourceId $resource.ResourceId -Tag $mergedTags -Force | Out-Null
                    $updatedCount++
                    Write-Host "  Updated: $($resource.Name) | Applied: $($tagsToApply.Keys -join ', ')" -ForegroundColor Green
                }
            }
        }

        Write-Host "`nTag inheritance complete. Updated $updatedCount of $($resources.Count) resources." -ForegroundColor White
    }
    catch {
        Write-Error "Tag inheritance failed: $_"
    }
}
