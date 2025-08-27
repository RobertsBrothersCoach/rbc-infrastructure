# ArgoCD GitOps Agent

## Purpose
Expert agent for managing ArgoCD applications and GitOps workflows in the RBC-Infrastructure repository.

## Capabilities
- Bootstrap ArgoCD installations
- Sync applications across environments
- Update image tags in Kustomization files
- Troubleshoot out-of-sync applications
- Configure app-of-apps patterns
- Manage environment promotion workflows

## Key Commands

### ArgoCD Installation
```bash
# Create namespace and install ArgoCD
kubectl create namespace argocd
kubectl apply -n argocd -f kubernetes/argocd/install/

# Wait for ArgoCD to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s

# Get initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# Access UI via port-forward
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

### Bootstrap GitOps
```bash
cd kubernetes/scripts
./bootstrap-gitops.sh

# Or manually apply app-of-apps
kubectl apply -f kubernetes/argocd/applications/app-of-apps.yaml
```

### Application Management
```bash
# List all applications
argocd app list
kubectl get applications -n argocd

# Sync applications
argocd app sync leasing-app-prod
argocd app sync leasing-app-dev --prune
argocd app sync leasing-app-staging --force

# Refresh application state
argocd app get leasing-app-prod --refresh

# View application details
argocd app get leasing-app-prod
kubectl describe application leasing-app-prod -n argocd
```

### Image Tag Updates
```bash
# Update image tag using script
cd kubernetes/scripts
./update-image-tag.sh dev backend v1.2.3
./update-image-tag.sh staging frontend v2.0.1
./update-image-tag.sh prod backend v1.0.0

# Manual update in kustomization.yaml
# Edit: kubernetes/apps/leasing-app/overlays/{env}/kustomization.yaml
```

## File Structure Knowledge
- ArgoCD install: `kubernetes/argocd/install/`
- Applications: `kubernetes/argocd/applications/`
- App manifests: `kubernetes/apps/leasing-app/`
- Base configs: `kubernetes/apps/leasing-app/base/`
- Overlays: `kubernetes/apps/leasing-app/overlays/{env}/`
- Scripts: `kubernetes/scripts/`

## Application Configuration

### Environment Namespaces
- Development: `leasing-app-dev`
- Staging: `leasing-app-staging`
- Production: `leasing-app-prod`

### Sync Policies
- **Dev**: Auto-sync enabled, prune enabled
- **Staging**: Auto-sync with manual approval
- **Prod**: Manual sync only, no auto-sync

### Repository URLs
- Must use: `https://github.com/your-org/RBC-Infrastructure`
- Capitalization is important!

### App-of-Apps Pattern
- Parent app: `app-of-apps.yaml`
- Watches: `kubernetes/argocd/applications/`
- Auto-deploys all child applications

## Image Management

### Image Repository Pattern
- Backend: `your-acr.azurecr.io/leasing-app-backend:{tag}`
- Frontend: `your-acr.azurecr.io/leasing-app-frontend:{tag}`

### Tag Conventions
- Dev: `dev-latest` or commit SHA
- Staging: Semantic version (e.g., `v1.2.3`)
- Prod: Stable release tags (e.g., `v1.0.0`)

## Troubleshooting

### Out of Sync Issues
```bash
# Force sync with pruning
argocd app sync <app-name> --prune

# Hard refresh from Git
argocd app get <app-name> --hard-refresh

# Reset to Git state
argocd app sync <app-name> --force
```

### Check Logs
```bash
# ArgoCD server logs
kubectl logs -n argocd deployment/argocd-server

# Application controller logs
kubectl logs -n argocd deployment/argocd-application-controller

# Repo server logs
kubectl logs -n argocd deployment/argocd-repo-server
```

### Common Issues
1. **ImagePullBackOff**: Check ACR credentials and image existence
2. **OutOfSync**: Usually means manual changes in cluster
3. **Degraded Health**: Check pod logs and events
4. **Sync Failed**: Check RBAC and repository access

## CI/CD Integration

### Workflow
1. CI builds and pushes image to ACR
2. CI updates image tag in this repo
3. ArgoCD detects Git changes
4. Auto-sync (dev/staging) or manual sync (prod)

### GitHub Actions Integration
```yaml
- name: Update GitOps repository
  run: |
    git clone https://github.com/${{ github.repository_owner }}/RBC-Infrastructure
    cd RBC-Infrastructure
    ./scripts/update-image-tag.sh ${{ env.ENVIRONMENT }} backend ${{ env.VERSION }}
    git add .
    git commit -m "Update backend image to ${{ env.VERSION }}"
    git push
```

## Best Practices
1. Never edit resources directly in cluster
2. All changes through Git commits
3. Use structured commit messages for changes
4. Test in dev before staging/prod
5. Keep app-of-apps for centralized management
6. Monitor application health regularly
7. Use projects to separate environments
8. Configure resource limits and quotas