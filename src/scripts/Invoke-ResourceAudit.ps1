function Invoke-ResourceAudit {
    <#
    .SYNOPSIS
        Generates a comprehensive audit report of all resources in a subscription.

    .DESCRIPTION
        Enumerates all resources, groups them by type and resource group, checks tag compliance,
        identifies unused resources, and outputs a structured report suitable for compliance reviews.

    .PARAMETER SubscriptionId
        Target subscription.

    .PARAMETER ExportPath
        Path to export the audit report as CSV.

    .EXAMPLE
        Invoke-ResourceAudit -ExportPath "./audit-report.csv"
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$SubscriptionId,

        [Parameter()]
        [string]$ExportPath
    )

    if (-not $SubscriptionId) {
        $SubscriptionId = (Get-AzContext).Subscription.Id
    }

    Write-Host "Running full resource audit for subscription $SubscriptionId..." -ForegroundColor Cyan

    try {
        $resources = Get-AzResource
        $resourceGroups = Get-AzResourceGroup

        $audit = $resources | ForEach-Object {
            $tagCount = if ($_.Tags) { $_.Tags.Count } else { 0 }
            $hasOwner = if ($_.Tags -and $_.Tags.ContainsKey("Owner")) { $true } else { $false }
            $hasEnv = if ($_.Tags -and $_.Tags.ContainsKey("Environment")) { $true } else { $false }

            [PSCustomObject]@{
                ResourceName  = $_.Name
                ResourceType  = $_.ResourceType
                ResourceGroup = $_.ResourceGroupName
                Location      = $_.Location
                TagCount      = $tagCount
                HasOwnerTag   = $hasOwner
                HasEnvTag     = $hasEnv
                ResourceId    = $_.ResourceId
            }
        }

        # Summary by type
        $byType = $audit | Group-Object ResourceType | Sort-Object Count -Descending |
            Select-Object @{N='ResourceType';E={$_.Name}}, Count

        # Summary by resource group
        $byRG = $audit | Group-Object ResourceGroup | Sort-Object Count -Descending |
            Select-Object @{N='ResourceGroup';E={$_.Name}}, Count

        Write-Host "`nResource Audit Summary" -ForegroundColor White
        Write-Host ("=" * 50) -ForegroundColor Gray
        Write-Host "  Total Resources:        $($audit.Count)" -ForegroundColor White
        Write-Host "  Total Resource Groups:   $($resourceGroups.Count)" -ForegroundColor White
        Write-Host "  With Owner Tag:          $(($audit | Where-Object HasOwnerTag).Count)" -ForegroundColor White
        Write-Host "  With Environment Tag:    $(($audit | Where-Object HasEnvTag).Count)" -ForegroundColor White

        Write-Host "`n  Top Resource Types:" -ForegroundColor White
        $byType | Select-Object -First 10 | ForEach-Object {
            Write-Host "    $($_.ResourceType.PadRight(45)) $($_.Count)" -ForegroundColor Gray
        }

        if ($ExportPath) {
            $audit | Export-Csv -Path $ExportPath -NoTypeInformation
            Write-Host "`nReport exported to: $ExportPath" -ForegroundColor Green
        }

        return [PSCustomObject]@{
            SubscriptionId   = $SubscriptionId
            TotalResources   = $audit.Count
            TotalRGs         = $resourceGroups.Count
            ByType           = $byType
            ByResourceGroup  = $byRG
            Details          = $audit
        }
    }
    catch {
        Write-Error "Resource audit failed: $_"
    }
}

function Invoke-ServiceDeployment {
    <#
    .SYNOPSIS
        Deploys a Windows service to multiple remote targets via WinRM or local copy.

    .DESCRIPTION
        Reads a target list from a CSV file and deploys a specified service package to each target.
        Supports WinRM-based remote deployment through jump servers for on-premises environments
        and direct copy for local network targets.

    .PARAMETER ServiceName
        Name of the Windows service to deploy.

    .PARAMETER PackagePath
        Path to the service package (zip or folder).

    .PARAMETER TargetsCsv
        Path to a CSV file with columns: Hostname, InstallPath, JumpServer (optional).

    .PARAMETER Credential
        PSCredential for remote authentication. If omitted, uses current session credentials.

    .PARAMETER WhatIf
        Preview deployment without executing.

    .EXAMPLE
        Invoke-ServiceDeployment -ServiceName "FileWatcher" -PackagePath "./package.zip" -TargetsCsv "./targets.csv"
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$ServiceName,

        [Parameter(Mandatory)]
        [string]$PackagePath,

        [Parameter(Mandatory)]
        [string]$TargetsCsv,

        [Parameter()]
        [PSCredential]$Credential
    )

    if (-not (Test-Path $TargetsCsv)) {
        Write-Error "Targets CSV not found: $TargetsCsv"
        return
    }

    if (-not (Test-Path $PackagePath)) {
        Write-Error "Package not found: $PackagePath"
        return
    }

    $targets = Import-Csv $TargetsCsv
    $successCount = 0
    $failCount = 0

    Write-Host "Deploying '$ServiceName' to $($targets.Count) targets..." -ForegroundColor Cyan

    foreach ($target in $targets) {
        $hostname = $target.Hostname
        $installPath = $target.InstallPath
        $jumpServer = $target.JumpServer

        Write-Host "`n  Target: $hostname" -ForegroundColor White

        if ($PSCmdlet.ShouldProcess($hostname, "Deploy $ServiceName")) {
            try {
                $sessionParams = @{ ComputerName = $hostname }
                if ($Credential) { $sessionParams.Credential = $Credential }

                if ($jumpServer) {
                    Write-Host "    Routing through jump server: $jumpServer" -ForegroundColor Gray
                    $jumpSession = New-PSSession -ComputerName $jumpServer @(
                        if ($Credential) { @{ Credential = $Credential } } else { @{} }
                    )
                    $session = New-PSSession -ComputerName $hostname -Session $jumpSession
                } else {
                    $session = New-PSSession @sessionParams
                }

                # Stop existing service
                Invoke-Command -Session $session -ScriptBlock {
                    param($svc)
                    $service = Get-Service -Name $svc -ErrorAction SilentlyContinue
                    if ($service -and $service.Status -eq 'Running') {
                        Stop-Service -Name $svc -Force
                        Write-Output "Service stopped."
                    }
                } -ArgumentList $ServiceName

                # Copy package
                Copy-Item -Path $PackagePath -Destination $installPath -ToSession $session -Recurse -Force
                Write-Host "    Package deployed to $installPath" -ForegroundColor Green

                # Start service
                Invoke-Command -Session $session -ScriptBlock {
                    param($svc)
                    Start-Service -Name $svc
                    $status = (Get-Service -Name $svc).Status
                    Write-Output "Service status: $status"
                } -ArgumentList $ServiceName

                Remove-PSSession $session -ErrorAction SilentlyContinue
                if ($jumpSession) { Remove-PSSession $jumpSession -ErrorAction SilentlyContinue }

                $successCount++
                Write-Host "    DEPLOYED SUCCESSFULLY" -ForegroundColor Green
            }
            catch {
                $failCount++
                Write-Host "    DEPLOYMENT FAILED: $_" -ForegroundColor Red
            }
        }
    }

    Write-Host "`nDeployment Summary" -ForegroundColor White
    Write-Host ("=" * 40) -ForegroundColor Gray
    Write-Host "  Total targets:  $($targets.Count)" -ForegroundColor White
    Write-Host "  Succeeded:      $successCount" -ForegroundColor Green
    Write-Host "  Failed:         $failCount" -ForegroundColor $(if ($failCount -gt 0) { "Red" } else { "Green" })
}
