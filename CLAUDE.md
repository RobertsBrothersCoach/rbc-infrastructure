# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a hybrid Infrastructure as Code (IaC) and GitOps repository for RBC applications, combining Azure Bicep for infrastructure provisioning and ArgoCD/Kubernetes for application deployment.

## Key Architecture Components

### Infrastructure Layer (Bicep)
- **Main orchestration**: `bicep/main.bicep` deploys all infrastructure at subscription scope
- **Environment-specific deployments**: Environments are `dev`, `qa`, and `prod` with zone redundancy in production
- **Primary regions**: eastus2 (with zones), westcentralus (no zones), eastus (with zones)
- **Resource naming**: `RBCLeasingApp-{Environment}` pattern for resource groups

### GitOps Layer (ArgoCD/Kubernetes)
- **App-of-apps pattern**: Bootstrap via `kubernetes/argocd/applications/app-of-apps.yaml`
- **Environment namespaces**: `leasing-app-dev`, `leasing-app-staging`, `leasing-app-prod`
- **Kustomize overlays**: Base manifests in `apps/leasing-app/base/`, environment customizations in `overlays/{env}/`
- **Repository URL convention**: Use `RBC-Infrastructure` (capitalized) in all references

## Common Development Commands

### Infrastructure Deployment (Bicep)
```powershell
# Deploy infrastructure to specific environment
.\bicep\deploy.ps1 -Environment dev -Location eastus2 -BackupRegion westcentralus

# What-if deployment (preview changes)
.\bicep\deploy.ps1 -Environment dev -WhatIf

# Manual Azure CLI deployment
az deployment sub create --location eastus2 --template-file bicep/main.bicep --parameters environmentName=dev
```

### ArgoCD/GitOps Operations
```bash
# Install ArgoCD
kubectl create namespace argocd
kubectl apply -n argocd -f kubernetes/argocd/install/

# Bootstrap GitOps (deploys all applications)
cd kubernetes/scripts
./bootstrap-gitops.sh

# Update image tags (from CI/CD)
./update-image-tag.sh dev backend v1.2.3
./update-image-tag.sh staging frontend v2.0.1

# ArgoCD application management
argocd app list
argocd app sync leasing-app-prod
argocd app sync leasing-app-dev --prune
argocd app get leasing-app-prod --refresh
```

### Monitoring and Troubleshooting
```bash
# Check application status
kubectl get applications -n argocd

# ArgoCD server logs
kubectl logs -n argocd deployment/argocd-server

# Application controller logs
kubectl logs -n argocd deployment/argocd-application-controller

# Force sync with Git state
argocd app sync <app-name> --force
```

## Critical Configuration Points

### Image Updates in Kustomization
Image tags are managed in `kubernetes/apps/leasing-app/overlays/{env}/kustomization.yaml`:
- Backend: `your-acr.azurecr.io/leasing-app-backend:{tag}`
- Frontend: `your-acr.azurecr.io/leasing-app-frontend:{tag}`

### ArgoCD Repository URLs
All ArgoCD application manifests must reference: `https://github.com/your-org/RBC-Infrastructure`

### Environment-Specific Behaviors
- **Development**: Auto-sync enabled, latest image tags
- **Staging**: Auto-sync with manual approval, specific version tags
- **Production**: Manual sync only, stable release tags, zone-redundant infrastructure

### Security Requirements
- Secrets stored in Azure Key Vault, never in repository
- Use Secrets Store CSI Driver for Kubernetes secret management
- PostgreSQL passwords auto-rotate: 90 days (prod), 180 days (non-prod)

## Deployment Workflow

1. Application CI builds and pushes image to ACR
2. CI updates image tag in this repository via `update-image-tag.sh`
3. ArgoCD detects Git changes and syncs to cluster
4. Production requires manual sync approval

## Zone Redundancy Configuration

Production deployments in supported regions (eastus2, eastus) include:
- PostgreSQL: Zone-redundant HA across zones 1 & 2
- Redis: Premium tier across zones 1, 2, 3
- App Service: P1v3 with 3+ instances
- Container Apps: Zone-redundant environment

Non-production uses single-zone deployment for cost optimization.