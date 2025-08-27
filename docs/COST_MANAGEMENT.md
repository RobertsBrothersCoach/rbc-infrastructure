# AKS Dev Environment Cost Management

## Current Status: ⏹️ STOPPED (Saving $70+/month)

## Quick Commands

### PowerShell (Windows)
```powershell
# Stop cluster (save costs)
.\scripts\aks-management.ps1 stop

# Start cluster (when needed)
.\scripts\aks-management.ps1 start

# Check status
.\scripts\aks-management.ps1 status

# View costs
.\scripts\aks-management.ps1 costs
```

### Bash (Linux/Mac)
```bash
# Stop cluster (save costs)
./scripts/aks-management.sh stop

# Start cluster (when needed)
./scripts/aks-management.sh start

# Check status
./scripts/aks-management.sh status

# View costs
./scripts/aks-management.sh costs
```

## Cost Breakdown

### When Running (Development Active)
| Component | Daily Cost | Monthly Cost |
|-----------|------------|--------------|
| Compute (1-3 B2s VMs) | $1.50-4.50 | $45-135 |
| Load Balancer (Standard) | $0.83 | $25 |
| Storage (30GB) | $0.14 | $4 |
| **Total** | **$2.40-3.60** | **$70-110** |

### When Stopped (Not in Use)
| Component | Daily Cost | Monthly Cost |
|-----------|------------|--------------|
| Compute | $0 | $0 |
| Load Balancer | $0 | $0 |
| Storage (preserved) | $0.14 | $4 |
| **Total** | **$0.14** | **$4** |

### Annual Savings by Stopping
- **Nights & Weekends**: Save ~$50/month ($600/year)
- **When Not Developing**: Save ~$100/month ($1,200/year)

## Automated Cost Management

### Option 1: Manual Daily Management
```powershell
# Morning - Start development
.\scripts\aks-management.ps1 start

# Evening - Stop for the night
.\scripts\aks-management.ps1 stop
```

### Option 2: Scheduled Automation (Windows)
Create a scheduled task to stop at 6 PM:
```powershell
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" `
    -Argument "-File C:\GitHub\RBC-Infrastructure\scripts\aks-management.ps1 stop"
$trigger = New-ScheduledTaskTrigger -Daily -At "6:00PM"
Register-ScheduledTask -Action $action -Trigger $trigger -TaskName "StopAKSDevCluster"
```

### Option 3: Azure Automation (Recommended)
Use Azure Automation to schedule start/stop:
1. Create Azure Automation Account
2. Add runbooks for start/stop
3. Schedule: Start at 9 AM, Stop at 6 PM weekdays only
4. Saves ~$60/month automatically

## When to Run vs Stop

### Keep Running When:
- Actively developing (daily work)
- Running tests or demos
- Team collaboration sessions
- CI/CD pipeline testing

### Stop When:
- End of workday
- Weekends (unless working)
- Holidays/vacations
- Not actively developing

## Starting After Shutdown

When you restart the cluster:

1. **Start the cluster** (3-5 minutes)
   ```powershell
   .\scripts\aks-management.ps1 start
   ```

2. **Services automatically restore**:
   - ✅ Kubernetes pods restart
   - ✅ nginx-ingress resumes
   - ✅ ArgoCD comes back online
   - ✅ External IP remains: 4.150.124.192

3. **Access services**:
   - ArgoCD: https://argocd-dev.cloud.rbccoach.com
   - Or locally: `kubectl port-forward svc/argocd-server -n argocd 8080:443`

## Cost Optimization Tips

1. **Use the stop/start scripts** - Easiest way to save
2. **Stop every evening** - Save $1.50-2.50 per night
3. **Stop on weekends** - Save $5-7 per weekend
4. **Use spot instances** - Future enhancement for 60-80% savings
5. **Right-size nodes** - B2s is good for dev, review if needed

## Monitoring Costs

### Azure Portal
1. Go to Cost Management + Billing
2. Filter by Resource Group: `RBCLeasingApp-Dev`
3. View daily/monthly trends

### CLI Check
```bash
# Current status and implied cost
.\scripts\aks-management.ps1 costs

# Azure cost analysis
az consumption usage list \
  --start-date 2025-08-01 \
  --end-date 2025-08-31 \
  --query "[?contains(resourceGroup, 'RBCLeasingApp-Dev')]" \
  --output table
```

## FAQ

**Q: Will I lose my data when stopping?**
A: No, all data is preserved. Only compute is deallocated.

**Q: How long to restart?**
A: 3-5 minutes for full cluster availability.

**Q: What about the External IP?**
A: The IP (4.150.124.192) is reserved and remains the same.

**Q: Can I schedule automatic start/stop?**
A: Yes, use Windows Task Scheduler or Azure Automation.

**Q: What if I forget to stop it?**
A: You'll be charged ~$2.50 extra per day. Set up automation!

## Emergency Stop

If costs are running high, immediately stop:
```bash
# Azure CLI direct command
az aks stop --resource-group RBCLeasingApp-Dev --name aks-rbcleasing-dev
```

---

**Remember**: Every hour stopped saves money! 💰

*Last Updated: 2025-08-27*