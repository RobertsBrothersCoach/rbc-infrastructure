# Environment Shutdown Automation

This directory contains automation scripts and templates for implementing scheduled environment shutdown/startup to achieve significant cost savings.

## Overview

The automation system provides:
- Automated daily shutdown at 7 PM EST
- Automated startup at 7 AM EST (Monday-Friday)
- Manual override capabilities
- Cost tracking and reporting
- Teams notifications
- Web-based control interface

## Cost Savings

| Environment | Monthly Cost | With Automation | Savings |
|------------|--------------|-----------------|---------|
| Development | $1,400 | $60 | $1,340 (85%) |
| QA | $1,100 | $120 | $980 (80%) |
| **Total** | **$2,500** | **$180** | **$2,320 (93%)** |

## Components

### PowerShell Scripts (`/scripts`)

- **Shutdown-Environment.ps1**: Core shutdown logic for all Azure resources
- **Startup-Environment.ps1**: Startup logic with health checks
- **Manual-Override-Workflow.ps1**: Web interface for manual control
- **Track-EnvironmentCosts.ps1**: Cost tracking and reporting

### Azure Automation Runbooks (`/runbooks`)

- **ScheduledShutdown.ps1**: Runbook for automated daily shutdown
- **ScheduledStartup.ps1**: Runbook for weekday morning startup
- **ManualOverride.ps1**: Runbook for manual control with override

### ARM Templates (`/arm-templates`)

- **logic-app-orchestration.json**: Logic App for schedule orchestration

## Setup Instructions

### 1. Create Azure Automation Account

```bash
az automation account create \
  --name aa-tourbus-automation \
  --resource-group rg-tourbus-shared \
  --location eastus \
  --sku Basic
```

### 2. Enable Managed Identity

```bash
az automation account update \
  --name aa-tourbus-automation \
  --resource-group rg-tourbus-shared \
  --assign-identity
```

### 3. Assign Permissions

Grant the managed identity Contributor access to environment resource groups:

```bash
# Get the managed identity principal ID
IDENTITY_ID=$(az automation account show \
  --name aa-tourbus-automation \
  --resource-group rg-tourbus-shared \
  --query identity.principalId -o tsv)

# Assign permissions to Dev environment
az role assignment create \
  --assignee $IDENTITY_ID \
  --role Contributor \
  --scope /subscriptions/{subscription-id}/resourceGroups/rg-tourbus-dev

# Assign permissions to QA environment  
az role assignment create \
  --assignee $IDENTITY_ID \
  --role Contributor \
  --scope /subscriptions/{subscription-id}/resourceGroups/rg-tourbus-qa
```

### 4. Import PowerShell Modules

Import required modules in the Automation Account:
- Az.Accounts
- Az.Resources
- Az.ContainerInstance
- Az.WebApps
- Az.PostgreSql
- Az.CostManagement

### 5. Upload Runbooks

Upload the runbooks from `/runbooks` directory to the Automation Account.

### 6. Create Schedules

```powershell
# Daily shutdown at 7 PM EST
New-AzAutomationSchedule `
  -Name "DailyShutdown" `
  -StartTime "19:00:00" `
  -TimeZone "Eastern Standard Time" `
  -DayInterval 1 `
  -AutomationAccountName aa-tourbus-automation `
  -ResourceGroupName rg-tourbus-shared

# Weekday startup at 7 AM EST
New-AzAutomationSchedule `
  -Name "WeekdayStartup" `
  -StartTime "07:00:00" `
  -TimeZone "Eastern Standard Time" `
  -WeekInterval 1 `
  -DaysOfWeek Monday,Tuesday,Wednesday,Thursday,Friday `
  -AutomationAccountName aa-tourbus-automation `
  -ResourceGroupName rg-tourbus-shared
```

### 7. Link Runbooks to Schedules

```powershell
# Link shutdown runbook
Register-AzAutomationScheduledRunbook `
  -RunbookName "ScheduledShutdown" `
  -ScheduleName "DailyShutdown" `
  -Parameters @{
    EnvironmentName = "Development"
    ResourceGroupName = "rg-tourbus-dev"
  } `
  -AutomationAccountName aa-tourbus-automation `
  -ResourceGroupName rg-tourbus-shared

# Link startup runbook
Register-AzAutomationScheduledRunbook `
  -RunbookName "ScheduledStartup" `
  -ScheduleName "WeekdayStartup" `
  -Parameters @{
    EnvironmentName = "Development"
    ResourceGroupName = "rg-tourbus-dev"
  } `
  -AutomationAccountName aa-tourbus-automation `
  -ResourceGroupName rg-tourbus-shared
