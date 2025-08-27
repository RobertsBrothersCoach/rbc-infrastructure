# Infrastructure Deployment Strategy

## Current Situation
We have a GitHub Actions workflow (`infrastructure-deployment.yml`) that can handle deployments, but we need to decide on the best approach for our team.

## Option 1: GitHub Actions Automated Deployment

### How It Works
```yaml
Trigger: Push to main → Validate → Deploy to Dev → Manual approval → Deploy to Staging/Prod
```

### Pros ✅
- **Fully automated** - No manual intervention for dev
- **Consistent deployments** - Same process every time
- **Audit trail** - Every deployment is logged in GitHub
- **Version controlled** - All changes tracked
- **Rollback capability** - Easy to revert to previous deployment
- **Team collaboration** - PR reviews before deployment
- **Secrets management** - GitHub Secrets secure storage
- **Environment protection** - Required approvals for prod

### Cons ❌
- **Requires GitHub Secrets setup first** 
- **Initial complexity** - Need to configure workflows
- **Debugging harder** - Logs are in GitHub, not local
- **Dependency on GitHub** - If GitHub is down, can't deploy
- **Learning curve** - Team needs to understand GitHub Actions

### When to Use
- Team is comfortable with GitOps
- Want consistent, repeatable deployments
- Need audit trails and compliance
- Multiple developers working on infrastructure

## Option 2: Manual Local Deployment

### How It Works
```powershell
Local machine → Azure CLI → Run bicep/deploy.ps1 → Deploy to Azure
```

### Pros ✅
- **Quick to start** - Can deploy immediately
- **Direct control** - See results in real-time
- **Easy debugging** - Errors visible immediately
- **No GitHub setup needed** - Just Azure CLI
- **Flexibility** - Can make quick changes
- **Learning friendly** - Good for understanding the process

### Cons ❌
- **No audit trail** - Who deployed what when?
- **Inconsistent** - Different developers might deploy differently
- **Security risk** - Credentials on local machines
- **No approval process** - Anyone can deploy to prod
- **Manual process** - Prone to human error
- **No automatic rollback** - Manual intervention needed

### When to Use
- Initial setup and testing
- Emergency fixes
- Small team or single developer
- Learning and experimentation

## Option 3: Hybrid Approach (RECOMMENDED) 🌟

### Phase 1: Initial Setup (Now)
1. **Manual deployment for dev environment first**
   - Quick to start Sprint 1
   - Learn the process
   - Validate everything works

2. **Set up GitHub Secrets while dev is running**
   - AZURE_CREDENTIALS_DEV
   - AZURE_SUBSCRIPTION_ID
   - PostgreSQL passwords

3. **Test GitHub Actions with dev**
   - Run workflow manually
   - Verify it works

### Phase 2: Production Ready (Sprint 2)
1. **GitHub Actions for all environments**
   - Dev: Auto-deploy on push to main
   - Staging: Manual trigger with approval
   - Prod: Manual trigger with 2 approvals

2. **Keep manual scripts as backup**
   - Emergency deployments
   - Local testing
   - Disaster recovery

## Recommended Implementation Plan

### Step 1: Manual First Deployment (Today)
```powershell
# Deploy dev environment manually to get started
cd bicep
.\deploy.ps1 -Environment dev -Location eastus2
```

### Step 2: Configure GitHub Secrets (While Dev Deploys)
```bash
# Add service principal to GitHub
gh secret set AZURE_CREDENTIALS_DEV --body '{
  "clientId": "e4e45f45-cdae-4b9d-b163-e2581e02e096",
  "clientSecret": "xD08Q~...",
  "subscriptionId": "026185ca-7fce-4ff3-9790-bc4ecdebc550",
  "tenantId": "2bf8eca0-5705-47f9-bad9-10a86ef58a19"
}'

# Add subscription ID
gh secret set AZURE_SUBSCRIPTION_ID --body "026185ca-7fce-4ff3-9790-bc4ecdebc550"

# Add PostgreSQL password
gh secret set POSTGRES_ADMIN_PASSWORD_DEV --body "GeneratedSecurePassword"
```

### Step 3: Update Workflow for Our Needs
- Update domain references
- Configure proper environments
- Add our specific validation steps

### Step 4: Test Workflow
```bash
# Trigger manual deployment
gh workflow run infrastructure-deployment.yml \
  -f environment=dev \
  -f action=plan
```

## Decision Matrix

| Criteria | GitHub Actions | Manual | Hybrid |
|----------|---------------|---------|---------|
| **Speed to Start** | ❌ Slow | ✅ Fast | ✅ Fast |
| **Long-term Maintenance** | ✅ Easy | ❌ Hard | ✅ Easy |
| **Security** | ✅ High | ⚠️ Medium | ✅ High |
| **Audit Trail** | ✅ Complete | ❌ None | ✅ Complete |
| **Team Scaling** | ✅ Excellent | ❌ Poor | ✅ Excellent |
| **Flexibility** | ⚠️ Medium | ✅ High | ✅ High |
| **Cost** | ✅ Free | ✅ Free | ✅ Free |

## My Recommendation 🎯

**Go with Option 3: Hybrid Approach**

1. **Right now**: Deploy manually to unblock Sprint 1
2. **This week**: Set up GitHub Actions for dev
3. **Next sprint**: Extend to staging/prod with approvals

This gives us:
- ✅ Quick start (deploy in next 15 minutes)
- ✅ Long-term automation 
- ✅ Security best practices
- ✅ Flexibility when needed
- ✅ Team can learn gradually

## Security Considerations

### For Manual Deployment
- Never commit credentials
- Use Azure CLI device login
- Rotate service principal keys regularly
- Use separate credentials per environment

### For GitHub Actions
- Use GitHub Secrets (never plain text)
- Enable environment protection rules
- Require PR reviews for infrastructure changes
- Use OIDC authentication (future improvement)
- Implement least privilege for service principals

## Cost Implications

Both approaches have same Azure costs, but consider:
- **GitHub Actions**: 2,000 free minutes/month (more than enough)
- **Manual**: Developer time for each deployment
- **Hybrid**: Best of both worlds

## Team Training Needed

### For Manual Deployment
- Azure CLI basics
- PowerShell scripting
- Bicep syntax understanding

### For GitHub Actions
- GitHub workflow syntax
- Secrets management
- PR and review process
- Troubleshooting failed workflows

## Next Steps

1. **Make decision** (Recommend Hybrid)
2. **If Manual First**:
   - Create parameters file
   - Run deployment script
   - Document any issues

3. **If GitHub Actions First**:
   - Set up all secrets
   - Update workflow file
   - Create PR with changes
   - Test with dev environment

## Questions to Answer

1. **Who will have deployment permissions?**
   - Suggest: All devs for dev, leads for staging, admins for prod

2. **What's our rollback strategy?**
   - Suggest: Git revert + rerun workflow

3. **How often will we deploy?**
   - Suggest: Dev (continuous), Staging (weekly), Prod (bi-weekly)

4. **Do we need a separate CI/CD for applications?**
   - Yes, this is just infrastructure

5. **Should we use GitHub environments feature?**
   - Yes, provides approval gates and secrets isolation