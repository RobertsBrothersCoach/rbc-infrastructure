# Cost Optimization Agent

## Purpose
Expert agent for optimizing Azure resource costs in the RBC-Infrastructure repository.

## Capabilities
- Configure auto-shutdown for non-production
- Analyze resource utilization
- Recommend right-sizing
- Set up budget alerts
- Implement tagging strategies
- Configure scaling policies

## Cost Management Strategy

### Environment Cost Targets
| Environment | Monthly Budget | Optimization Level | Auto-Shutdown |
|-------------|---------------|-------------------|---------------|
| Development | $1,000 | Aggressive | Yes (7 PM - 7 AM) |
| Staging | $2,000 | Moderate | Yes (10 PM - 6 AM) |
| Production | $5,000 | Conservative | No |

## Auto-Shutdown Configuration

### Automation Account Setup
```bicep
// bicep/modules/auto-shutdown.bicep
resource automationAccount 'Microsoft.Automation/automationAccounts@2022-08-08' = {
  name: 'aa-rbc-${environmentName}'
  location: location
  properties: {
    sku: {
      name: 'Basic'
    }
  }
}

resource shutdownRunbook 'Microsoft.Automation/automationAccounts/runbooks@2022-08-08' = {
  parent: automationAccount
  name: 'Shutdown-Environment'
  properties: {
    runbookType: 'PowerShell'
    publishContentLink: {
      uri: 'https://raw.githubusercontent.com/your-org/RBC-Infrastructure/main/automation/runbooks/ScheduledShutdown.ps1'
    }
  }
}

resource shutdownSchedule 'Microsoft.Automation/automationAccounts/schedules@2022-08-08' = if (environmentName != 'prod') {
  parent: automationAccount
  name: 'schedule-shutdown-${environmentName}'
  properties: {
    startTime: dateTimeAdd(utcNow(), 'PT1H')
    frequency: 'Day'
    interval: 1
    timeZone: 'Eastern Standard Time'
    advancedSchedule: {
      weekDays: ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday']
      hours: [19]  // 7 PM
    }
  }
}
```

### Shutdown Runbook Script
```powershell
# automation/runbooks/ScheduledShutdown.ps1
param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$true)]
    [ValidateSet('Stop', 'Start')]
    [string]$Action
)

# Authenticate using managed identity
Connect-AzAccount -Identity

# Get all resources in the resource group
$resources = Get-AzResource -ResourceGroupName $ResourceGroupName

foreach ($resource in $resources) {
    switch ($resource.ResourceType) {
        'Microsoft.Compute/virtualMachines' {
            if ($Action -eq 'Stop') {
                Stop-AzVM -ResourceGroupName $ResourceGroupName -Name $resource.Name -Force
            } else {
                Start-AzVM -ResourceGroupName $ResourceGroupName -Name $resource.Name
            }
        }
        'Microsoft.Web/sites' {
            if ($Action -eq 'Stop') {
                Stop-AzWebApp -ResourceGroupName $ResourceGroupName -Name $resource.Name
            } else {
                Start-AzWebApp -ResourceGroupName $ResourceGroupName -Name $resource.Name
            }
        }
        'Microsoft.ContainerService/managedClusters' {
            if ($Action -eq 'Stop') {
                Stop-AzAksCluster -ResourceGroupName $ResourceGroupName -Name $resource.Name
            } else {
                Start-AzAksCluster -ResourceGroupName $ResourceGroupName -Name $resource.Name
            }
        }
        'Microsoft.DBforPostgreSQL/flexibleServers' {
            if ($Action -eq 'Stop') {
                Stop-AzPostgreSqlFlexibleServer -ResourceGroupName $ResourceGroupName -Name $resource.Name
            } else {
                Start-AzPostgreSqlFlexibleServer -ResourceGroupName $ResourceGroupName -Name $resource.Name
            }
        }
    }
}

Write-Output "$Action completed for $ResourceGroupName at $(Get-Date)"
```

