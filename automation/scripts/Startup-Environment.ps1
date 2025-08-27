<#
.SYNOPSIS
    Start up Azure environment resources for business hours
.DESCRIPTION
    This script starts Azure resources for development and QA environments at 7 AM EST Monday-Friday.
    Resources are restored to their operational state with health checks.
.PARAMETER EnvironmentName
    The environment to start up (Development or QA)
.PARAMETER ResourceGroupName
    The resource group containing the environment resources
.PARAMETER SkipHealthCheck
    Skip health check validation after startup
.EXAMPLE
    .\Startup-Environment.ps1 -EnvironmentName "Development" -ResourceGroupName "rg-tourbus-dev"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("Development", "QA")]
    [string]$EnvironmentName,
    
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,
    
    [switch]$SkipHealthCheck
)

# Import Azure modules
Import-Module Az.Accounts -ErrorAction Stop
Import-Module Az.Resources -ErrorAction Stop
Import-Module Az.ContainerInstance -ErrorAction Stop
Import-Module Az.WebApps -ErrorAction Stop
Import-Module Az.PostgreSql -ErrorAction Stop

# Configuration
$script:ErrorActionPreference = "Stop"
$script:StartupTimestamp = Get-Date
$script:LogFile = "startup-$EnvironmentName-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
$script:MaxRetries = 3
$script:RetryDelaySeconds = 30

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

