# Kubernetes Infrastructure as Code

This directory contains the complete Infrastructure as Code setup for our Kubernetes cluster using GitOps principles.

## Architecture

```
kubernetes/
├── infrastructure/           # Base infrastructure components
│   ├── namespaces.yaml      # All required namespaces
│   ├── nginx-ingress/       # Ingress controller setup
│   ├── cert-manager/        # SSL certificate management
│   ├── argocd/              # GitOps operator
│   └── post-install/        # Post-installation configurations
├── applications/            # Application deployments (managed by ArgoCD)
├── security/               # Security policies and RBAC
└── Makefile               # Automated deployment commands
```

## Prerequisites

- Azure AKS cluster deployed
- kubectl configured to access the cluster
- make (optional, for using Makefile commands)

## Quick Start

### Option 1: Using Make (Recommended)

```bash
# Complete infrastructure setup
make all

# Or step by step:
make install-infrastructure    # Deploy base components
make configure-post-install    # Apply configurations
make get-lb-ip                # Get Load Balancer IP
make get-argocd-password      # Get ArgoCD password
```

### Option 2: Using kubectl directly

```bash
# Install base infrastructure
kubectl apply -k kubernetes/infrastructure/

# Wait for deployments to be ready
kubectl wait --for=condition=available deployment/ingress-nginx-controller -n ingress-nginx --timeout=300s
kubectl wait --for=condition=available deployment/cert-manager -n cert-manager --timeout=300s
kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=300s

# Apply post-installation configurations
kubectl apply -k kubernetes/infrastructure/post-install/
```

## Components

### 1. NGINX Ingress Controller
- **Purpose**: Routes external traffic to services
- **Namespace**: `ingress-nginx`
- **Configuration**: Basic Load Balancer (cost-optimized)
- **Replicas**: 1 (dev environment)

### 2. cert-manager
- **Purpose**: Automated SSL certificate management
- **Namespace**: `cert-manager`
- **Issuers**: Let's Encrypt (staging and production)
- **Configuration**: Automatic certificate renewal

### 3. ArgoCD
- **Purpose**: GitOps continuous deployment
- **Namespace**: `argocd`
- **URL**: https://argocd-dev.cloud.rbccoach.com
- **Configuration**: Single replica for cost optimization

## DNS Configuration

After deployment, configure your DNS:

1. Get the Load Balancer IP:
   ```bash
   make get-lb-ip
   # or
   kubectl get service ingress-nginx-controller -n ingress-nginx
   ```

2. Add DNS A record:
   ```
   *.cloud.rbccoach.com → <LOAD_BALANCER_IP>
   ```

## Accessing ArgoCD

1. Get admin password:
   ```bash
   make get-argocd-password
   # or
   kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
   ```

2. Access UI: https://argocd-dev.cloud.rbccoach.com

3. Login with:
   - Username: `admin`
   - Password: (from step 1)

## Cost Optimizations

This setup includes several cost-saving measures:

- **Single replicas**: All components run with 1 replica in dev
- **Basic Load Balancer**: Using Azure Basic SKU
- **Resource limits**: Conservative CPU/memory requests
- **Auto-scaling**: Configured but disabled by default

## Security Features

- **RBAC**: Kubernetes role-based access control
- **Network Policies**: Zero-trust network segmentation
- **SSL/TLS**: Automatic HTTPS with Let's Encrypt
- **Pod Security**: Security contexts and policies

## Monitoring

Check deployment status:
```bash
# All infrastructure pods
kubectl get pods -A | grep -E 'ingress-nginx|cert-manager|argocd'

# Check ingress rules
kubectl get ingress -A

# Check certificates
kubectl get certificates -A
```

## Troubleshooting

### Pods not starting
```bash
# Check pod logs
kubectl logs -n <namespace> <pod-name>

# Describe pod for events
kubectl describe pod -n <namespace> <pod-name>
```

### Load Balancer IP not assigned
```bash
# Check service status
kubectl describe service ingress-nginx-controller -n ingress-nginx

# Check Azure subscription limits
az network public-ip list --resource-group MC_RBCLeasingApp-Dev_aks-rbcleasing-dev_eastus2
```

### Certificate issues
```bash
# Check cert-manager logs
kubectl logs -n cert-manager deployment/cert-manager

# Check certificate status
kubectl describe certificate -n <namespace> <cert-name>
```

## Cleanup

Remove all infrastructure:
```bash
make clean
# or
kubectl delete -k kubernetes/infrastructure/
kubectl delete namespace ingress-nginx cert-manager argocd
```

## Next Steps

1. Configure Azure AD authentication for ArgoCD
2. Create ArgoCD applications for your services
3. Set up monitoring with Prometheus/Grafana
4. Configure backup and disaster recovery

## Estimated Costs

- **AKS Cluster**: ~$70-120/month (1-3 nodes)
- **Load Balancer**: ~$15-20/month (Basic SKU)
- **Total**: ~$85-140/month for dev environment