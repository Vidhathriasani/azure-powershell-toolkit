function Get-AzAppServiceCertStatus {
    <#
    .SYNOPSIS
        Checks SSL certificate expiration dates across all App Services in a subscription.

    .PARAMETER SubscriptionId
        Target subscription. Uses current context if omitted.

    .PARAMETER WarningDaysThreshold
        Number of days before expiration to flag as a warning. Default: 30.

    .PARAMETER SendAlert
        If specified, sends alerts for expiring certificates.

    .EXAMPLE
        Get-AzAppServiceCertStatus -WarningDaysThreshold 60
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$SubscriptionId,

        [Parameter()]
        [int]$WarningDaysThreshold = 30,

        [Parameter()]
        [switch]$SendAlert
    )

    if (-not $SubscriptionId) {
        $SubscriptionId = (Get-AzContext).Subscription.Id
    }

    Write-Host "Scanning App Service SSL certificates..." -ForegroundColor Cyan
    Write-Host "Warning threshold: $WarningDaysThreshold days before expiration" -ForegroundColor Gray

    try {
        $certificates = Get-AzWebAppCertificate
        $results = @()
        $alertItems = @()

        foreach ($cert in $certificates) {
            $daysUntilExpiry = ($cert.ExpirationDate - (Get-Date)).Days

            $status = if ($daysUntilExpiry -lt 0) {
                "EXPIRED"
            } elseif ($daysUntilExpiry -le $WarningDaysThreshold) {
                "EXPIRING_SOON"
            } else {
                "OK"
            }

            $statusColor = switch ($status) {
                "EXPIRED"       { "Red" }
                "EXPIRING_SOON" { "Yellow" }
                "OK"            { "Green" }
            }

            $result = [PSCustomObject]@{
                CertName       = $cert.Name
                SubjectName    = $cert.SubjectName
                Thumbprint     = $cert.Thumbprint
                ExpirationDate = $cert.ExpirationDate.ToString('yyyy-MM-dd')
                DaysRemaining  = $daysUntilExpiry
                Status         = $status
                ResourceGroup  = $cert.ResourceGroupName
            }
            $results += $result

            if ($status -ne "OK") {
                $alertItems += $result
            }

            Write-Host "  $($cert.SubjectName.PadRight(40)) Expires: $($cert.ExpirationDate.ToString('yyyy-MM-dd')) ($daysUntilExpiry days) [$status]" -ForegroundColor $statusColor
        }

        if ($alertItems.Count -gt 0 -and $SendAlert) {
            $message = "SSL Certificate Alert:`n"
            $message += ($alertItems | ForEach-Object {
                "$($_.SubjectName): $($_.Status) ($($_.DaysRemaining) days remaining)"
            }) -join "`n"

            Send-AlertNotification -Title "SSL Certificate Expiration Warning" `
                -Message $message -Severity "Critical"
        }

        Write-Host "`nTotal certificates: $($results.Count) | OK: $(($results | Where-Object Status -eq 'OK').Count) | Expiring: $(($results | Where-Object Status -eq 'EXPIRING_SOON').Count) | Expired: $(($results | Where-Object Status -eq 'EXPIRED').Count)" -ForegroundColor White

        return $results
    }
    catch {
        Write-Error "Certificate check failed: $_"
    }
}

