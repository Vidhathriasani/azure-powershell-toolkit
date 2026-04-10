BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..' 'src' 'modules' 'AzResourceGovernance' 'AzResourceGovernance.ps1'
    . $ModulePath
}

Describe 'Invoke-AzTagComplianceAudit' {
    BeforeAll {
        Mock Get-AzContext { [PSCustomObject]@{ Subscription = [PSCustomObject]@{ Id = 'test-sub' } } }
        Mock Set-AzContext {}
    }

    Context 'When all resources are compliant' {
        BeforeAll {
            Mock Get-AzResource {
                @(
                    [PSCustomObject]@{ Name = 'vm1'; ResourceType = 'Microsoft.Compute/virtualMachines'; ResourceGroupName = 'rg1'; Location = 'eastus'; Tags = @{ Environment = 'prod'; Owner = 'team1' } },
                    [PSCustomObject]@{ Name = 'vm2'; ResourceType = 'Microsoft.Compute/virtualMachines'; ResourceGroupName = 'rg1'; Location = 'eastus'; Tags = @{ Environment = 'dev'; Owner = 'team2' } }
                )
            }
        }

        It 'Should return 100% compliance' {
            $result = Invoke-AzTagComplianceAudit -RequiredTags @("Environment", "Owner")
            $result.CompliancePercent | Should -Be 100
            $result.NonCompliantCount | Should -Be 0
        }
    }

    Context 'When resources are missing tags' {
        BeforeAll {
            Mock Get-AzResource {
                @(
                    [PSCustomObject]@{ Name = 'vm1'; ResourceType = 'Microsoft.Compute/virtualMachines'; ResourceGroupName = 'rg1'; Location = 'eastus'; Tags = @{ Environment = 'prod' } },
                    [PSCustomObject]@{ Name = 'vm2'; ResourceType = 'Microsoft.Compute/virtualMachines'; ResourceGroupName = 'rg1'; Location = 'eastus'; Tags = $null }
                )
            }
        }

        It 'Should report non-compliant resources' {
            $result = Invoke-AzTagComplianceAudit -RequiredTags @("Environment", "Owner")
            $result.NonCompliantCount | Should -BeGreaterThan 0
            $result.CompliancePercent | Should -BeLessThan 100
        }
    }
}

Describe 'Find-AzOrphanedResources' {
    BeforeAll {
        Mock Get-AzContext { [PSCustomObject]@{ Subscription = [PSCustomObject]@{ Id = 'test-sub' } } }
    }

    Context 'When unattached disks exist' {
        BeforeAll {
            Mock Get-AzDisk {
                @([PSCustomObject]@{
                    Name = 'disk-orphan-1'; DiskState = 'Unattached'; ResourceGroupName = 'rg1'
                    Location = 'eastus'; DiskSizeGB = 128; Sku = @{ Name = 'Premium_LRS' }
                    TimeCreated = (Get-Date).AddDays(-30)
                })
            }
            Mock Get-AzPublicIpAddress { @() }
            Mock Get-AzNetworkInterface { @() }
            Mock Get-AzResourceGroup { @() }
        }

        It 'Should find orphaned disks' {
            $result = Find-AzOrphanedResources -IncludeTypes @("Disk")
            $result | Should -Not -BeNullOrEmpty
            $result[0].Type | Should -Be "Unattached Disk"
        }

        It 'Should estimate monthly cost' {
            $result = Find-AzOrphanedResources -IncludeTypes @("Disk")
            $result[0].EstMonthlyCost | Should -BeGreaterThan 0
        }
    }
}
