# azure-toolkit.psm1
# Root module loader for Azure PowerShell Automation Toolkit

$ModulePath = $PSScriptRoot

# Import all module files
$ModuleFolders = @(
    'src/modules/AzCostMonitor',
    'src/modules/AzResourceGovernance',
    'src/modules/AzAppServiceOps',
    'src/modules/AzHybridConnectivity'
)

foreach ($folder in $ModuleFolders) {
    $modulePath = Join-Path $ModulePath $folder
    if (Test-Path $modulePath) {
        $psFiles = Get-ChildItem -Path $modulePath -Filter '*.ps1' -Recurse
        foreach ($file in $psFiles) {
            try {
                . $file.FullName
                Write-Verbose "Loaded: $($file.Name)"
            }
            catch {
                Write-Warning "Failed to load $($file.FullName): $_"
            }
        }
    }
}

# Import standalone functions
$FunctionPaths = @(
    'src/functions',
    'src/scripts'
)

foreach ($funcPath in $FunctionPaths) {
    $fullPath = Join-Path $ModulePath $funcPath
    if (Test-Path $fullPath) {
        $psFiles = Get-ChildItem -Path $fullPath -Filter '*.ps1'
        foreach ($file in $psFiles) {
            try {
                . $file.FullName
                Write-Verbose "Loaded: $($file.Name)"
            }
            catch {
                Write-Warning "Failed to load $($file.FullName): $_"
            }
        }
    }
}

# Load configuration helper
function Get-ToolkitConfig {
    [CmdletBinding()]
    param(
        [string]$ConfigPath = (Join-Path $ModulePath 'config/toolkit-config.json')
    )

    if (-not (Test-Path $ConfigPath)) {
        Write-Warning "Config file not found at $ConfigPath. Using defaults."
        return @{
            alerting = @{
                teams_webhook_url = ""
                slack_webhook_url = ""
                smtp_server       = ""
                smtp_from         = ""
                smtp_to           = @()
            }
            defaults = @{
                cost_threshold_percent = 25
                cert_warning_days      = 30
                log_retention_days     = 90
                required_tags          = @("Environment", "Owner", "CostCenter")
            }
        }
    }

    return Get-Content $ConfigPath -Raw | ConvertFrom-Json -AsHashtable
}

Write-Verbose "Azure PowerShell Automation Toolkit loaded successfully."
