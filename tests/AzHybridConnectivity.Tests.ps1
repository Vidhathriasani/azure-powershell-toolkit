BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'src' 'modules' 'AzHybridConnectivity' 'AzHybridConnectivity.ps1'
    . $ModulePath
}

Describe 'Test-AzVpnGatewayHealth' {
    Context 'When all tunnels are connected' {
        BeforeAll {
            Mock Get-AzVirtualNetworkGateway {
                @([PSCustomObject]@{ Name = 'vng-prod'; Id = '/sub/rg/vng-prod'; Sku = @{ Name = 'VpnGw1' }; ProvisioningState = 'Succeeded' })
            }
            Mock Get-AzVirtualNetworkGatewayConnection {
                @([PSCustomObject]@{
                    Name = 'conn-onprem'; ConnectionStatus = 'Connected'; ConnectionType = 'IPsec'
                    ProvisioningState = 'Succeeded'; VirtualNetworkGateway1 = @{ Id = '/sub/rg/vng-prod' }
                    IngressBytesTransferred = 1048576; EgressBytesTransferred = 2097152
                    SharedKey = 'secret'; RoutingWeight = 10
                })
            }
        }

        It 'Should report all connections as connected' {
            $result = Test-AzVpnGatewayHealth -ResourceGroupName 'rg-networking'
            $result | Should -Not -BeNullOrEmpty
            $result[0].Status | Should -Be 'Connected'
        }
    }

    Context 'When a tunnel is disconnected' {
        BeforeAll {
            Mock Get-AzVirtualNetworkGateway {
                @([PSCustomObject]@{ Name = 'vng-prod'; Id = '/sub/rg/vng-prod'; Sku = @{ Name = 'VpnGw1' }; ProvisioningState = 'Succeeded' })
            }
            Mock Get-AzVirtualNetworkGatewayConnection {
                @([PSCustomObject]@{
                    Name = 'conn-onprem'; ConnectionStatus = 'NotConnected'; ConnectionType = 'IPsec'
                    ProvisioningState = 'Succeeded'; VirtualNetworkGateway1 = @{ Id = '/sub/rg/vng-prod' }
                    IngressBytesTransferred = 0; EgressBytesTransferred = 0
                    SharedKey = 'secret'; RoutingWeight = 10
                })
            }
        }

        It 'Should flag disconnected tunnels' {
            $result = Test-AzVpnGatewayHealth -ResourceGroupName 'rg-networking'
            $result[0].Status | Should -Be 'NotConnected'
        }
    }
}

Describe 'Test-AzTrafficManagerFailover' {
    BeforeAll {
        Mock Get-AzTrafficManagerProfile {
            [PSCustomObject]@{
                Name = 'tm-prod'; TrafficRoutingMethod = 'Priority'
                RelativeDnsName = 'tm-prod'; ProfileStatus = 'Enabled'
                MonitorProtocol = 'HTTPS'; MonitorPort = 443; MonitorPath = '/health'
                Endpoints = @(
                    [PSCustomObject]@{ Name = 'primary'; Type = 'Microsoft.Network/trafficManagerProfiles/externalEndpoints'; Target = 'app.eastus.azurewebsites.net'; EndpointStatus = 'Enabled'; EndpointMonitorStatus = 'Online'; Priority = 1; Weight = 1; EndpointLocation = 'East US' },
                    [PSCustomObject]@{ Name = 'secondary'; Type = 'Microsoft.Network/trafficManagerProfiles/externalEndpoints'; Target = 'app.westus.azurewebsites.net'; EndpointStatus = 'Enabled'; EndpointMonitorStatus = 'Online'; Priority = 2; Weight = 1; EndpointLocation = 'West US' }
                )
            }
        }
    }

    It 'Should return profile details with endpoint status' {
        $result = Test-AzTrafficManagerFailover -ProfileName 'tm-prod' -ResourceGroupName 'rg-networking'
        $result.ProfileName | Should -Be 'tm-prod'
        $result.OnlineCount | Should -Be 2
        $result.TotalEndpoints | Should -Be 2
    }

    It 'Should identify failover target during simulation' {
        $result = Test-AzTrafficManagerFailover -ProfileName 'tm-prod' -ResourceGroupName 'rg-networking' -SimulateFailover
        $result.Endpoints[1].EndpointName | Should -Be 'secondary'
    }
}
