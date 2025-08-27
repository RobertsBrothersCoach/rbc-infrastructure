# Azure Resource Naming Standards and Cost Optimization

## Resource Naming Convention

### Standard Pattern
`{resourceType}-{application}-{environment}`

### Current Naming Standards

| Resource Type | Naming Pattern | Example (Dev) | Example (Prod) |
|--------------|---------------|---------------|----------------|
| **Resource Group** | `RBCLeasingApp-{Env}` | `RBCLeasingApp-Dev` | `RBCLeasingApp-Prod` |
| **AKS Cluster** | `aks-rbc-{env}` | `aks-rbc-dev` | `aks-rbc-prod` |
| **Container Registry** | `acrrbc{env}` | `acrrbcdev` | `acrrbcprod` |
| **Key Vault** | `kv-rbc-{env}` | `kv-rbc-dev` | `kv-rbc-prod` |
| **PostgreSQL** | `psql-rbcleasing-{env}` | `psql-rbcleasing-dev` | `psql-rbcleasing-prod` |
| **Redis Cache** | `redis-rbcleasing-{env}` | `redis-rbcleasing-dev` | `redis-rbcleasing-prod` |
| **App Service** | `app-rbc-{env}` | `app-rbc-dev` | `app-rbc-prod` |
| **Storage Account** | `strbc{env}` | `strbcdev` | `strbcprod` |
| **Log Analytics** | `log-rbc-{env}` | `log-rbc-dev` | `log-rbc-prod` |
| **App Insights** | `appi-rbc-{env}` | `appi-rbc-dev` | `appi-rbc-prod` |
| **Network Security Group** | `nsg-rbc-{env}` | `nsg-rbc-dev` | `nsg-rbc-prod` |
| **Virtual Network** | `vnet-rbc-{env}` | `vnet-rbc-dev` | `vnet-rbc-prod` |
| **Automation Account** | `aa-rbc-{env}` | `aa-rbc-dev` | `aa-rbc-prod` |

### Kubernetes Namespaces
- Development: `leasing-app-dev`
- Staging: `leasing-app-staging`  
- Production: `leasing-app-prod`

## Cost Optimization Strategy

### Auto-Shutdown Schedule

| Environment | Auto-Shutdown | Schedule | Est. Monthly Savings |
|------------|--------------|----------|---------------------|
| **Development** | ✅ Enabled | 7 PM - 7 AM weekdays, All weekend | ~70% cost reduction |
| **Staging** | ✅ Enabled | 10 PM - 6 AM daily | ~35% cost reduction |
| **Production** | ❌ Disabled | Always On | N/A |

### Resources That Will Be Shut Down

#### Development Environment (7 PM - 7 AM + Weekends)
- **AKS Cluster**: Stopped (saves ~$150/month)
- **App Services**: Stopped (saves ~$50/month)
- **Container Apps**: Scaled to 0 replicas
- **PostgreSQL**: Stopped (saves ~$80/month)
- **Redis Cache**: Cannot be stopped (remains running)

#### Resources That Remain Running
- **Key Vault**: Always on (minimal cost)
- **Storage Accounts**: Always on (pay per usage)
- **Container Registry**: Always on (minimal cost)
- **Monitoring**: Always on (required for alerts)

### Estimated Cost Savings

| Environment | Without Auto-Shutdown | With Auto-Shutdown | Monthly Savings |
|------------|----------------------|-------------------|-----------------|
| Development | ~$800/month | ~$240/month | **$560 (70%)** |
| Staging | ~$1,200/month | ~$780/month | **$420 (35%)** |
| Production | ~$3,500/month | N/A | N/A |

**Total Monthly Savings: ~$980**

## Implementation Details

### 1. Auto-Shutdown Configuration (Already in Bicep)

The auto-shutdown is already configured in `bicep/main.bicep`:
```bicep
param enableAutoShutdown bool = environmentName != 'prod'
```

### 2. Manual Shutdown/Startup Commands

