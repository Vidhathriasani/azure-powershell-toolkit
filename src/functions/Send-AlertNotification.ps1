function Send-AlertNotification {
    <#
    .SYNOPSIS
        Unified alert dispatcher supporting Microsoft Teams, Slack, and SMTP email.

    .DESCRIPTION
        Sends alert notifications to configured channels. Reads webhook URLs and SMTP
        settings from the toolkit configuration file. Supports severity levels that
        control message formatting and color coding.

    .PARAMETER Title
        Alert title/subject.

    .PARAMETER Message
        Alert body text.

    .PARAMETER Severity
        Alert severity: Info, Warning, or Critical. Affects message color and formatting.

    .PARAMETER Channels
        Override which channels to use. Default: all configured channels.

    .EXAMPLE
        Send-AlertNotification -Title "Disk Alert" -Message "Unattached disks found" -Severity "Warning"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Title,

        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter()]
        [ValidateSet("Info", "Warning", "Critical")]
        [string]$Severity = "Info",

        [Parameter()]
        [ValidateSet("Teams", "Slack", "Email", "All")]
        [string[]]$Channels = @("All")
    )

    $config = Get-ToolkitConfig
    $alertConfig = $config.alerting
    $sendAll = $Channels -contains "All"
    $timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss UTC')

    $colorMap = @{
        Info     = @{ Teams = "0078D4"; Slack = "#0078D4" }
        Warning  = @{ Teams = "FFC107"; Slack = "#FFC107" }
        Critical = @{ Teams = "DC3545"; Slack = "#DC3545" }
    }

    $emojiMap = @{
        Info     = "ℹ️"
        Warning  = "⚠️"
        Critical = "🚨"
    }

    # Microsoft Teams (Incoming Webhook)
    if (($sendAll -or $Channels -contains "Teams") -and $alertConfig.teams_webhook_url) {
        try {
            $teamsPayload = @{
                "@type"      = "MessageCard"
                "@context"   = "http://schema.org/extensions"
                themeColor   = $colorMap[$Severity].Teams
                summary      = "$($emojiMap[$Severity]) $Title"
                sections     = @(
                    @{
                        activityTitle    = "$($emojiMap[$Severity]) $Title"
                        activitySubtitle = "Azure Toolkit Alert | $timestamp"
                        facts            = @(
                            @{ name = "Severity"; value = $Severity }
                            @{ name = "Timestamp"; value = $timestamp }
                        )
                        text             = $Message
                        markdown         = $true
                    }
                )
            } | ConvertTo-Json -Depth 10

            Invoke-RestMethod -Uri $alertConfig.teams_webhook_url -Method Post `
                -ContentType 'application/json' -Body $teamsPayload | Out-Null

            Write-Verbose "Teams notification sent successfully."
        }
        catch {
            Write-Warning "Failed to send Teams notification: $_"
        }
    }

    # Slack (Incoming Webhook)
    if (($sendAll -or $Channels -contains "Slack") -and $alertConfig.slack_webhook_url) {
        try {
            $slackPayload = @{
                attachments = @(
                    @{
                        color    = $colorMap[$Severity].Slack
                        title    = "$($emojiMap[$Severity]) $Title"
                        text     = $Message
                        footer   = "Azure Toolkit Alert"
                        ts       = [int][double]::Parse((Get-Date -UFormat %s))
                        fields   = @(
                            @{ title = "Severity"; value = $Severity; short = $true }
                        )
                    }
                )
            } | ConvertTo-Json -Depth 10

            Invoke-RestMethod -Uri $alertConfig.slack_webhook_url -Method Post `
                -ContentType 'application/json' -Body $slackPayload | Out-Null

            Write-Verbose "Slack notification sent successfully."
        }
        catch {
            Write-Warning "Failed to send Slack notification: $_"
        }
    }

    # Email (SMTP)
    if (($sendAll -or $Channels -contains "Email") -and $alertConfig.smtp_server -and $alertConfig.smtp_to) {
        try {
            $emailParams = @{
                From       = $alertConfig.smtp_from
                To         = $alertConfig.smtp_to
                Subject    = "[$Severity] $Title"
                Body       = @"
Azure PowerShell Toolkit Alert
==============================
Severity:  $Severity
Title:     $Title
Timestamp: $timestamp

$Message

This alert was sent by the Azure PowerShell Automation Toolkit.
"@
                SmtpServer = $alertConfig.smtp_server
                Port       = if ($alertConfig.smtp_port) { $alertConfig.smtp_port } else { 587 }
                UseSsl     = $true
            }

            if ($alertConfig.smtp_credential) {
                $emailParams.Credential = $alertConfig.smtp_credential
            }

            Send-MailMessage @emailParams
            Write-Verbose "Email notification sent successfully."
        }
        catch {
            Write-Warning "Failed to send email notification: $_"
        }
    }

    Write-Host "[$Severity] Alert dispatched: $Title" -ForegroundColor $(
        switch ($Severity) { "Info" { "Cyan" } "Warning" { "Yellow" } "Critical" { "Red" } }
    )
}
