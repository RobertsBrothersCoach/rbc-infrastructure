<#
.SYNOPSIS
    Azure Automation Runbook for scheduled environment startup
.DESCRIPTION
    This runbook is executed by Azure Automation on a schedule to start environments at 7 AM EST Monday-Friday.
    It runs as a managed identity with appropriate permissions.
.NOTES
    Schedule: Monday-Friday at 7:00 AM EST
    Required Modules: Az.Accounts, Az.Resources, Az.ContainerInstance, Az.WebApps, Az.PostgreSql
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$EnvironmentName = "Development",
    
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupName = "rg-tourbus-dev"
)

# Check if today is a weekday (Monday-Friday)
$dayOfWeek = (Get-Date).DayOfWeek
if ($dayOfWeek -eq 'Saturday' -or $dayOfWeek -eq 'Sunday') {
    Write-Output "Today is $dayOfWeek - skipping startup for weekend"
    exit 0
}

# Authenticate using Managed Identity
Write-Output "Authenticating with Azure using Managed Identity..."
try {
    Connect-AzAccount -Identity
    Write-Output "Successfully authenticated with Azure"
}
catch {
    Write-Error "Failed to authenticate with Azure: $_"
    throw
}

# Set subscription context if needed
$subscriptionId = Get-AutomationVariable -Name "SubscriptionId" -ErrorAction SilentlyContinue
if ($subscriptionId) {
    Set-AzContext -Subscription $subscriptionId
    Write-Output "Set context to subscription: $subscriptionId"
}

# Import the startup script functions
. .\Startup-Environment.ps1

# Override the logging function for Azure Automation
function Write-LogMessage {
    param(
        [string]$Message,
        [ValidateSet("Info", "Warning", "Error", "Success")]
        [string]$Level = "Info"
    )
    
    switch ($Level) {
        "Error"   { Write-Error $Message }
        "Warning" { Write-Warning $Message }
        default   { Write-Output "[$Level] $Message" }
    }
}

# Execute startup
try {
    Write-Output "Starting scheduled startup for $EnvironmentName environment"
    Write-Output "Resource Group: $ResourceGroupName"
    Write-Output "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    
    # Call the main startup function
    Main
    
    Write-Output "Scheduled startup completed successfully"
}
catch {
    Write-Error "Scheduled startup failed: $_"
    
    # Send alert if webhook is configured
    $alertWebhook = Get-AutomationVariable -Name "AlertWebhookUrl" -ErrorAction SilentlyContinue
    if ($alertWebhook) {
        $alertMessage = @{
            text = "⚠️ Scheduled startup failed for $EnvironmentName environment: $_"
        } | ConvertTo-Json
        
        Invoke-RestMethod -Uri $alertWebhook -Method Post -Body $alertMessage -ContentType 'application/json'
    }
    
    throw
}