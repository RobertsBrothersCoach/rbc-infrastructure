#!/bin/bash

# Azure AD Configuration Script for ArgoCD
# This script helps configure Azure AD OIDC for ArgoCD

set -e

echo "🔐 Configuring Azure AD for ArgoCD..."

# Check required environment variables
if [ -z "$TENANT_ID" ] || [ -z "$CLIENT_ID" ] || [ -z "$CLIENT_SECRET" ]; then
    echo "❌ Missing required environment variables:"
    echo "   TENANT_ID, CLIENT_ID, CLIENT_SECRET"
    echo ""
    echo "📝 Usage:"
    echo "   export TENANT_ID=your-tenant-id"
    echo "   export CLIENT_ID=your-client-id"
    echo "   export CLIENT_SECRET=your-client-secret"
    echo "   ./configure-azure-ad.sh"
    exit 1
fi

# Update ArgoCD ConfigMap with Azure AD settings
echo "📝 Updating ArgoCD configuration..."
kubectl patch configmap argocd-cm -n argocd --type merge -p "{
  \"data\": {
    \"oidc.config\": \"name: Azure AD\nissuer: https://login.microsoftonline.com/${TENANT_ID}/v2.0\nclientId: ${CLIENT_ID}\nclientSecret: \$oidc.azure.clientSecret\nrequestedScopes: [\\\"openid\\\", \\\"profile\\\", \\\"email\\\"]\nrequestedIDTokenClaims: {\\\"groups\\\": {\\\"essential\\\": true}}\"
  }
}"

# Create secret for OIDC client secret
echo "🔑 Creating OIDC secret..."
kubectl create secret generic argocd-secret \
  --from-literal=oidc.azure.clientSecret="${CLIENT_SECRET}" \
  -n argocd \
  --dry-run=client -o yaml | kubectl apply -f -

# Restart ArgoCD server
echo "🔄 Restarting ArgoCD server..."
kubectl rollout restart deployment argocd-server -n argocd
kubectl rollout status deployment argocd-server -n argocd

echo "✅ Azure AD configuration complete!"
echo ""
echo "📋 Next steps:"
echo "1. Update the ArgoCD URL in Azure AD app registration"
echo "2. Add redirect URIs:"
echo "   - https://your-argocd-url/auth/callback"
echo "   - https://your-argocd-url/api/dex/callback"
echo "3. Grant admin consent for the app permissions"