# Function to start PostgreSQL servers (must start first)
function Start-PostgreSQLServers {
    param([string]$ResourceGroupName)
    
    Write-LogMessage "Starting PostgreSQL Flexible Servers..." -Level Info
    
    try {
        # Get all PostgreSQL Flexible Servers in the resource group
        $pgServers = Get-AzPostgreSqlFlexibleServer -ResourceGroupName $ResourceGroupName
        
        foreach ($server in $pgServers) {
            Write-LogMessage "Starting PostgreSQL server '$($server.Name)'" -Level Info
            
            # Start the server
            Start-AzPostgreSqlFlexibleServer `
                -Name $server.Name `
                -ResourceGroupName $ResourceGroupName `
                -NoWait
            
            Write-LogMessage "PostgreSQL server '$($server.Name)' start initiated" -Level Success
        }
        
        # Wait for all servers to be ready
        Write-LogMessage "Waiting for PostgreSQL servers to be ready..." -Level Info
        Start-Sleep -Seconds 60
        
        # Verify servers are running
        foreach ($server in $pgServers) {
            $retryCount = 0
            $serverReady = $false
            
            while (-not $serverReady -and $retryCount -lt $MaxRetries) {
                $currentServer = Get-AzPostgreSqlFlexibleServer `
                    -Name $server.Name `
                    -ResourceGroupName $ResourceGroupName
                
                if ($currentServer.State -eq "Ready") {
                    Write-LogMessage "PostgreSQL server '$($server.Name)' is ready" -Level Success
                    $serverReady = $true
                }
                else {
                    $retryCount++
                    Write-LogMessage "Waiting for PostgreSQL server '$($server.Name)' (attempt $retryCount/$MaxRetries)" -Level Warning
                    Start-Sleep -Seconds $RetryDelaySeconds
                }
            }
            
            if (-not $serverReady) {
                throw "PostgreSQL server '$($server.Name)' failed to start"
            }
        }
    }
    catch {
        Write-LogMessage "Failed to start PostgreSQL servers: $_" -Level Error
        throw
    }
}

# Function to start App Services
function Start-AppServices {
    param([string]$ResourceGroupName)
    
    Write-LogMessage "Starting App Services..." -Level Info
    
    try {
        # Get all App Services in the resource group
        $webApps = Get-AzWebApp -ResourceGroupName $ResourceGroupName
        
        foreach ($webapp in $webApps) {
            Write-LogMessage "Starting App Service '$($webapp.Name)'" -Level Info
            
            Start-AzWebApp `
                -Name $webapp.Name `
                -ResourceGroupName $ResourceGroupName
            
            Write-LogMessage "App Service '$($webapp.Name)' started successfully" -Level Success
        }
        
        # Wait for apps to be fully started
        Start-Sleep -Seconds 30
    }
    catch {
        Write-LogMessage "Failed to start App Services: $_" -Level Error
        throw
    }
}

# Function to scale up Container Apps
function Start-ContainerApps {
    param([string]$ResourceGroupName)
    
    Write-LogMessage "Scaling up Container Apps..." -Level Info
    
    try {
        # Get all Container Apps in the resource group
        $containerApps = Get-AzContainerApp -ResourceGroupName $ResourceGroupName
        
        foreach ($app in $containerApps) {
            # Determine appropriate replica count based on environment
            $minReplicas = if ($EnvironmentName -eq "Development") { 1 } else { 2 }
            $maxReplicas = if ($EnvironmentName -eq "Development") { 3 } else { 5 }
            
            Write-LogMessage "Scaling Container App '$($app.Name)' to $minReplicas-$maxReplicas replicas" -Level Info
            
            # Scale up replicas
            Update-AzContainerApp `
                -Name $app.Name `
                -ResourceGroupName $ResourceGroupName `
                -MinReplicas $minReplicas `
                -MaxReplicas $maxReplicas
            
            Write-LogMessage "Container App '$($app.Name)' scaled up successfully" -Level Success
        }
    }
    catch {
        Write-LogMessage "Failed to scale up Container Apps: $_" -Level Error
        throw
    }
}

# Function to start other compute resources
function Start-ComputeResources {
    param([string]$ResourceGroupName)
    
    Write-LogMessage "Starting compute resources..." -Level Info
    
    try {
        # Start any Virtual Machines
        $vms = Get-AzVM -ResourceGroupName $ResourceGroupName
        foreach ($vm in $vms) {
            Write-LogMessage "Starting VM '$($vm.Name)'" -Level Info
            Start-AzVM -Name $vm.Name -ResourceGroupName $ResourceGroupName
            Write-LogMessage "VM '$($vm.Name)' started" -Level Success
        }
        
        # Start any AKS clusters
        $aksClusters = Get-AzAksCluster -ResourceGroupName $ResourceGroupName
        foreach ($cluster in $aksClusters) {
            Write-LogMessage "Starting AKS cluster '$($cluster.Name)'" -Level Info
            Start-AzAksCluster -Name $cluster.Name -ResourceGroupName $ResourceGroupName
            Write-LogMessage "AKS cluster '$($cluster.Name)' started" -Level Success
        }
    }
    catch {
        Write-LogMessage "Failed to start compute resources: $_" -Level Warning
        # Continue execution even if some resources fail
    }
}

# Function to perform health checks
function Test-ServiceHealth {
    param([string]$ResourceGroupName)
    
    if ($SkipHealthCheck) {
        Write-LogMessage "Skipping health checks as requested" -Level Warning
        return $true
    }
    
    Write-LogMessage "Performing service health checks..." -Level Info
    
    $healthChecksPassed = $true
    
    try {
        # Check App Services health
        $webApps = Get-AzWebApp -ResourceGroupName $ResourceGroupName
        foreach ($webapp in $webApps) {
            $appUrl = "https://$($webapp.DefaultHostName)/health"
            
            try {
                $response = Invoke-WebRequest -Uri $appUrl -Method Get -TimeoutSec 30 -UseBasicParsing
                if ($response.StatusCode -eq 200) {
                    Write-LogMessage "Health check passed for '$($webapp.Name)'" -Level Success
                }
                else {
                    Write-LogMessage "Health check failed for '$($webapp.Name)': Status $($response.StatusCode)" -Level Warning
                    $healthChecksPassed = $false
                }
            }
            catch {
                Write-LogMessage "Health check failed for '$($webapp.Name)': $_" -Level Warning
                $healthChecksPassed = $false
            }
        }
        
        # Check Container Apps health
        $containerApps = Get-AzContainerApp -ResourceGroupName $ResourceGroupName
        foreach ($app in $containerApps) {
            # Get the ingress FQDN if available
            if ($app.Configuration.Ingress.Fqdn) {
                $appUrl = "https://$($app.Configuration.Ingress.Fqdn)/health"
                
                try {
                    $response = Invoke-WebRequest -Uri $appUrl -Method Get -TimeoutSec 30 -UseBasicParsing
                    if ($response.StatusCode -eq 200) {
                        Write-LogMessage "Health check passed for Container App '$($app.Name)'" -Level Success
                    }
                    else {
                        Write-LogMessage "Health check failed for Container App '$($app.Name)': Status $($response.StatusCode)" -Level Warning
                        $healthChecksPassed = $false
                    }
                }
                catch {
                    Write-LogMessage "Health check failed for Container App '$($app.Name)': $_" -Level Warning
                    $healthChecksPassed = $false
                }
            }
        }
        
        return $healthChecksPassed
    }
    catch {
        Write-LogMessage "Health checks encountered errors: $_" -Level Error
        return $false
    }
}

# Function to load and validate resource state
function Test-ResourceState {
    param([string]$ResourceGroupName)
    
    Write-LogMessage "Validating resource state..." -Level Info
    
    try {
        # Find the most recent state file
        $stateFiles = Get-ChildItem -Path "." -Filter "resource-state-$EnvironmentName-*.json" | 
                      Sort-Object LastWriteTime -Descending
        
        if ($stateFiles.Count -eq 0) {
            Write-LogMessage "No previous resource state file found" -Level Warning
            return $true
        }
        
        $latestStateFile = $stateFiles[0]
        Write-LogMessage "Loading resource state from $($latestStateFile.Name)" -Level Info
        
        $savedState = Get-Content $latestStateFile.FullName | ConvertFrom-Json
        
        # Get current resources
        $currentResources = Get-AzResource -ResourceGroupName $ResourceGroupName
        
        # Compare resource counts
        if ($savedState.Resources.Count -ne $currentResources.Count) {
            Write-LogMessage "Resource count mismatch. Expected: $($savedState.Resources.Count), Found: $($currentResources.Count)" -Level Warning
        }
        
        Write-LogMessage "Resource state validation completed" -Level Success
        return $true
    }
    catch {
        Write-LogMessage "Failed to validate resource state: $_" -Level Warning
        return $true  # Non-critical, continue
    }
}

# Function to send notification
function Send-StartupNotification {
    param(
        [string]$EnvironmentName,
        [string]$Status,
        [string]$Details,
        [bool]$HealthChecksPassed
    )
    
    Write-LogMessage "Sending startup notification..." -Level Info
    
    try {
        # If Teams webhook URL is configured
        if ($env:TEAMS_WEBHOOK_URL) {
            $themeColor = if ($Status -eq "Success" -and $HealthChecksPassed) { "00FF00" } 
                         elseif ($Status -eq "Success") { "FFA500" }  # Orange for partial success
                         else { "FF0000" }
            
            $message = @{
                "@type" = "MessageCard"
                "@context" = "http://schema.org/extensions"
                "summary" = "Environment Startup Notification"
                "themeColor" = $themeColor
                "title" = "Environment Startup: $EnvironmentName"
                "sections" = @(
                    @{
                        "activityTitle" = "Startup Status"
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
                                "name" = "Health Checks"
                                "value" = if ($HealthChecksPassed) { "Passed" } else { "Failed" }
                            },
                            @{
                                "name" = "Details"
                                "value" = $Details
                            }
                        )
                    }
                )
                "potentialAction" = @(
                    @{
                        "@type" = "OpenUri"
                        "name" = "View Azure Portal"
                        "targets" = @(
                            @{
                                "os" = "default"
                                "uri" = "https://portal.azure.com/#@/resource/subscriptions/$((Get-AzContext).Subscription.Id)/resourceGroups/$ResourceGroupName/overview"
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
    Write-LogMessage "Starting environment startup process" -Level Info
    Write-LogMessage "Environment: $EnvironmentName" -Level Info
    Write-LogMessage "Resource Group: $ResourceGroupName" -Level Info
    Write-LogMessage "========================================" -Level Info
    
    # Verify Azure connection
    if (-not (Test-AzureConnection)) {
        throw "Azure connection required. Please run Connect-AzAccount"
    }
    
    try {
        # Validate resource state
        Test-ResourceState -ResourceGroupName $ResourceGroupName
        
        # Execute startup in order of dependencies
        
        # 1. Start PostgreSQL servers first (critical dependency)
        Start-PostgreSQLServers -ResourceGroupName $ResourceGroupName
        
        # 2. Start compute resources
        Start-ComputeResources -ResourceGroupName $ResourceGroupName
        
        # 3. Start App Services
        Start-AppServices -ResourceGroupName $ResourceGroupName
        
        # 4. Finally scale up Container Apps
        Start-ContainerApps -ResourceGroupName $ResourceGroupName
        
        # 5. Perform health checks
        $healthChecksPassed = Test-ServiceHealth -ResourceGroupName $ResourceGroupName
        
        # Prepare status message
        $status = if ($healthChecksPassed) { "Success" } else { "Success with warnings" }
        $details = "All resources started. Health checks: $(if ($healthChecksPassed) { 'Passed' } else { 'Some services may need attention' })"
        
        Write-LogMessage $details -Level $(if ($healthChecksPassed) { "Success" } else { "Warning" })
        
        # Send notification
        Send-StartupNotification `
            -EnvironmentName $EnvironmentName `
            -Status $status `
            -Details $details `
            -HealthChecksPassed $healthChecksPassed
            
        Write-LogMessage "========================================" -Level Info
        Write-LogMessage "Environment startup completed" -Level $(if ($healthChecksPassed) { "Success" } else { "Warning" })
        Write-LogMessage "Log file: $LogFile" -Level Info
        Write-LogMessage "========================================" -Level Info
        
        # Return success code based on health checks
        if (-not $healthChecksPassed) {
            exit 1  # Non-zero exit code for partial success
        }
    }
    catch {
        $errorDetails = "Startup failed: $_"
        Write-LogMessage $errorDetails -Level Error
        
        # Send failure notification
        Send-StartupNotification `
            -EnvironmentName $EnvironmentName `
            -Status "Failed" `
            -Details $errorDetails `
            -HealthChecksPassed $false
            
        throw
    }
}

# Execute main function
Main