## Resource Right-Sizing

### SKU Recommendations
```powershell
# Analyze resource utilization and recommend right-sizing
function Get-RightSizingRecommendations {
    param(
        [string]$ResourceGroupName = "RBCLeasingApp-Dev"
    )
    
    $recommendations = @()
    
    # Check App Service Plans
    $appServicePlans = Get-AzAppServicePlan -ResourceGroupName $ResourceGroupName
    foreach ($plan in $appServicePlans) {
        $metrics = Get-AzMetric -ResourceId $plan.Id -TimeGrain 01:00:00 -StartTime (Get-Date).AddDays(-7)
        $avgCpu = ($metrics | Where-Object {$_.Name.Value -eq "CpuPercentage"}).Data.Average | Measure-Object -Average
        
        if ($avgCpu.Average -lt 20) {
            $recommendations += [PSCustomObject]@{
                Resource = $plan.Name
                Type = "App Service Plan"
                Current = $plan.Sku.Name
                Recommended = Get-SmallerSku $plan.Sku.Name
                EstimatedSavings = Calculate-SkuSavings $plan.Sku.Name (Get-SmallerSku $plan.Sku.Name)
                Reason = "Average CPU < 20%"
            }
        }
    }
    
    # Check AKS Node Pools
    $aksClusters = Get-AzAksCluster -ResourceGroupName $ResourceGroupName
    foreach ($cluster in $aksClusters) {
        foreach ($nodePool in $cluster.AgentPoolProfiles) {
            # Analyze node utilization
            $metrics = @{
                CPU = Get-NodePoolCpuUtilization $cluster.Name $nodePool.Name
                Memory = Get-NodePoolMemoryUtilization $cluster.Name $nodePool.Name
            }
            
            if ($metrics.CPU -lt 30 -and $metrics.Memory -lt 40) {
                $recommendations += [PSCustomObject]@{
                    Resource = "$($cluster.Name)/$($nodePool.Name)"
                    Type = "AKS Node Pool"
                    Current = "$($nodePool.VmSize) x $($nodePool.Count)"
                    Recommended = "$($nodePool.VmSize) x $([Math]::Max(1, $nodePool.Count - 1))"
                    EstimatedSavings = Calculate-NodeSavings $nodePool.VmSize
                    Reason = "Low CPU and Memory utilization"
                }
            }
        }
    }
    
    return $recommendations
}
```

### Development Environment Optimizations
```bicep
// Use B-series burstable VMs for dev
var vmSku = environmentName == 'dev' ? 'Standard_B2ms' : 
            environmentName == 'staging' ? 'Standard_D2s_v3' : 
            'Standard_D4s_v3'

// Use Basic tier services where possible in dev
var postgresSku = environmentName == 'dev' ? {
  name: 'Standard_B2ms'
  tier: 'Burstable'
} : environmentName == 'staging' ? {
  name: 'Standard_D2ds_v4'
  tier: 'GeneralPurpose'
} : {
  name: 'Standard_D4ds_v4'
  tier: 'GeneralPurpose'
}

// Use consumption plan for Functions in dev
var functionPlan = environmentName == 'dev' ? 'Y1' : 'EP1'
```

## Tagging Strategy

### Required Tags
```bicep
var mandatoryTags = {
  Environment: environmentName
  Application: 'RBCLeasingApp'
  CostCenter: costCenter
  Owner: owner
  Department: department
  Project: projectCode
  ManagedBy: 'Bicep'
  CreatedDate: utcNow('yyyy-MM-dd')
  AutoShutdown: environmentName != 'prod' ? 'true' : 'false'
  DataClassification: environmentName == 'prod' ? 'Confidential' : 'Internal'
}

// Apply tags to all resources
resource tagPolicy 'Microsoft.Authorization/policyAssignments@2022-06-01' = {
  name: 'require-tags-${environmentName}'
  properties: {
    policyDefinitionId: '/providers/Microsoft.Authorization/policyDefinitions/96670d01-0a4d-4649-9c89-2d3abc0a5025'
    parameters: {
      tagName: {
        value: 'Environment'
      }
      tagValue: {
        value: environmentName
      }
    }
  }
}
```

