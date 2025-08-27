<#
.SYNOPSIS
    Track and report environment costs and savings from shutdown automation
.DESCRIPTION
    Monitors Azure costs and calculates savings from automated shutdown/startup schedules
.PARAMETER StartDate
    Start date for cost analysis
.PARAMETER EndDate  
    End date for cost analysis
#>

param(
    [DateTime]$StartDate = (Get-Date).AddDays(-30),
    [DateTime]$EndDate = (Get-Date),
    [string]$ResourceGroupName = "rg-tourbus-*",
    [string]$OutputPath = "."
)

# Import Azure modules
Import-Module Az.Billing -ErrorAction Stop
Import-Module Az.CostManagement -ErrorAction Stop

function Get-EnvironmentCosts {
    param(
        [string]$ResourceGroupName,
        [DateTime]$StartDate,
        [DateTime]$EndDate
    )
    
    $query = @{
        type = "Usage"
        timeframe = "Custom"
        timePeriod = @{
            from = $StartDate.ToString("yyyy-MM-dd")
            to = $EndDate.ToString("yyyy-MM-dd")
        }
        dataset = @{
            granularity = "Daily"
            aggregation = @{
                totalCost = @{
                    name = "Cost"
                    function = "Sum"
                }
            }
            grouping = @(
                @{
                    type = "Dimension"
                    name = "ResourceGroup"
                }
            )
            filter = @{
                dimensions = @{
                    name = "ResourceGroup"
                    operator = "In"
                    values = @($ResourceGroupName)
                }
            }
        }
    }
    
    $result = Invoke-AzCostManagementQuery -Scope "/subscriptions/$((Get-AzContext).Subscription.Id)" -Query $query
    return $result
}

function Calculate-Savings {
    param(
        [array]$CostData,
        [int]$ShutdownHours = 12
    )
    
    $totalCost = ($CostData | Measure-Object -Property Cost -Sum).Sum
    $potentialSavings = $totalCost * ($ShutdownHours / 24)
    
    return @{
        TotalCost = $totalCost
        PotentialSavings = $potentialSavings
        ActualSavingsPercent = [math]::Round(($potentialSavings / $totalCost) * 100, 2)
    }
}

function Generate-CostReport {
    param(
        [hashtable]$DevCosts,
        [hashtable]$QACosts,
        [string]$OutputPath
    )
    
    $report = @"
# Environment Cost Tracking Report
Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")

## Development Environment
- Total Monthly Cost: `$$([math]::Round($DevCosts.TotalCost, 2))
- Potential Savings: `$$([math]::Round($DevCosts.PotentialSavings, 2))
- Savings Percentage: $($DevCosts.ActualSavingsPercent)%

## QA Environment  
- Total Monthly Cost: `$$([math]::Round($QACosts.TotalCost, 2))
- Potential Savings: `$$([math]::Round($QACosts.PotentialSavings, 2))
- Savings Percentage: $($QACosts.ActualSavingsPercent)%

## Total Savings
- Combined Monthly Savings: `$$([math]::Round($DevCosts.PotentialSavings + $QACosts.PotentialSavings, 2))
- Annual Savings Projection: `$$([math]::Round(($DevCosts.PotentialSavings + $QACosts.PotentialSavings) * 12, 2))

## Recommendations
- Maintain consistent shutdown schedules
- Consider expanding automation to other environments
- Review resource sizing for additional optimization opportunities
"@
    
    $reportPath = Join-Path $OutputPath "cost-report-$(Get-Date -Format 'yyyyMMdd').md"
    $report | Out-File $reportPath
    
    Write-Host "Cost report generated: $reportPath" -ForegroundColor Green
    return $reportPath
}

# Main execution
try {
    Write-Host "Fetching cost data..." -ForegroundColor Cyan
    
    # Get costs for each environment
    $devCosts = Get-EnvironmentCosts -ResourceGroupName "rg-tourbus-dev" -StartDate $StartDate -EndDate $EndDate
    $qaCosts = Get-EnvironmentCosts -ResourceGroupName "rg-tourbus-qa" -StartDate $StartDate -EndDate $EndDate
    
    # Calculate savings
    $devSavings = Calculate-Savings -CostData $devCosts -ShutdownHours 12
    $qaSavings = Calculate-Savings -CostData $qaCosts -ShutdownHours 12
    
    # Generate report
    $reportPath = Generate-CostReport -DevCosts $devSavings -QACosts $qaSavings -OutputPath $OutputPath
    
    # Display summary
    Write-Host "`nCost Tracking Summary:" -ForegroundColor Green
    Write-Host "Development Environment Savings: `$$([math]::Round($devSavings.PotentialSavings, 2))/month" -ForegroundColor Yellow
    Write-Host "QA Environment Savings: `$$([math]::Round($qaSavings.PotentialSavings, 2))/month" -ForegroundColor Yellow
    Write-Host "Total Monthly Savings: `$$([math]::Round($devSavings.PotentialSavings + $qaSavings.PotentialSavings, 2))" -ForegroundColor Green
}
catch {
    Write-Error "Failed to track costs: $_"
    throw
}