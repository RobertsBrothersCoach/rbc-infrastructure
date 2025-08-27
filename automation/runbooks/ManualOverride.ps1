<#
.SYNOPSIS
    Azure Automation Runbook for manual environment control
.DESCRIPTION
    This runbook allows manual override of scheduled shutdown/startup operations.
    Can be triggered via webhook or Azure Portal for immediate action.
.PARAMETER Action
    The action to perform: Shutdown or Startup
.PARAMETER EnvironmentName
    The environment to control (Development or QA)
.PARAMETER ResourceGroupName
    The resource group containing the environment resources
.PARAMETER OverrideSchedule
    If true, disables the next scheduled action
#>

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("Shutdown", "Startup")]
    [string]$Action,
    
    [Parameter(Mandatory=$true)]
    [ValidateSet("Development", "QA")]
    [string]$EnvironmentName,
    
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$false)]
    [bool]$OverrideSchedule = $false
)

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

# Function to update override flag
function Set-OverrideFlag {
    param(
        [string]$EnvironmentName,
        [string]$Action,
        [bool]$Enable
    )
    
    try {
        $variableName = "$EnvironmentName-$Action-Override"
        
        if ($Enable) {
            # Set override flag with expiration (24 hours)
            $expiration = (Get-Date).AddHours(24)
            Set-AutomationVariable -Name $variableName -Value $expiration.ToString()
            Write-Output "Override enabled for $Action until $expiration"
        }
        else {
            # Clear override flag
            Set-AutomationVariable -Name $variableName -Value ""
            Write-Output "Override cleared for $Action"
        }
    }
    catch {
        Write-Warning "Failed to set override flag: $_"
    }
}

# Main execution
try {
    Write-Output "========================================="
    Write-Output "Manual Override Request"
    Write-Output "Action: $Action"
    Write-Output "Environment: $EnvironmentName"
    Write-Output "Resource Group: $ResourceGroupName"
    Write-Output "Override Schedule: $OverrideSchedule"
    Write-Output "Requested at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Write-Output "========================================="
    
    # Import appropriate script based on action
    if ($Action -eq "Shutdown") {
        . .\Shutdown-Environment.ps1
    }
    else {
        . .\Startup-Environment.ps1
    }
    
    # Set override flag if requested
    if ($OverrideSchedule) {
        Set-OverrideFlag -EnvironmentName $EnvironmentName -Action $Action -Enable $true
    }
    
    # Execute the action with Force flag
    if ($Action -eq "Shutdown") {
        $global:Force = $true
    }
    else {
        $global:SkipHealthCheck = $false
    }
    
    Main
    
    Write-Output "========================================="
    Write-Output "Manual override completed successfully"
    Write-Output "========================================="
    
    # Send notification if webhook is configured
    $notificationWebhook = Get-AutomationVariable -Name "NotificationWebhookUrl" -ErrorAction SilentlyContinue
    if ($notificationWebhook) {
        $message = @{
            text = "✅ Manual $Action completed for $EnvironmentName environment"
        } | ConvertTo-Json
        
        Invoke-RestMethod -Uri $notificationWebhook -Method Post -Body $message -ContentType 'application/json'
    }
}
catch {
    Write-Error "Manual override failed: $_"
    
    # Send alert if webhook is configured
    $alertWebhook = Get-AutomationVariable -Name "AlertWebhookUrl" -ErrorAction SilentlyContinue
    if ($alertWebhook) {
        $alertMessage = @{
            text = "⚠️ Manual $Action failed for $EnvironmentName environment: $_"
        } | ConvertTo-Json
        
        Invoke-RestMethod -Uri $alertWebhook -Method Post -Body $alertMessage -ContentType 'application/json'
    }
    
    throw
}