### Cost Allocation Tags
```powershell
# Apply cost allocation tags to existing resources
$resources = Get-AzResource -ResourceGroupName "RBCLeasingApp-Dev"

foreach ($resource in $resources) {
    $tags = $resource.Tags ?? @{}
    $tags["CostAllocation"] = "Development"
    $tags["BillingPeriod"] = "2024-Q1"
    $tags["ChargebackCode"] = "IT-DEV-001"
    
    Set-AzResource -ResourceId $resource.ResourceId -Tag $tags -Force
}
```

## Budget Configuration

### Azure Budgets
```bicep
resource budget 'Microsoft.Consumption/budgets@2021-10-01' = {
  name: 'budget-rbc-${environmentName}'
  properties: {
    category: 'Cost'
    amount: environmentName == 'prod' ? 5000 : environmentName == 'staging' ? 2000 : 1000
    timeGrain: 'Monthly'
    timePeriod: {
      startDate: '2024-01-01'
      endDate: '2024-12-31'
    }
    filter: {
      dimensions: {
        name: 'ResourceGroup'
        operator: 'In'
        values: [
          resourceGroup().name
        ]
      }
    }
    notifications: {
      Actual_GreaterThan_50_Percent: {
        enabled: true
        operator: 'GreaterThan'
        threshold: 50
        thresholdType: 'Actual'
        contactEmails: ['team@company.com']
      }
      Actual_GreaterThan_80_Percent: {
        enabled: true
        operator: 'GreaterThan'
        threshold: 80
        thresholdType: 'Actual'
        contactEmails: ['team@company.com', 'manager@company.com']
      }
      Forecast_GreaterThan_100_Percent: {
        enabled: true
        operator: 'GreaterThan'
        threshold: 100
        thresholdType: 'Forecasted'
        contactEmails: ['team@company.com', 'manager@company.com', 'finance@company.com']
      }
    }
  }
}
```

## Scaling Policies

### Horizontal Pod Autoscaler
```yaml
# kubernetes/apps/leasing-app/overlays/dev/hpa-cost-optimized.yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: leasing-app-backend-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: leasing-app-backend
  minReplicas: 1  # Minimum for dev
  maxReplicas: 3  # Limited max for cost control
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 80  # Higher threshold for dev
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 85
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
      - type: Percent
        value: 50  # Aggressive scale down
        periodSeconds: 60
    scaleUp:
      stabilizationWindowSeconds: 180  # Slower scale up
      policies:
      - type: Percent
        value: 25  # Conservative scale up
        periodSeconds: 180
```

### Azure App Service Autoscale
```bicep
resource autoScale 'Microsoft.Insights/autoscalesettings@2022-10-01' = if (environmentName != 'dev') {
  name: 'autoscale-app-${environmentName}'
  location: location
  properties: {
    targetResourceUri: appServicePlan.id
    enabled: true
    profiles: [
      {
        name: 'Cost-Optimized-Profile'
        capacity: {
          minimum: environmentName == 'prod' ? '2' : '1'
          maximum: environmentName == 'prod' ? '10' : '3'
          default: environmentName == 'prod' ? '3' : '1'
        }
        rules: [
          {
            metricTrigger: {
              metricName: 'CpuPercentage'
              metricResourceUri: appServicePlan.id
              timeGrain: 'PT1M'
              statistic: 'Average'
              timeWindow: 'PT10M'
              timeAggregation: 'Average'
              operator: 'GreaterThan'
              threshold: 75
            }
            scaleAction: {
              direction: 'Increase'
              type: 'ChangeCount'
              value: '1'
              cooldown: 'PT10M'
            }
          }
          {
            metricTrigger: {
              metricName: 'CpuPercentage'
              metricResourceUri: appServicePlan.id
              timeGrain: 'PT1M'
              statistic: 'Average'
              timeWindow: 'PT10M'
              timeAggregation: 'Average'
              operator: 'LessThan'
              threshold: 25
            }
            scaleAction: {
              direction: 'Decrease'
              type: 'ChangeCount'
              value: '1'
              cooldown: 'PT15M'  // Longer cooldown for cost optimization
            }
          }
        ]
      }
    ]
  }
}
```