```

### 8. Deploy Logic App (Optional)

Deploy the Logic App for advanced orchestration:

```bash
az deployment group create \
  --resource-group rg-tourbus-shared \
  --template-file arm-templates/logic-app-orchestration.json \
  --parameters \
    environmentName=Development \
    resourceGroupName=rg-tourbus-dev \
    teamsWebhookUrl="<your-teams-webhook-url>"
```

### 9. Configure Notifications (Optional)

Set automation variables for Teams notifications:

```powershell
New-AzAutomationVariable `
  -Name "NotificationWebhookUrl" `
  -Value "<your-teams-webhook-url>" `
  -Encrypted $false `
  -AutomationAccountName aa-tourbus-automation `
  -ResourceGroupName rg-tourbus-shared
```

## Manual Control

### Using PowerShell

```powershell
# Shutdown environment manually
.\Shutdown-Environment.ps1 `
  -EnvironmentName Development `
  -ResourceGroupName rg-tourbus-dev `
  -Force

# Startup environment manually
.\Startup-Environment.ps1 `
  -EnvironmentName Development `
  -ResourceGroupName rg-tourbus-dev
```

### Using Web Interface

Start the web control interface:

```powershell
.\Manual-Override-Workflow.ps1 -Port 8080
```

Then navigate to `http://localhost:8080` to control environments via web UI.

### Using Azure Portal

1. Navigate to the Automation Account
2. Go to Runbooks > ManualOverride
3. Click "Start" and provide parameters:
   - Action: Shutdown or Startup
   - EnvironmentName: Development or QA
   - ResourceGroupName: rg-tourbus-dev or rg-tourbus-qa
   - OverrideSchedule: true/false

## Cost Tracking

Run the cost tracking script monthly:

```powershell
.\Track-EnvironmentCosts.ps1 `
  -StartDate (Get-Date).AddDays(-30) `
  -EndDate (Get-Date) `
  -OutputPath ./reports
```

This generates a markdown report with:
- Current costs per environment
- Actual savings achieved
- Projected annual savings
- Optimization recommendations

## Monitoring

### View Automation Job History

```bash
az automation job list \
  --automation-account-name aa-tourbus-automation \
  --resource-group rg-tourbus-shared \
  --output table
```

### Check Last Run Status

```powershell
Get-AzAutomationJob `
  -RunbookName "ScheduledShutdown" `
  -AutomationAccountName aa-tourbus-automation `
  -ResourceGroupName rg-tourbus-shared `
  -Top 1
```

### Alert Configuration

Configure alerts for automation failures:

```bash
az monitor metrics alert create \
  --name automation-failure-alert \
  --resource-group rg-tourbus-shared \
  --scopes /subscriptions/{subscription-id}/resourceGroups/rg-tourbus-shared/providers/Microsoft.Automation/automationAccounts/aa-tourbus-automation \
  --condition "count FailedJob > 0" \
  --window-size 5m \
  --evaluation-frequency 5m
```

## Troubleshooting

### Common Issues

1. **Runbook fails with authentication error**
   - Verify managed identity is enabled
   - Check role assignments are correct
   - Ensure subscription context is set

2. **Resources don't start properly**
   - Check PostgreSQL servers start first
   - Verify network connectivity
   - Review health check endpoints

3. **Schedule doesn't trigger**
   - Verify timezone settings
   - Check schedule is enabled
   - Review automation account diagnostics

4. **Cost tracking shows no data**
   - Ensure Cost Management APIs are enabled
   - Verify permissions for cost data access
   - Wait 24 hours for cost data to populate

### Manual Recovery

If automated startup fails:

```powershell
# Force startup with health check skip
.\Startup-Environment.ps1 `
  -EnvironmentName Development `
  -ResourceGroupName rg-tourbus-dev `
  -SkipHealthCheck
```

## Best Practices

1. **Test in non-production first**: Always test automation changes in development before applying to QA
2. **Monitor regularly**: Check automation job history weekly
3. **Update schedules for holidays**: Disable startup for company holidays to maximize savings
4. **Keep scripts updated**: Update scripts when adding new resource types
5. **Document overrides**: Log manual overrides in team wiki/documentation

## Support

For issues or questions:
1. Check runbook execution logs in Azure Portal
2. Review PowerShell script output logs
3. Contact DevOps team for assistance

## License

MIT License - See LICENSE file in repository root