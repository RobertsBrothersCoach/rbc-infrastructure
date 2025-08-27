#!/bin/bash

# ArgoCD Installation Script for AKS
# This script installs ArgoCD on an AKS cluster

set -e

echo "🚀 Installing ArgoCD on AKS cluster..."

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl is not installed. Please install kubectl first."
    exit 1
fi

# Check if connected to a cluster
if ! kubectl cluster-info &> /dev/null; then
    echo "❌ Not connected to a Kubernetes cluster. Please configure kubectl first."
    exit 1
fi

# Create namespace
echo "📦 Creating ArgoCD namespace..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

# Install ArgoCD
echo "⚙️ Installing ArgoCD..."
kubectl apply -n argocd -k ../argocd/install/

# Wait for ArgoCD to be ready
echo "⏳ Waiting for ArgoCD to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s

# Get initial admin password
echo "🔑 Getting initial admin password..."
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

echo "✅ ArgoCD installation complete!"
echo ""
echo "📋 Connection Details:"
echo "   Username: admin"
echo "   Password: $ARGOCD_PASSWORD"
echo ""
echo "🌐 To access ArgoCD UI, run:"
echo "   kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "   Then open https://localhost:8080"
echo ""
echo "🔒 IMPORTANT: Change the admin password after first login!"
echo "   argocd account update-password"