## Reserved Instances & Savings Plans

### Reserved Instance Recommendations
```powershell
# Get RI recommendations
$recommendations = Get-AzConsumptionReservationRecommendation `
    -Scope "subscriptions/$subscriptionId" `
    -LookBackPeriod Last30Days

foreach ($rec in $recommendations) {
    Write-Output "Resource: $($rec.ResourceType)"
    Write-Output "Recommended Term: $($rec.RecommendedQuantityNormalized) x $($rec.Term)"
    Write-Output "Estimated Savings: $($rec.NetSavings)"
    Write-Output "ROI Period: $($rec.FirstUsageDate)"
}
```

## Cost Analysis Queries

### Monthly Cost Breakdown
```kusto
// Azure Cost Management query
ConsumptionData
| where TimeGenerated > ago(30d)
| summarize TotalCost = sum(Cost) by ResourceGroup, Service
| order by TotalCost desc
| project ResourceGroup, Service, TotalCost = round(TotalCost, 2)
```

### Unused Resources Detection
```powershell
# Find unused resources
function Find-UnusedResources {
    $unusedResources = @()
    
    # Unattached disks
    $disks = Get-AzDisk | Where-Object {$_.DiskState -eq 'Unattached'}
    $unusedResources += $disks | ForEach-Object {
        [PSCustomObject]@{
            Type = "Disk"
            Name = $_.Name
            Size = "$($_.DiskSizeGB) GB"
            MonthlyCost = [math]::Round($_.DiskSizeGB * 0.05, 2)
        }
    }
    
    # Unused Public IPs
    $publicIps = Get-AzPublicIpAddress | Where-Object {$null -eq $_.IpConfiguration}
    $unusedResources += $publicIps | ForEach-Object {
        [PSCustomObject]@{
            Type = "Public IP"
            Name = $_.Name
            Size = "N/A"
            MonthlyCost = 3.65
        }
    }
    
    # Stopped VMs still incurring storage costs
    $vms = Get-AzVM -Status | Where-Object {$_.PowerState -eq 'VM deallocated'}
    $unusedResources += $vms | ForEach-Object {
        [PSCustomObject]@{
            Type = "Deallocated VM"
            Name = $_.Name
            Size = $_.HardwareProfile.VmSize
            MonthlyCost = "Storage costs only"
        }
    }
    
    return $unusedResources
}
```

## Cost Optimization Checklist
- [ ] Auto-shutdown configured for non-production
- [ ] Reserved instances purchased for stable workloads
- [ ] Spot instances used for batch processing
- [ ] Unused resources identified and removed
- [ ] Right-sizing analysis completed monthly
- [ ] Tagging strategy implemented
- [ ] Budget alerts configured
- [ ] Cost anomaly detection enabled
- [ ] Dev/Test pricing applied where eligible
- [ ] Storage tiers optimized (hot/cool/archive)

## Best Practices
1. Review costs weekly, optimize monthly
2. Use Azure Advisor recommendations
3. Implement aggressive auto-shutdown for dev/test
4. Use spot instances for non-critical workloads
5. Purchase Reserved Instances for production
6. Optimize storage tiers based on access patterns
7. Delete unattached resources automatically
8. Use Azure Hybrid Benefit where applicable
9. Monitor and act on cost anomalies immediately
10. Educate team on cost-conscious development