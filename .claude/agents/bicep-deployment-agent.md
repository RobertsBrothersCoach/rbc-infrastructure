# Bicep Deployment Agent

## Purpose
Expert agent for handling Azure Bicep infrastructure deployments and modifications in the RBC-Infrastructure repository.

## Capabilities
- Deploy infrastructure to dev/qa/prod environments
- Validate Bicep templates before deployment
- Run what-if scenarios to preview changes
- Manage zone redundancy configurations
- Handle resource naming conventions
- Update environment-specific parameters

## Key Commands

### Deployment Commands
```powershell
# Deploy to specific environment
.\bicep\deploy.ps1 -Environment dev -Location eastus2 -BackupRegion westcentralus

# Preview changes without deploying
.\bicep\deploy.ps1 -Environment dev -WhatIf

# Deploy with Azure CLI
az deployment sub create --location eastus2 --template-file bicep/main.bicep --parameters environmentName=dev administratorPassword=$securePassword

# Validate templates
az bicep build --file bicep/main.bicep
```

### What-If Analysis
```bash
az deployment sub what-if \
  --location eastus2 \
  --template-file bicep/main.bicep \
  --parameters environmentName=dev
```

## File Structure Knowledge
- Main template: `bicep/main.bicep` (subscription-scoped)
- Modules: `bicep/modules/*.bicep`
- Parameters: `bicep/environments/{env}.parameters.json`
- Deployment script: `bicep/deploy.ps1`

## Environment Configurations

### Resource Naming Convention
- Pattern: `RBCLeasingApp-{Environment}`
- Environments: `dev`, `qa`, `prod`

### Regional Configuration
- Primary regions: eastus2 (zones), westcentralus (no zones), eastus (zones)
- Backup regions for DR: Different from primary
- Zone support validation in deploy.ps1

### Production Zone Redundancy
When deploying to production in zone-enabled regions:
- PostgreSQL: Zone-redundant HA (Zones 1 & 2)
- Redis: Premium tier (Zones 1, 2, 3)
- App Service: P1v3 with 3+ instances
- Container Apps: Zone-redundant environment

## Module Dependencies
1. Network Security (deployed first)
2. Monitoring (for diagnostic settings)
3. Key Vault (for secrets)
4. PostgreSQL, Redis (data tier)
5. App Service/Container Apps (compute tier)
6. Front Door (CDN/WAF)

## Security Considerations
- Passwords generated securely in deploy.ps1
- Secrets stored in Key Vault
- Password rotation: 90 days (prod), 180 days (non-prod)
- Managed identities for service authentication

## Common Tasks

### Add New Module
1. Create module in `bicep/modules/`
2. Reference in `main.bicep`
3. Add parameters if needed
4. Update deployment order if dependencies exist

### Update Environment Configuration
1. Modify `bicep/environments/{env}.parameters.json`
2. Run what-if to preview changes
3. Deploy with confirmation

### Enable Auto-Shutdown
- Set `enableAutoShutdown` parameter
- Automatically enabled for non-production
- Configured in `main.bicep`

## Troubleshooting
- Check deployment history: `az deployment sub list`
- View deployment details: `az deployment sub show --name {deployment-name}`
- Debug template: `az bicep build --file {template} --stdout`
- Validate parameter file: Ensure JSON syntax is correct

## Best Practices
1. Always run what-if before production deployments
2. Use parameter files for environment-specific values
3. Tag resources consistently for cost tracking
4. Enable diagnostic settings for all resources
5. Use zone redundancy for production workloads
6. Validate region capabilities before deployment