function Test-AzVpnGatewayHealth {
    <#
    .SYNOPSIS
        Checks VPN gateway connection status and tunnel health.

    .PARAMETER ResourceGroupName
        Resource group containing the VPN gateway.

    .PARAMETER GatewayName
        Specific gateway name. If omitted, checks all gateways in the resource group.

    .PARAMETER SendAlert
        If specified, sends alerts for unhealthy tunnels.

    .EXAMPLE
        Test-AzVpnGatewayHealth -ResourceGroupName "rg-networking"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ResourceGroupName,

        [Parameter()]
        [string]$GatewayName,

        [Parameter()]
        [switch]$SendAlert
    )

    Write-Host "Checking VPN gateway health in '$ResourceGroupName'..." -ForegroundColor Cyan

    try {
        $gateways = if ($GatewayName) {
            @(Get-AzVirtualNetworkGateway -ResourceGroupName $ResourceGroupName -Name $GatewayName)
        } else {
            Get-AzVirtualNetworkGateway -ResourceGroupName $ResourceGroupName
        }

        $results = @()
        $unhealthyConnections = @()

        foreach ($gw in $gateways) {
            Write-Host "`n  Gateway: $($gw.Name) | SKU: $($gw.Sku.Name) | Provisioning: $($gw.ProvisioningState)" -ForegroundColor White

            $connections = Get-AzVirtualNetworkGatewayConnection -ResourceGroupName $ResourceGroupName |
                Where-Object {
                    $_.VirtualNetworkGateway1.Id -eq $gw.Id -or
                    $_.VirtualNetworkGateway2.Id -eq $gw.Id
                }

            foreach ($conn in $connections) {
                $status = $conn.ConnectionStatus
                $statusColor = switch ($status) {
                    "Connected"    { "Green" }
                    "Connecting"   { "Yellow" }
                    "NotConnected" { "Red" }
                    default        { "Gray" }
                }

                $ingressBytes = if ($conn.IngressBytesTransferred) {
                    [math]::Round($conn.IngressBytesTransferred / 1MB, 2)
                } else { 0 }

                $egressBytes = if ($conn.EgressBytesTransferred) {
                    [math]::Round($conn.EgressBytesTransferred / 1MB, 2)
                } else { 0 }

                $connectionResult = [PSCustomObject]@{
                    GatewayName      = $gw.Name
                    ConnectionName   = $conn.Name
                    ConnectionType   = $conn.ConnectionType
                    Status           = $status
                    ProvisioningState = $conn.ProvisioningState
                    IngressMB        = $ingressBytes
                    EgressMB         = $egressBytes
                    SharedKey        = if ($conn.SharedKey) { "Configured" } else { "Missing" }
                    RoutingWeight    = $conn.RoutingWeight
                }

                $results += $connectionResult

                if ($status -ne "Connected") {
                    $unhealthyConnections += $connectionResult
                }

                Write-Host "    Connection: $($conn.Name.PadRight(30)) [$status] | Type: $($conn.ConnectionType) | In: ${ingressBytes}MB Out: ${egressBytes}MB" -ForegroundColor $statusColor
            }

            if ($connections.Count -eq 0) {
                Write-Host "    No connections found for this gateway." -ForegroundColor Gray
            }
        }

        if ($unhealthyConnections.Count -gt 0 -and $SendAlert) {
            $message = "VPN Gateway Alert: $($unhealthyConnections.Count) unhealthy connections`n"
            $message += ($unhealthyConnections | ForEach-Object {
                "$($_.ConnectionName): $($_.Status) (Gateway: $($_.GatewayName))"
            }) -join "`n"

            Send-AlertNotification -Title "VPN Gateway Health Alert" `
                -Message $message -Severity "Critical"
        }

        $connectedCount = ($results | Where-Object Status -eq "Connected").Count
        Write-Host "`nSummary: $($results.Count) connections | $connectedCount connected | $($unhealthyConnections.Count) unhealthy" -ForegroundColor White

        return $results
    }
    catch {
        Write-Error "VPN gateway health check failed: $_"
    }
}

