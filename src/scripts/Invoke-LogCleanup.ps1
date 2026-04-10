function Invoke-LogCleanup {
    <#
    .SYNOPSIS
        Enforces log retention policies across Azure Storage Accounts and App Service logs.

    .PARAMETER SubscriptionId
        Target subscription.

    .PARAMETER RetentionDays
        Maximum age of logs to retain. Logs older than this are deleted. Default: 90.

    .PARAMETER StorageAccountName
        Specific storage account to clean. If omitted, scans all storage accounts with log containers.

    .PARAMETER WhatIf
        Preview which blobs would be deleted without actually deleting them.

    .EXAMPLE
        Invoke-LogCleanup -RetentionDays 60 -WhatIf

    .EXAMPLE
        Invoke-LogCleanup -StorageAccountName "stprodlogs" -RetentionDays 30
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter()]
        [string]$SubscriptionId,

        [Parameter()]
        [int]$RetentionDays = 90,

        [Parameter()]
        [string]$StorageAccountName,

        [Parameter()]
        [string[]]$ContainerPrefixes = @("insights-logs-", "insights-metrics-", "logs", "app-logs")
    )

    if (-not $SubscriptionId) {
        $SubscriptionId = (Get-AzContext).Subscription.Id
    }

    $cutoffDate = (Get-Date).AddDays(-$RetentionDays)
    $totalBlobsFound = 0
    $totalBlobsDeleted = 0
    $totalSizeReclaimed = 0

    Write-Host "Log Cleanup | Retention: $RetentionDays days | Cutoff: $($cutoffDate.ToString('yyyy-MM-dd'))" -ForegroundColor Cyan

    try {
        $storageAccounts = if ($StorageAccountName) {
            Get-AzStorageAccount | Where-Object { $_.StorageAccountName -eq $StorageAccountName }
        } else {
            Get-AzStorageAccount
        }

        foreach ($sa in $storageAccounts) {
            $context = $sa.Context
            $containers = Get-AzStorageContainer -Context $context -ErrorAction SilentlyContinue |
                Where-Object {
                    $name = $_.Name
                    $ContainerPrefixes | Where-Object { $name -like "$_*" }
                }

            if ($containers.Count -eq 0) { continue }

            Write-Host "`n  Storage Account: $($sa.StorageAccountName)" -ForegroundColor White

            foreach ($container in $containers) {
                Write-Host "    Container: $($container.Name)" -ForegroundColor Gray

                $blobs = Get-AzStorageBlob -Container $container.Name -Context $context |
                    Where-Object { $_.LastModified -lt $cutoffDate }

                $totalBlobsFound += $blobs.Count

                foreach ($blob in $blobs) {
                    $blobSizeMB = [math]::Round($blob.Length / 1MB, 2)

                    if ($PSCmdlet.ShouldProcess($blob.Name, "Delete blob ($blobSizeMB MB, modified $($blob.LastModified.ToString('yyyy-MM-dd')))")) {
                        Remove-AzStorageBlob -Blob $blob.Name -Container $container.Name -Context $context -Force
                        $totalBlobsDeleted++
                        $totalSizeReclaimed += $blob.Length
                    }
                }

                if ($blobs.Count -gt 0) {
                    Write-Host "      Found $($blobs.Count) blobs older than $RetentionDays days" -ForegroundColor Yellow
                }
            }
        }

        $sizeReclaimedMB = [math]::Round($totalSizeReclaimed / 1MB, 2)
        $sizeReclaimedGB = [math]::Round($totalSizeReclaimed / 1GB, 2)

        Write-Host "`nLog Cleanup Summary" -ForegroundColor White
        Write-Host ("=" * 40) -ForegroundColor Gray
        Write-Host "  Blobs found past retention:  $totalBlobsFound" -ForegroundColor White
        Write-Host "  Blobs deleted:               $totalBlobsDeleted" -ForegroundColor Green
        Write-Host "  Storage reclaimed:            ${sizeReclaimedMB} MB (${sizeReclaimedGB} GB)" -ForegroundColor Green

        return [PSCustomObject]@{
            RetentionDays    = $RetentionDays
            CutoffDate       = $cutoffDate
            BlobsFound       = $totalBlobsFound
            BlobsDeleted     = $totalBlobsDeleted
            SizeReclaimedMB  = $sizeReclaimedMB
        }
    }
    catch {
        Write-Error "Log cleanup failed: $_"
    }
}
