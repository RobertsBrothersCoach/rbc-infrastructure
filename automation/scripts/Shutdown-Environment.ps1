<#
.SYNOPSIS
    Shutdown Azure environment resources to reduce costs during off-hours
.DESCRIPTION
    This script shuts down Azure resources for development and QA environments at 7 PM EST daily.
    Resources are deallocated to achieve zero cost during off-hours.
.PARAMETER EnvironmentName
    The environment to shut down (Development or QA)
.PARAMETER ResourceGroupName
    The resource group containing the environment resources
.PARAMETER Force
    Skip confirmation prompts
.EXAMPLE
    .\Shutdown-Environment.ps1 -EnvironmentName "Development" -ResourceGroupName "rg-tourbus-dev"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("Development", "QA")]
    [string]$EnvironmentName,
    
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,
    
    [switch]$Force
)

# Import Azure modules
Import-Module Az.Accounts -ErrorAction Stop
Import-Module Az.Resources -ErrorAction Stop
Import-Module Az.ContainerInstance -ErrorAction Stop
Import-Module Az.WebApps -ErrorAction Stop
Import-Module Az.PostgreSql -ErrorAction Stop

# Configuration
$script:ErrorActionPreference = "Stop"
$script:ShutdownTimestamp = Get-Date
$script:LogFile = "shutdown-$EnvironmentName-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

