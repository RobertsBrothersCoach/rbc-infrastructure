# ArgoCD Setup Guide for AKS

## Prerequisites

1. **Azure Resources**
   - AKS cluster deployed
   - Azure Container Registry (ACR)
   - Azure Key Vault (optional but recommended)
   - Azure AD tenant

2. **Tools**
   - Azure CLI
   - kubectl
   - ArgoCD CLI (optional)
   - Helm 3.x

3. **Access**
   - AKS cluster admin access
   - Azure AD admin for app registration
   - GitHub repository access

## Initial Setup

### 1. Connect to AKS Cluster

```bash
# Login to Azure
az login

# Get AKS credentials
az aks get-credentials --resource-group <rg-name> --name <cluster-name>

# Verify connection
kubectl cluster-info
```

### 2. Install ArgoCD

```bash
cd scripts
./install-argocd.sh
```

This will:
- Create the argocd namespace
- Install ArgoCD components
- Display the initial admin password

### 3. Configure Azure AD (Optional)

#### Create Azure AD App Registration

1. Go to Azure Portal > Azure Active Directory > App registrations
2. Click "New registration"
3. Name: "ArgoCD-AKS"
4. Redirect URI: `https://your-argocd-url/auth/callback`
5. Note the Application (client) ID and Tenant ID
6. Create a client secret under "Certificates & secrets"

#### Configure ArgoCD

```bash
export TENANT_ID=your-tenant-id
export CLIENT_ID=your-client-id
export CLIENT_SECRET=your-client-secret
./configure-azure-ad.sh
```

### 4. Configure Ingress

#### Install NGINX Ingress Controller

```bash
# Add Helm repo
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

# Install ingress controller
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --create-namespace \
  --namespace ingress-nginx \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path"=/healthz
```

#### Install cert-manager

```bash
# Install cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml

# Create ClusterIssuer for Let's Encrypt
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: your-email@example.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
EOF
```

### 5. Configure ACR Integration

```bash
# Attach ACR to AKS
az aks update \
  --name <cluster-name> \
  --resource-group <rg-name> \
  --attach-acr <acr-name>
```

### 6. Bootstrap GitOps

Update repository references in the manifests:

```bash
# Update all references to your repositories
find ../argocd -name "*.yaml" -exec sed -i 's|your-org|YOUR-GITHUB-ORG|g' {} \;
find ../apps -name "*.yaml" -exec sed -i 's|your-acr|YOUR-ACR-NAME|g' {} \;
find ../apps -name "*.yaml" -exec sed -i 's|yourdomain.com|YOUR-DOMAIN|g' {} \;
```

Deploy the bootstrap configuration:

```bash
./bootstrap-gitops.sh
```

## Deployment Workflow

### CI/CD Pipeline Integration

Your CI/CD pipeline should:

1. **Build and Test**
   ```yaml
   - Build application
   - Run tests
   - Build Docker image
   ```

2. **Push to ACR**
   ```yaml
   - Login to ACR
   - Tag image with version
   - Push to registry
   ```

3. **Update GitOps Repo**
   ```yaml
   - Clone infrastructure repo
   - Update image tag in kustomization.yaml
   - Commit and push changes
   ```

Example GitHub Actions workflow:

```yaml
- name: Update GitOps repository
  run: |
    git clone https://github.com/${{ github.repository_owner }}/RBC-Infrastructure
    cd RBC-Infrastructure
    ./scripts/update-image-tag.sh ${{ env.ENVIRONMENT }} backend ${{ env.VERSION }}
    git config user.name "GitHub Actions"
    git config user.email "actions@github.com"
    git add .
    git commit -m "Update backend image to ${{ env.VERSION }}"
    git push
```

## Secrets Management

### Using Azure Key Vault

1. **Install Secrets Store CSI Driver**
   ```bash
   helm repo add csi-secrets-store-provider-azure https://azure.github.io/secrets-store-csi-driver-provider-azure/charts
   helm install csi-secrets-store-provider-azure/csi-secrets-store-provider-azure \
     --generate-name --namespace kube-system
   ```

2. **Configure Managed Identity**
   ```bash
   # Enable managed identity on AKS
   az aks update -g <rg-name> -n <cluster-name> --enable-managed-identity
   
   # Get identity client ID
   IDENTITY_CLIENT_ID=$(az aks show -g <rg-name> -n <cluster-name> --query identityProfile.kubeletidentity.clientId -o tsv)
   
   # Grant Key Vault permissions
   az keyvault set-policy -n <keyvault-name> \
     --secret-permissions get list \
     --spn $IDENTITY_CLIENT_ID
   ```

3. **Update SecretProviderClass**
   Update the manifests with your Key Vault details

## Monitoring

### ArgoCD Metrics

```bash
# Enable metrics
kubectl patch configmap argocd-server-config -n argocd --type merge -p '{"data":{"application.instanceLabelKey":"argocd.argoproj.io/instance"}}'

# Access metrics
kubectl port-forward -n argocd svc/argocd-metrics 8082:8082
# Metrics available at http://localhost:8082/metrics
```

### Application Health

Monitor application health in ArgoCD UI or CLI:

```bash
# Check all applications
argocd app list

# Get specific app details
argocd app get leasing-app-prod

# Check sync status
argocd app sync-status leasing-app-prod
```

## Troubleshooting

### Common Issues

1. **Out of Sync Applications**
   ```bash
   argocd app sync <app-name> --prune
   ```

2. **Image Pull Errors**
   - Verify ACR integration
   - Check service account annotations
   - Verify image exists in registry

3. **Certificate Issues**
   - Check cert-manager logs
   - Verify DNS is pointing to cluster
   - Check ClusterIssuer status

4. **Permission Denied**
   - Verify RBAC configuration
   - Check service account permissions
   - Review Azure AD group memberships

### Debug Commands

```bash
# Check ArgoCD logs
kubectl logs -n argocd deployment/argocd-server

# Check application controller logs
kubectl logs -n argocd deployment/argocd-application-controller

# Describe application
kubectl describe application <app-name> -n argocd

# Force refresh
argocd app get <app-name> --refresh
```

## Security Best Practices

1. **Enable RBAC** - Use Azure AD groups for access control
2. **Use TLS** - Always use HTTPS with valid certificates
3. **Secure Secrets** - Use Azure Key Vault, never commit secrets
4. **Network Policies** - Implement network segmentation
5. **Pod Security** - Use Pod Security Standards
6. **Image Scanning** - Scan images in ACR before deployment
7. **Audit Logging** - Enable and monitor audit logs

## Next Steps

1. Configure monitoring with Prometheus/Grafana
2. Set up alerts for failed deployments
3. Implement progressive delivery with Flagger
4. Add more applications to the GitOps workflow
5. Configure multi-cluster deployments