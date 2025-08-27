#!/bin/bash

# Setup custom domain *.cloud.rbccoach.com for AKS cluster
# This script installs nginx-ingress, cert-manager, and configures ArgoCD

set -e

DOMAIN="cloud.rbccoach.com"
ARGOCD_SUBDOMAIN="argocd-dev.${DOMAIN}"

echo "🌐 Setting up custom domain infrastructure for *.${DOMAIN}"
echo "=================================================="

# Check if kubectl is configured
if ! kubectl cluster-info &> /dev/null; then
    echo "❌ kubectl is not configured. Please run 'az aks get-credentials' first."
    exit 1
fi

# Get cluster info
CLUSTER_NAME=$(kubectl config current-context | cut -d'_' -f4 2>/dev/null || echo "unknown")
echo "📋 Configuring domain for cluster: $CLUSTER_NAME"

# 1. Install nginx-ingress controller
echo ""
echo "🔧 Step 1: Installing nginx-ingress controller..."
echo "------------------------------------------------"

# Add ingress-nginx helm repo
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

# Create namespace
kubectl create namespace ingress-nginx --dry-run=client -o yaml | kubectl apply -f -

# Install nginx-ingress controller with cost optimizations
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --set controller.replicaCount=1 \
  --set controller.resources.requests.cpu=100m \
  --set controller.resources.requests.memory=128Mi \
  --set controller.resources.limits.cpu=500m \
  --set controller.resources.limits.memory=512Mi \
  --set controller.service.type=LoadBalancer \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-sku"="basic" \
  --set defaultBackend.enabled=true \
  --set defaultBackend.replicaCount=1 \
  --set defaultBackend.resources.requests.cpu=10m \
  --set defaultBackend.resources.requests.memory=16Mi \
  --wait \
  --timeout 300s

echo "✅ nginx-ingress controller installed!"

# 2. Install cert-manager
echo ""
echo "🔐 Step 2: Installing cert-manager for SSL certificates..."
echo "--------------------------------------------------------"

# Add cert-manager helm repo
helm repo add jetstack https://charts.jetstack.io
helm repo update

# Create namespace
kubectl create namespace cert-manager --dry-run=client -o yaml | kubectl apply -f -

# Install cert-manager
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --version v1.13.0 \
  --set installCRDs=true \
  --set resources.requests.cpu=50m \
  --set resources.requests.memory=64Mi \
  --set resources.limits.cpu=200m \
  --set resources.limits.memory=256Mi \
  --set webhook.resources.requests.cpu=25m \
  --set webhook.resources.requests.memory=32Mi \
  --set webhook.resources.limits.cpu=100m \
  --set webhook.resources.limits.memory=128Mi \
  --wait \
  --timeout 300s

echo "✅ cert-manager installed!"

# 3. Create Let's Encrypt ClusterIssuers
echo ""
echo "📜 Step 3: Creating Let's Encrypt ClusterIssuers..."
echo "--------------------------------------------------"

# Wait for cert-manager to be ready
kubectl wait --for=condition=available --timeout=300s deployment/cert-manager -n cert-manager
kubectl wait --for=condition=available --timeout=300s deployment/cert-manager-webhook -n cert-manager

# Create ClusterIssuers
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: devops@rbccoach.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging
spec:
  acme:
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    email: devops@rbccoach.com
    privateKeySecretRef:
      name: letsencrypt-staging
    solvers:
    - http01:
        ingress:
          class: nginx
EOF

echo "✅ Let's Encrypt ClusterIssuers created!"

# 4. Get Load Balancer IP
echo ""
echo "🌐 Step 4: Getting Load Balancer IP for DNS configuration..."
echo "----------------------------------------------------------"

echo "⏳ Waiting for Load Balancer IP to be assigned..."
LB_IP=""
TIMEOUT=300
COUNTER=0

while [ -z "$LB_IP" ] && [ $COUNTER -lt $TIMEOUT ]; do
  LB_IP=$(kubectl get service ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
  if [ -z "$LB_IP" ]; then
    echo "⏳ Still waiting for Load Balancer IP... (${COUNTER}s/${TIMEOUT}s)"
    sleep 10
    COUNTER=$((COUNTER + 10))
  fi
done

if [ -z "$LB_IP" ]; then
  echo "⚠️  Load Balancer IP not yet assigned. Check manually:"
  echo "   kubectl get service ingress-nginx-controller -n ingress-nginx"
else
  echo "✅ Load Balancer IP: $LB_IP"
fi

# 5. Display next steps
echo ""
echo "🎉 Custom domain infrastructure setup complete!"
echo "=============================================="
echo ""
echo "📋 Next Steps:"
echo "1. **Configure DNS Records** (Required):"
echo "   Add these DNS A records to your domain provider:"
echo "   - *.cloud.rbccoach.com → $LB_IP"
echo "   - argocd-dev.cloud.rbccoach.com → $LB_IP"
echo ""
echo "2. **Install ArgoCD with custom domain:**"
echo "   ./scripts/install-argocd.sh"
echo ""
echo "3. **Access Services:**"
echo "   - ArgoCD UI: https://${ARGOCD_SUBDOMAIN}"
echo "   - Your apps: https://[app-name]-dev.${DOMAIN}"
echo ""
echo "💰 **Cost Optimization Applied:**"
echo "   - Single replica ingress controller"
echo "   - Basic Load Balancer (not Standard)"
echo "   - Minimal resource requests"
echo "   - Estimated additional cost: ~$15-25/month"
echo ""
echo "🔍 **Verify Installation:**"
echo "   kubectl get all -n ingress-nginx"
echo "   kubectl get clusterissuers"
echo "   kubectl get service ingress-nginx-controller -n ingress-nginx"
echo ""
if [ -z "$LB_IP" ]; then
  echo "⚠️  **Important**: Get the Load Balancer IP with:"
  echo "   kubectl get service ingress-nginx-controller -n ingress-nginx"
fi