# Logging function
function Write-LogMessage {
    param(
        [string]$Message,
        [ValidateSet("Info", "Warning", "Error", "Success")]
        [string]$Level = "Info"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timestamp [$Level] $Message"
    
    # Color coding for console output
    switch ($Level) {
        "Info"    { Write-Host $logMessage -ForegroundColor White }
        "Warning" { Write-Host $logMessage -ForegroundColor Yellow }
        "Error"   { Write-Host $logMessage -ForegroundColor Red }
        "Success" { Write-Host $logMessage -ForegroundColor Green }
    }
    
    # Also write to log file
    Add-Content -Path $LogFile -Value $logMessage
}

# Function to verify Azure connection
function Test-AzureConnection {
    try {
        $context = Get-AzContext
        if (-not $context) {
            throw "No Azure context found. Please run Connect-AzAccount first."
        }
        Write-LogMessage "Connected to Azure subscription: $($context.Subscription.Name)" -Level Success
        return $true
    }
    catch {
        Write-LogMessage "Azure connection failed: $_" -Level Error
        return $false
    }
}

# Function to shutdown Container Apps
function Stop-ContainerApps {
    param([string]$ResourceGroupName)
    
    Write-LogMessage "Shutting down Container Apps..." -Level Info
    
    try {
        # Get all Container Apps in the resource group
        $containerApps = Get-AzContainerApp -ResourceGroupName $ResourceGroupName
        
        foreach ($app in $containerApps) {
            Write-LogMessage "Scaling Container App '$($app.Name)' to 0 replicas" -Level Info
            
            # Scale to 0 replicas
            Update-AzContainerApp `
                -Name $app.Name `
                -ResourceGroupName $ResourceGroupName `
                -MinReplicas 0 `
                -MaxReplicas 0
            
            Write-LogMessage "Container App '$($app.Name)' scaled down successfully" -Level Success
        }
    }
    catch {
        Write-LogMessage "Failed to shutdown Container Apps: $_" -Level Error
        throw
    }
}

# Function to stop App Services
function Stop-AppServices {
    param([string]$ResourceGroupName)
    
    Write-LogMessage "Stopping App Services..." -Level Info
    
    try {
        # Get all App Services in the resource group
        $webApps = Get-AzWebApp -ResourceGroupName $ResourceGroupName
        
        foreach ($webapp in $webApps) {
            Write-LogMessage "Stopping App Service '$($webapp.Name)'" -Level Info
            
            Stop-AzWebApp `
                -Name $webapp.Name `
                -ResourceGroupName $ResourceGroupName `
                -Force
            
            Write-LogMessage "App Service '$($webapp.Name)' stopped successfully" -Level Success
        }
    }
    catch {
        Write-LogMessage "Failed to stop App Services: $_" -Level Error
        throw
    }
}

# Function to pause PostgreSQL servers
function Stop-PostgreSQLServers {
    param([string]$ResourceGroupName)
    
    Write-LogMessage "Pausing PostgreSQL Flexible Servers..." -Level Info
    
    try {
        # Get all PostgreSQL Flexible Servers in the resource group
        $pgServers = Get-AzPostgreSqlFlexibleServer -ResourceGroupName $ResourceGroupName
        
        foreach ($server in $pgServers) {
            Write-LogMessage "Stopping PostgreSQL server '$($server.Name)'" -Level Info
            
            # Stop the server (deallocate compute)
            Stop-AzPostgreSqlFlexibleServer `
                -Name $server.Name `
                -ResourceGroupName $ResourceGroupName `
                -NoWait
            
            Write-LogMessage "PostgreSQL server '$($server.Name)' stop initiated" -Level Success
        }
    }
    catch {
        Write-LogMessage "Failed to pause PostgreSQL servers: $_" -Level Error
        throw
    }
}

# Function to deallocate other compute resources
function Stop-ComputeResources {
    param([string]$ResourceGroupName)
    
    Write-LogMessage "Deallocating compute resources..." -Level Info
    
    try {
        # Stop any Virtual Machines
        $vms = Get-AzVM -ResourceGroupName $ResourceGroupName
        foreach ($vm in $vms) {
            Write-LogMessage "Deallocating VM '$($vm.Name)'" -Level Info
            Stop-AzVM -Name $vm.Name -ResourceGroupName $ResourceGroupName -Force
            Write-LogMessage "VM '$($vm.Name)' deallocated" -Level Success
        }
        
        # Stop any AKS clusters
        $aksClusters = Get-AzAksCluster -ResourceGroupName $ResourceGroupName
        foreach ($cluster in $aksClusters) {
            Write-LogMessage "Stopping AKS cluster '$($cluster.Name)'" -Level Info
            Stop-AzAksCluster -Name $cluster.Name -ResourceGroupName $ResourceGroupName
            Write-LogMessage "AKS cluster '$($cluster.Name)' stopped" -Level Success
        }
    }
    catch {
        Write-LogMessage "Failed to deallocate compute resources: $_" -Level Warning
        # Continue execution even if some resources fail
    }
}

# Function to save resource state before shutdown
function Save-ResourceState {
    param([string]$ResourceGroupName)
    
    Write-LogMessage "Saving resource state before shutdown..." -Level Info
    
    try {
        $stateFile = "resource-state-$EnvironmentName-$(Get-Date -Format 'yyyyMMdd').json"
        
        # Collect resource states
        $resourceState = @{
            Timestamp = $ShutdownTimestamp
            Environment = $EnvironmentName
            ResourceGroup = $ResourceGroupName
            Resources = @()
        }
        
        # Get all resources and their current state
        $resources = Get-AzResource -ResourceGroupName $ResourceGroupName
        foreach ($resource in $resources) {
            $resourceState.Resources += @{
                Name = $resource.Name
                Type = $resource.ResourceType
                Location = $resource.Location
                Id = $resource.ResourceId
            }
        }
        
        # Save to JSON file
        $resourceState | ConvertTo-Json -Depth 10 | Out-File $stateFile
        Write-LogMessage "Resource state saved to $stateFile" -Level Success
    }
    catch {
        Write-LogMessage "Failed to save resource state: $_" -Level Warning
        # Non-critical, continue execution
    }
}

# Function to send notification
function Send-ShutdownNotification {
    param(
        [string]$EnvironmentName,
        [string]$Status,
        [string]$Details
    )
    
    Write-LogMessage "Sending shutdown notification..." -Level Info
    
    try {
        # If Teams webhook URL is configured
        if ($env:TEAMS_WEBHOOK_URL) {
            $message = @{
                "@type" = "MessageCard"
                "@context" = "http://schema.org/extensions"
                "summary" = "Environment Shutdown Notification"
                "themeColor" = if ($Status -eq "Success") { "00FF00" } else { "FF0000" }
                "title" = "Environment Shutdown: $EnvironmentName"
                "sections" = @(
                    @{
                        "activityTitle" = "Shutdown Status"
                        "activitySubtitle" = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                        "facts" = @(
                            @{
                                "name" = "Environment"
                                "value" = $EnvironmentName
                            },
                            @{
                                "name" = "Status"
                                "value" = $Status
                            },
                            @{
                                "name" = "Details"
                                "value" = $Details
                            }
                        )
                    }
                )
            }
            
            $messageJson = $message | ConvertTo-Json -Depth 10
            Invoke-RestMethod -Uri $env:TEAMS_WEBHOOK_URL -Method Post -Body $messageJson -ContentType 'application/json'
            Write-LogMessage "Notification sent to Teams" -Level Success
        }
    }
    catch {
        Write-LogMessage "Failed to send notification: $_" -Level Warning
        # Non-critical, continue execution
    }
}

# Main execution
function Main {
    Write-LogMessage "========================================" -Level Info
    Write-LogMessage "Starting environment shutdown process" -Level Info
    Write-LogMessage "Environment: $EnvironmentName" -Level Info
    Write-LogMessage "Resource Group: $ResourceGroupName" -Level Info
    Write-LogMessage "========================================" -Level Info
    
    # Verify Azure connection
    if (-not (Test-AzureConnection)) {
        throw "Azure connection required. Please run Connect-AzAccount"
    }
    
    # Confirm shutdown unless Force flag is used
    if (-not $Force) {
        $confirmation = Read-Host "Are you sure you want to shutdown the $EnvironmentName environment? (yes/no)"
        if ($confirmation -ne "yes") {
            Write-LogMessage "Shutdown cancelled by user" -Level Warning
            return
        }
    }
    
    try {
        # Save current resource state
        Save-ResourceState -ResourceGroupName $ResourceGroupName
        
        # Execute shutdown in order of dependencies
        
        # 1. Scale down Container Apps first
        Stop-ContainerApps -ResourceGroupName $ResourceGroupName
        
        # 2. Stop App Services
        Stop-AppServices -ResourceGroupName $ResourceGroupName
        
        # 3. Stop other compute resources
        Stop-ComputeResources -ResourceGroupName $ResourceGroupName
        
        # 4. Finally pause databases (after apps are stopped)
        Stop-PostgreSQLServers -ResourceGroupName $ResourceGroupName
        
        # Calculate estimated cost savings
        $monthlySavings = switch ($EnvironmentName) {
            "Development" { 1340 }  # $1,400 - $60
            "QA" { 980 }           # $1,100 - $120
        }
        
        $details = "All resources successfully shut down. Estimated monthly savings: $$monthlySavings"
        Write-LogMessage $details -Level Success
        
        # Send success notification
        Send-ShutdownNotification `
            -EnvironmentName $EnvironmentName `
            -Status "Success" `
            -Details $details
            
        Write-LogMessage "========================================" -Level Info
        Write-LogMessage "Environment shutdown completed successfully" -Level Success
        Write-LogMessage "Log file: $LogFile" -Level Info
        Write-LogMessage "========================================" -Level Info
    }
    catch {
        $errorDetails = "Shutdown failed: $_"
        Write-LogMessage $errorDetails -Level Error
        
        # Send failure notification
        Send-ShutdownNotification `
            -EnvironmentName $EnvironmentName `
            -Status "Failed" `
            -Details $errorDetails
            
        throw
    }
}

# Execute main function
Main