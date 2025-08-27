#!/bin/bash

# Bootstrap GitOps with ArgoCD
# This script sets up the initial GitOps configuration

set -e

echo "🚀 Bootstrapping GitOps with ArgoCD..."

# Check if ArgoCD is installed
if ! kubectl get namespace argocd &> /dev/null; then
    echo "❌ ArgoCD namespace not found. Please install ArgoCD first."
    echo "   Run: ./install-argocd.sh"
    exit 1
fi

# Get repository URL
read -p "Enter your infrastructure repository URL (e.g., https://github.com/your-org/rbc-infrastructure): " REPO_URL

if [ -z "$REPO_URL" ]; then
    echo "❌ Repository URL is required"
    exit 1
fi

# Update app-of-apps with correct repository
echo "📝 Configuring app-of-apps..."
sed -i.bak "s|https://github.com/your-org/rbc-infrastructure|${REPO_URL}|g" ../argocd/applications/app-of-apps.yaml

# Apply ArgoCD projects
echo "📦 Creating ArgoCD projects..."
kubectl apply -f ../argocd/applications/argocd-project.yaml

# Apply app-of-apps
echo "🎯 Deploying app-of-apps pattern..."
kubectl apply -f ../argocd/applications/app-of-apps.yaml

# Wait for sync
echo "⏳ Waiting for initial sync..."
sleep 10

# Check application status
echo "📊 Checking application status..."
kubectl get applications -n argocd

echo "✅ GitOps bootstrap complete!"
echo ""
echo "📋 Next steps:"
echo "1. Commit and push any changes to your infrastructure repository"
echo "2. ArgoCD will automatically detect and deploy changes"
echo "3. Monitor applications in ArgoCD UI"
echo ""
echo "🔍 To check application status:"
echo "   kubectl get applications -n argocd"
echo "   argocd app list"