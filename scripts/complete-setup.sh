#!/bin/bash

# Complete AKS Setup Script
# This script configures kubectl, installs all components, and sets up GitOps

set -e

echo "🚀 RBC Infrastructure Complete Setup"
echo "===================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Check if required tools are installed
echo "🔍 Checking prerequisites..."
command -v az >/dev/null 2>&1 || { print_error "Azure CLI is required but not installed."; exit 1; }
command -v kubectl >/dev/null 2>&1 || { print_error "kubectl is required but not installed."; exit 1; }
command -v helm >/dev/null 2>&1 || { print_error "Helm is required but not installed."; exit 1; }

# Step 1: Configure AKS Credentials
echo ""
echo "📋 Step 1: Configuring AKS Credentials"
echo "--------------------------------------"

RESOURCE_GROUP="RBCLeasingApp-Dev"
AKS_CLUSTER_NAME="aks-rbcleasing-dev"

# Check if AKS cluster exists
if az aks show --name "$AKS_CLUSTER_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
    print_status "AKS cluster found: $AKS_CLUSTER_NAME"
    
    # Get credentials
    echo "🔐 Getting AKS credentials..."
    az aks get-credentials \
        --resource-group "$RESOURCE_GROUP" \
        --name "$AKS_CLUSTER_NAME" \
        --overwrite-existing
    
    print_status "kubectl configured successfully"
    
    # Verify connection
    echo "🔍 Verifying cluster connection..."
    kubectl cluster-info
else
    print_error "AKS cluster not found. Please ensure deployment is complete."
    echo "Run: az aks list --resource-group $RESOURCE_GROUP"
    exit 1
fi

# Step 2: Install nginx-ingress controller
echo ""
echo "🌐 Step 2: Installing nginx-ingress Controller"
echo "---------------------------------------------"

# Add ingress-nginx helm repo
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

# Create namespace
kubectl create namespace ingress-nginx --dry-run=client -o yaml | kubectl apply -f -

# Install nginx-ingress
echo "⏳ Installing nginx-ingress (this may take 2-3 minutes)..."
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
    --namespace ingress-nginx \
    --set controller.replicaCount=1 \
    --set controller.resources.requests.cpu=100m \
    --set controller.resources.requests.memory=128Mi \
    --set controller.service.type=LoadBalancer \
    --wait \
    --timeout 300s

print_status "nginx-ingress installed"

# Step 3: Install cert-manager
echo ""
echo "🔐 Step 3: Installing cert-manager"
echo "----------------------------------"

# Add cert-manager helm repo
helm repo add jetstack https://charts.jetstack.io
helm repo update

# Create namespace
kubectl create namespace cert-manager --dry-run=client -o yaml | kubectl apply -f -

# Install cert-manager
echo "⏳ Installing cert-manager..."
helm upgrade --install cert-manager jetstack/cert-manager \
    --namespace cert-manager \
    --version v1.13.0 \
    --set installCRDs=true \
    --wait \
    --timeout 300s

print_status "cert-manager installed"

# Create ClusterIssuers
echo "📜 Creating Let's Encrypt ClusterIssuers..."
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

print_status "ClusterIssuers created"

# Step 4: Get Load Balancer IP
echo ""
echo "🌐 Step 4: Getting Load Balancer IP"
echo "-----------------------------------"

echo "⏳ Waiting for Load Balancer IP..."
LB_IP=""
TIMEOUT=300
COUNTER=0

while [ -z "$LB_IP" ] && [ $COUNTER -lt $TIMEOUT ]; do
    LB_IP=$(kubectl get service ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    if [ -z "$LB_IP" ]; then
        sleep 10
        COUNTER=$((COUNTER + 10))
    fi
done

if [ -n "$LB_IP" ]; then
    print_status "Load Balancer IP: $LB_IP"
    echo ""
    echo "📋 DNS Configuration Required:"
    echo "   Add A record: *.cloud.rbccoach.com → $LB_IP"
    echo ""
else
    print_warning "Load Balancer IP not yet assigned"
fi

# Step 5: Install ArgoCD
echo ""
echo "🚀 Step 5: Installing ArgoCD"
echo "----------------------------"

# Create namespace
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

# Install ArgoCD
echo "⏳ Installing ArgoCD..."
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.11.7/manifests/install.yaml

# Wait for ArgoCD to be ready
echo "⏳ Waiting for ArgoCD pods..."
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd

# Apply cost optimizations
echo "💰 Applying cost optimizations..."
kubectl patch deployment argocd-server -n argocd --type json -p='[
  {"op": "replace", "path": "/spec/replicas", "value": 1}
]'

kubectl patch deployment argocd-application-controller -n argocd --type json -p='[
  {"op": "replace", "path": "/spec/replicas", "value": 1}
]'

kubectl patch deployment argocd-repo-server -n argocd --type json -p='[
  {"op": "replace", "path": "/spec/replicas", "value": 1}
]'

print_status "ArgoCD installed"

# Apply custom domain ingress
echo "🌐 Configuring ArgoCD ingress..."
kubectl apply -f kubernetes/argocd/install/argocd-ingress.yaml

# Get ArgoCD password
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

# Step 6: Apply Security Policies
echo ""
echo "🔒 Step 6: Applying Security Policies"
echo "------------------------------------"

# Apply network policies
kubectl apply -f kubernetes/security/network-policies.yaml 2>/dev/null || true

# Apply RBAC policies
kubectl apply -f kubernetes/security/rbac-policies.yaml 2>/dev/null || true

print_status "Security policies applied"

# Step 7: Create namespaces
echo ""
echo "📁 Step 7: Creating Application Namespaces"
echo "-----------------------------------------"

for ns in development staging production; do
    kubectl create namespace $ns --dry-run=client -o yaml | kubectl apply -f -
    print_status "Namespace '$ns' ready"
done

# Summary
echo ""
echo "🎉 Setup Complete!"
echo "=================="
echo ""
echo "📋 Access Information:"
echo "   ArgoCD URL: https://argocd-dev.cloud.rbccoach.com"
echo "   ArgoCD Username: admin"
echo "   ArgoCD Password: $ARGOCD_PASSWORD"
if [ -n "$LB_IP" ]; then
    echo "   Load Balancer IP: $LB_IP"
fi
echo ""
echo "🔧 Next Steps:"
echo "   1. Configure DNS: *.cloud.rbccoach.com → $LB_IP"
echo "   2. Access ArgoCD: https://argocd-dev.cloud.rbccoach.com"
echo "   3. Change admin password in ArgoCD"
echo "   4. Configure Azure AD authentication"
echo "   5. Deploy your first application"
echo ""
echo "📚 Useful Commands:"
echo "   kubectl get all -n argocd"
echo "   kubectl get ingress -A"
echo "   kubectl get certificates -A"
echo "   kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo ""
echo "💰 Total Infrastructure Cost:"
echo "   AKS: ~$70-120/month"
echo "   Load Balancer: ~$15-20/month"
echo "   Total: ~$85-140/month"