#### Stop Development Environment
```powershell
# Stop all resources in dev
az aks stop --resource-group RBCLeasingApp-Dev --name aks-rbc-dev
az postgres flexible-server stop --resource-group RBCLeasingApp-Dev --name psql-rbcleasing-dev
az webapp stop --resource-group RBCLeasingApp-Dev --name app-rbc-dev
```

#### Start Development Environment
```powershell
# Start all resources in dev
az aks start --resource-group RBCLeasingApp-Dev --name aks-rbc-dev
az postgres flexible-server start --resource-group RBCLeasingApp-Dev --name psql-rbcleasing-dev
az webapp start --resource-group RBCLeasingApp-Dev --name app-rbc-dev
```

### 3. Automated Shutdown Runbook

Located in `automation/runbooks/ScheduledShutdown.ps1`:
- Runs daily at configured times
- Stops/starts resources based on schedule
- Sends notifications before shutdown

### 4. Cost Alerts Configuration

Budget alerts are configured at:
- Dev: $1,000/month (alert at 80%)
- Staging: $2,000/month (alert at 80%)
- Production: $5,000/month (alert at 80%)

## Quick Commands for Cost Management

### Check Current Costs
```bash
# Get current month costs
az consumption usage list \
  --start-date $(date +%Y-%m-01) \
  --end-date $(date +%Y-%m-%d) \
  --query "[?contains(resourceGroup, 'RBC')].{Resource:instanceName, Cost:pretaxCost}" \
  --output table
```

### Emergency Shutdown (All Non-Prod)
```bash
# Emergency stop all dev resources
./automation/scripts/Shutdown-Environment.ps1 -ResourceGroupName RBCLeasingApp-Dev -Action Stop

# Emergency stop all staging resources  
./automation/scripts/Shutdown-Environment.ps1 -ResourceGroupName RBCLeasingApp-Staging -Action Stop
```

### Schedule Override (Keep Dev Running)
```bash
# Override shutdown for tonight (dev work needed)
./automation/scripts/Manual-Override-Workflow.ps1 -Environment dev -SkipShutdown -Hours 12
```

## Resource SKU Optimization

### Development Environment SKUs (Cost-Optimized)
- **AKS**: Standard_B2ms nodes (burstable, ~$35/month per node)
- **PostgreSQL**: Burstable B1ms (1 vCore, ~$25/month)
- **Redis**: Basic C0 (250MB, ~$15/month)
- **App Service**: B1 (Basic tier, ~$13/month)

### Production Environment SKUs (Performance-Optimized)
- **AKS**: Standard_D4s_v3 nodes (4 vCores, ~$140/month per node)
- **PostgreSQL**: General Purpose D4ds_v4 (4 vCores, ~$300/month)
- **Redis**: Premium P1 (6GB, zone redundant, ~$300/month)
- **App Service**: P1v3 (Premium, ~$150/month)

## Best Practices

1. **Always use dev environment** for testing and development
2. **Schedule work during business hours** to utilize auto-shutdown
3. **Use spot instances** for batch jobs when possible
4. **Clean up unused resources** weekly
5. **Monitor cost anomalies** via Azure Cost Management
6. **Tag all resources** properly for cost allocation
7. **Use reserved instances** for production (1-year commitment saves ~30%)

## Cost Monitoring Dashboard

Access the cost dashboard at:
- Azure Portal → Cost Management → Cost Analysis
- Filter by tag: `Application = RBCLeasingApp`
- Group by: Environment tag

## Questions to Consider

1. **Should we implement more aggressive shutdown?**
   - Current: Nights and weekends
   - Option: Shutdown during lunch (12-1 PM)
   - Potential additional savings: ~5%

2. **Should we use Azure Dev/Test subscription?**
   - Benefits: ~40% discount on Windows VMs
   - Consideration: Separate subscription management

3. **Should we implement auto-scaling more aggressively?**
   - Current: Fixed replica counts
   - Option: Scale to 0 during off-hours
   - Potential savings: Additional 10-15%