function Get-AzAppServiceHealth {
    <#
    .SYNOPSIS
        Returns health status and performance metrics for App Services.

    .PARAMETER ResourceGroupName
        Filter by resource group. If omitted, checks all App Services in the subscription.

    .PARAMETER IncludeSlots
        If specified, includes deployment slot health.

    .EXAMPLE
        Get-AzAppServiceHealth -ResourceGroupName "rg-web-apps" -IncludeSlots
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$ResourceGroupName,

        [Parameter()]
        [switch]$IncludeSlots
    )

    Write-Host "Checking App Service health..." -ForegroundColor Cyan

    try {
        $apps = if ($ResourceGroupName) {
            Get-AzWebApp -ResourceGroupName $ResourceGroupName
        } else {
            Get-AzWebApp
        }

        $healthResults = @()

        foreach ($app in $apps) {
            $state = $app.State
            $stateColor = if ($state -eq "Running") { "Green" } else { "Red" }

            $healthResult = [PSCustomObject]@{
                AppName        = $app.Name
                ResourceGroup  = $app.ResourceGroup
                State          = $state
                Kind           = $app.Kind
                DefaultHostName = $app.DefaultHostName
                HttpsOnly      = $app.HttpsOnly
                AppServicePlan = ($app.ServerFarmId -split '/')[-1]
                Location       = $app.Location
                Slots          = @()
            }

            Write-Host "  $($app.Name.PadRight(35)) [$state]" -ForegroundColor $stateColor

            if ($IncludeSlots) {
                try {
                    $slots = Get-AzWebAppSlot -ResourceGroupName $app.ResourceGroup -Name $app.Name -ErrorAction SilentlyContinue
                    foreach ($slot in $slots) {
                        $slotName = ($slot.Name -split '/')[-1]
                        $slotColor = if ($slot.State -eq "Running") { "Green" } else { "Red" }
                        Write-Host "    Slot: $($slotName.PadRight(25)) [$($slot.State)]" -ForegroundColor $slotColor

                        $healthResult.Slots += [PSCustomObject]@{
                            SlotName = $slotName
                            State    = $slot.State
                            Hostname = $slot.DefaultHostName
                        }
                    }
                }
                catch {
                    Write-Verbose "No slots found for $($app.Name)"
                }
            }

            $healthResults += $healthResult
        }

        $runningCount = ($healthResults | Where-Object State -eq "Running").Count
        $stoppedCount = ($healthResults | Where-Object State -ne "Running").Count

        Write-Host "`nSummary: $($healthResults.Count) apps | $runningCount running | $stoppedCount stopped" -ForegroundColor White

        return $healthResults
    }
    catch {
        Write-Error "App Service health check failed: $_"
    }
}

function Get-AzAutoscaleActivity {
    <#
    .SYNOPSIS
        Reviews recent autoscale events for an App Service Plan.

    .PARAMETER AppServicePlanName
        Name of the App Service Plan to check.

    .PARAMETER ResourceGroupName
        Resource group of the App Service Plan.

    .PARAMETER Hours
        Number of hours to look back for autoscale events. Default: 24.

    .EXAMPLE
        Get-AzAutoscaleActivity -AppServicePlanName "asp-production" -ResourceGroupName "rg-web" -Hours 48
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$AppServicePlanName,

        [Parameter()]
        [string]$ResourceGroupName,

        [Parameter()]
        [int]$Hours = 24
    )

    Write-Host "Checking autoscale activity for '$AppServicePlanName' (last $Hours hours)..." -ForegroundColor Cyan

    try {
        $startTime = (Get-Date).AddHours(-$Hours)

        $events = Get-AzActivityLog -StartTime $startTime `
            -ResourceProvider "Microsoft.Insights" `
            -Status "Succeeded" |
            Where-Object {
                $_.OperationName.Value -like "*autoscale*" -and
                $_.ResourceGroupName -eq $ResourceGroupName
            }

        if ($events.Count -eq 0) {
            Write-Host "  No autoscale events found in the last $Hours hours." -ForegroundColor Green
            return @()
        }

        $results = foreach ($event in $events) {
            $detail = [PSCustomObject]@{
                Timestamp   = $event.EventTimestamp
                Operation   = $event.OperationName.LocalizedValue
                Description = $event.Description
                Status      = $event.Status.Value
                Caller      = $event.Caller
            }

            $color = if ($event.Description -match "scale up|increased") { "Yellow" }
                     elseif ($event.Description -match "scale down|decreased") { "Cyan" }
                     else { "White" }

            Write-Host "  $($event.EventTimestamp.ToString('MM/dd HH:mm')) | $($event.Description)" -ForegroundColor $color
            $detail
        }

        Write-Host "`nTotal autoscale events: $($results.Count)" -ForegroundColor White
        return $results
    }
    catch {
        Write-Error "Failed to retrieve autoscale activity: $_"
    }
}
