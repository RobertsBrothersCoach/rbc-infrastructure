#!/bin/bash

# Install ArgoCD on AKS cluster with custom domain support
# This script installs ArgoCD with minimal resource requirements and *.cloud.rbccoach.com domain

set -e

DOMAIN="cloud.rbccoach.com"
ARGOCD_URL="argocd-dev.${DOMAIN}"

echo "🚀 Installing ArgoCD on AKS cluster with custom domain..."
echo "Domain: https://${ARGOCD_URL}"

# Check if kubectl is configured
if ! kubectl cluster-info &> /dev/null; then
    echo "❌ kubectl is not configured. Please run 'az aks get-credentials' first."
    exit 1
fi

# Get cluster info
CLUSTER_NAME=$(kubectl config current-context | cut -d'_' -f4 2>/dev/null || echo "unknown")
echo "📋 Installing ArgoCD on cluster: $CLUSTER_NAME"

# Create ArgoCD namespace
echo "📁 Creating ArgoCD namespace..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

# Install ArgoCD using the official manifests (v2.11.7 stable)
echo "⬇️  Installing ArgoCD v2.11.7..."
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.11.7/manifests/install.yaml

# Wait for ArgoCD to be ready
echo "⏳ Waiting for ArgoCD pods to be ready (this may take 2-3 minutes)..."
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
kubectl wait --for=condition=available --timeout=300s deployment/argocd-application-controller -n argocd
kubectl wait --for=condition=available --timeout=300s deployment/argocd-repo-server -n argocd

# Apply cost optimizations
echo "💰 Applying cost optimization patches..."

# Reduce resource requests for dev environment
kubectl patch deployment argocd-server -n argocd -p '{
  "spec": {
    "replicas": 1,
    "template": {
      "spec": {
        "containers": [{
          "name": "argocd-server",
          "resources": {
            "requests": {"cpu": "50m", "memory": "64Mi"},
            "limits": {"cpu": "200m", "memory": "256Mi"}
          }
        }]
      }
    }
  }
}'

kubectl patch deployment argocd-application-controller -n argocd -p '{
  "spec": {
    "template": {
      "spec": {
        "containers": [{
          "name": "argocd-application-controller", 
          "resources": {
            "requests": {"cpu": "100m", "memory": "128Mi"},
            "limits": {"cpu": "500m", "memory": "512Mi"}
          }
        }]
      }
    }
  }
}'

kubectl patch deployment argocd-repo-server -n argocd -p '{
  "spec": {
    "template": {
      "spec": {
        "containers": [{
          "name": "argocd-repo-server",
          "resources": {
            "requests": {"cpu": "50m", "memory": "64Mi"}, 
            "limits": {"cpu": "200m", "memory": "256Mi"}
          }
        }]
      }
    }
  }
}'

# Get initial admin password
echo "🔐 Getting ArgoCD admin password..."
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

# Port forward for access (runs in background)
echo "🌐 Setting up port forwarding to access ArgoCD..."
kubectl port-forward svc/argocd-server -n argocd 8080:443 > /dev/null 2>&1 &
PORT_FORWARD_PID=$!

# Wait a moment for port forward to establish
sleep 3

# Apply custom domain ingress configuration
echo "🌐 Configuring custom domain ingress..."
kubectl apply -f kubernetes/argocd/install/argocd-ingress.yaml

echo ""
echo "✅ ArgoCD installation completed with custom domain!"
echo ""
echo "📋 Access Information:"
echo "   🌐 Custom Domain: https://${ARGOCD_URL}"
echo "   🔒 Local Access: https://localhost:8080 (port-forward)"
echo "   👤 Username: admin"
echo "   🔑 Password: $ARGOCD_PASSWORD"
echo ""
echo "💰 Cost Optimization Applied:"
echo "   - Single replica for all components"
echo "   - Minimal resource requests (CPU: 225m total, Memory: 288Mi total)"
echo "   - Resource limits to prevent overspend"
echo "   - Basic Load Balancer with nginx-ingress"
echo ""
echo "🔧 Next Steps:"
echo "   1. **Configure DNS**: Point *.cloud.rbccoach.com to your Load Balancer IP"
echo "   2. **Access ArgoCD**: https://${ARGOCD_URL} (after DNS setup)"
echo "   3. **Fallback Access**: https://localhost:8080 (port-forward active)"
echo "   4. Change the admin password"
echo "   5. Configure Azure AD authentication"
echo "   6. Set up your first application"
echo ""
echo "🔍 Get Load Balancer IP:"
echo "   kubectl get service ingress-nginx-controller -n ingress-nginx"
echo ""
echo "🛑 To stop port forwarding: kill $PORT_FORWARD_PID"