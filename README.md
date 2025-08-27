# RBC Infrastructure Repository

This repository contains both Infrastructure as Code (IaC) and GitOps configurations for RBC applications.

## Repository Structure

```
rbc-infrastructure/
├── bicep/                     # Infrastructure as Code
│   ├── modules/              # Reusable Bicep modules
│   │   ├── aks/             # AKS cluster configuration
│   │   ├── acr/             # Container registry
│   │   ├── postgresql/      # Database setup
│   │   ├── keyvault/        # Secrets management
│   │   └── networking/      # VNets, subnets, etc.
│   └── environments/         # Environment-specific configs
│       ├── dev/
│       ├── staging/
│       └── prod/
├── kubernetes/               # GitOps manifests
│   ├── argocd/              # ArgoCD installation and configuration
│   │   ├── install/         # ArgoCD installation manifests
│   │   └── applications/    # ArgoCD Application definitions
│   ├── apps/                # Application manifests
│   │   └── leasing-app/     # RBC Leasing Application
│   │       ├── base/        # Base Kubernetes manifests
│   │       └── overlays/    # Environment-specific configurations
│   ├── clusters/            # Cluster-specific configurations
│   ├── scripts/             # Utility scripts
│   └── docs/                # Kubernetes documentation
└── .github/                  # CI/CD workflows
    └── workflows/
```

## Prerequisites

- Azure CLI configured with appropriate subscription
- kubectl configured to access your AKS cluster(s)
- ArgoCD CLI (optional but recommended)
- Helm 3.x

## Quick Start

### 1. Install ArgoCD on AKS

```bash
# Create namespace
kubectl create namespace argocd

# Install ArgoCD
kubectl apply -n argocd -f kubernetes/argocd/install/

# Wait for ArgoCD to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s
```

### 2. Access ArgoCD UI

```bash
# Get initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# Port forward to access UI (or use ingress)
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Access at https://localhost:8080
# Username: admin
# Password: (from above command)
```

### 3. Bootstrap GitOps

```bash
# Apply the app-of-apps pattern
kubectl apply -f kubernetes/argocd/applications/app-of-apps.yaml

# This will automatically deploy all applications defined in this repository
```

## Environment Management

### Development
- **Namespace**: `leasing-app-dev`
- **Auto-sync**: Enabled
- **Image tags**: Latest from main branch

### Staging
- **Namespace**: `leasing-app-staging`
- **Auto-sync**: Enabled with manual approval
- **Image tags**: Specific version tags

### Production
- **Namespace**: `leasing-app-prod`
- **Auto-sync**: Disabled (manual sync required)
- **Image tags**: Stable release tags

## Application Deployment

Applications are deployed using Kustomize overlays:

1. **Base manifests** define the common configuration
2. **Overlays** customize for each environment
3. **ArgoCD** monitors and syncs changes automatically

### Adding a New Application

1. Create application manifests in `apps/<app-name>/`
2. Add ArgoCD Application definition in `argocd/applications/`
3. Commit and push changes
4. ArgoCD will automatically detect and deploy

## Security Considerations

- **Never commit secrets** to this repository
- Use Azure Key Vault with Secrets Store CSI Driver
- Configure RBAC for ArgoCD access
- Enable Azure AD integration for SSO
- Use private endpoints for ACR access

## Monitoring

ArgoCD provides:
- Application health status
- Sync status and history
- Resource tree visualization
- Drift detection
- Automated rollback on failures

## Useful Commands

```bash
# Check ArgoCD application status
argocd app list

# Sync an application manually
argocd app sync leasing-app-prod

# View application details
argocd app get leasing-app-prod

# Check application health
kubectl get applications -n argocd

# View ArgoCD logs
kubectl logs -n argocd deployment/argocd-server
```

## CI/CD Integration

Your application CI/CD pipeline should:
1. Build and test code
2. Build and push Docker image to ACR
3. Update image tag in this repository (via PR or direct commit)
4. ArgoCD detects change and deploys

## Troubleshooting

### ArgoCD Out of Sync
```bash
argocd app sync <app-name> --prune
```

### Force Refresh
```bash
argocd app get <app-name> --refresh
```

### Reset to Git State
```bash
argocd app sync <app-name> --force
```

## Contributing

1. Create feature branch
2. Make changes
3. Test in dev environment first
4. Create PR for review
5. Merge to main after approval

## License

MIT License - See LICENSE file for details