function Test-AzTrafficManagerFailover {
    <#
    .SYNOPSIS
        Validates Traffic Manager endpoint health and optionally simulates a failover.

    .PARAMETER ProfileName
        Name of the Traffic Manager profile.

    .PARAMETER ResourceGroupName
        Resource group of the Traffic Manager profile.

    .PARAMETER SimulateFailover
        If specified, reports what would happen if the primary endpoint went offline.

    .EXAMPLE
        Test-AzTrafficManagerFailover -ProfileName "tm-production" -ResourceGroupName "rg-networking"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProfileName,

        [Parameter()]
        [string]$ResourceGroupName,

        [Parameter()]
        [switch]$SimulateFailover
    )

    Write-Host "Checking Traffic Manager profile: $ProfileName" -ForegroundColor Cyan

    try {
        $profile = if ($ResourceGroupName) {
            Get-AzTrafficManagerProfile -Name $ProfileName -ResourceGroupName $ResourceGroupName
        } else {
            Get-AzTrafficManagerProfile | Where-Object { $_.Name -eq $ProfileName }
        }

        if (-not $profile) {
            Write-Warning "Traffic Manager profile '$ProfileName' not found."
            return
        }

        Write-Host "  Routing Method: $($profile.TrafficRoutingMethod)" -ForegroundColor White
        Write-Host "  DNS Name: $($profile.RelativeDnsName).trafficmanager.net" -ForegroundColor White
        Write-Host "  Profile Status: $($profile.ProfileStatus)" -ForegroundColor White
        Write-Host "  Monitor Protocol: $($profile.MonitorProtocol) | Port: $($profile.MonitorPort) | Path: $($profile.MonitorPath)" -ForegroundColor Gray

        $endpoints = $profile.Endpoints
        $results = @()

        Write-Host "`n  Endpoints:" -ForegroundColor White

        foreach ($ep in $endpoints) {
            $statusColor = switch ($ep.EndpointMonitorStatus) {
                "Online"   { "Green" }
                "Degraded" { "Yellow" }
                "Disabled" { "Gray" }
                default    { "Red" }
            }

            $result = [PSCustomObject]@{
                EndpointName    = $ep.Name
                Type            = $ep.Type.Split('/')[-1]
                Target          = $ep.Target
                Status          = $ep.EndpointStatus
                MonitorStatus   = $ep.EndpointMonitorStatus
                Priority        = $ep.Priority
                Weight          = $ep.Weight
                Location        = $ep.EndpointLocation
            }
            $results += $result

            Write-Host "    $($ep.Name.PadRight(25)) Target: $($ep.Target.PadRight(35)) Monitor: $($ep.EndpointMonitorStatus) | Priority: $($ep.Priority)" -ForegroundColor $statusColor
        }

        if ($SimulateFailover) {
            Write-Host "`n  Failover Simulation:" -ForegroundColor Yellow

            $onlineEndpoints = $results | Where-Object MonitorStatus -eq "Online" | Sort-Object Priority

            if ($onlineEndpoints.Count -le 1) {
                Write-Host "    WARNING: Only $($onlineEndpoints.Count) healthy endpoint(s). No failover target available!" -ForegroundColor Red
            } else {
                $primary = $onlineEndpoints[0]
                $failoverTarget = $onlineEndpoints[1]
                Write-Host "    If '$($primary.EndpointName)' (Priority $($primary.Priority)) goes offline:" -ForegroundColor White
                Write-Host "    Traffic would route to '$($failoverTarget.EndpointName)' (Priority $($failoverTarget.Priority)) at $($failoverTarget.Target)" -ForegroundColor Green
            }
        }

        return [PSCustomObject]@{
            ProfileName    = $ProfileName
            RoutingMethod  = $profile.TrafficRoutingMethod
            ProfileStatus  = $profile.ProfileStatus
            TotalEndpoints = $endpoints.Count
            OnlineCount    = ($results | Where-Object MonitorStatus -eq "Online").Count
            Endpoints      = $results
        }
    }
    catch {
        Write-Error "Traffic Manager check failed: $_"
    }
}

function Test-AzHybridDnsResolution {
    <#
    .SYNOPSIS
        Tests DNS resolution for hybrid environment domains from the current host.

    .PARAMETER Domains
        Array of domain names to resolve.

    .PARAMETER DnsServers
        Optional array of DNS server IPs to test against.

    .EXAMPLE
        Test-AzHybridDnsResolution -Domains @("app.internal.corp", "api.internal.corp")
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Domains,

        [Parameter()]
        [string[]]$DnsServers
    )

    Write-Host "Testing hybrid DNS resolution..." -ForegroundColor Cyan

    $results = @()

    foreach ($domain in $Domains) {
        if ($DnsServers) {
            foreach ($dns in $DnsServers) {
                try {
                    $resolved = Resolve-DnsName -Name $domain -Server $dns -ErrorAction Stop
                    $ip = ($resolved | Where-Object { $_.QueryType -eq 'A' } | Select-Object -First 1).IPAddress

                    Write-Host "  $($domain.PadRight(35)) via $($dns.PadRight(15)) -> $ip" -ForegroundColor Green

                    $results += [PSCustomObject]@{
                        Domain    = $domain
                        DnsServer = $dns
                        Resolved  = $true
                        IPAddress = $ip
                        Error     = ""
                    }
                }
                catch {
                    Write-Host "  $($domain.PadRight(35)) via $($dns.PadRight(15)) -> FAILED" -ForegroundColor Red

                    $results += [PSCustomObject]@{
                        Domain    = $domain
                        DnsServer = $dns
                        Resolved  = $false
                        IPAddress = ""
                        Error     = $_.Exception.Message
                    }
                }
            }
        }
        else {
            try {
                $resolved = Resolve-DnsName -Name $domain -ErrorAction Stop
                $ip = ($resolved | Where-Object { $_.QueryType -eq 'A' } | Select-Object -First 1).IPAddress

                Write-Host "  $($domain.PadRight(35)) -> $ip" -ForegroundColor Green

                $results += [PSCustomObject]@{
                    Domain    = $domain
                    DnsServer = "System Default"
                    Resolved  = $true
                    IPAddress = $ip
                    Error     = ""
                }
            }
            catch {
                Write-Host "  $($domain.PadRight(35)) -> FAILED" -ForegroundColor Red

                $results += [PSCustomObject]@{
                    Domain    = $domain
                    DnsServer = "System Default"
                    Resolved  = $false
                    IPAddress = ""
                    Error     = $_.Exception.Message
                }
            }
        }
    }

    $resolvedCount = ($results | Where-Object Resolved).Count
    Write-Host "`nResolved: $resolvedCount of $($results.Count) lookups" -ForegroundColor White

    return $results
}
