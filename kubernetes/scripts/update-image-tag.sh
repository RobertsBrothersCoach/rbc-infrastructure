#!/bin/bash

# Update Image Tag Script
# This script updates image tags in Kustomization files (typically called from CI/CD)

set -e

# Parse arguments
ENVIRONMENT=$1
COMPONENT=$2
NEW_TAG=$3

if [ -z "$ENVIRONMENT" ] || [ -z "$COMPONENT" ] || [ -z "$NEW_TAG" ]; then
    echo "❌ Missing required arguments"
    echo "Usage: ./update-image-tag.sh <environment> <component> <tag>"
    echo "Example: ./update-image-tag.sh dev backend v1.2.3"
    echo ""
    echo "Environments: dev, staging, prod"
    echo "Components: backend, frontend"
    exit 1
fi

# Validate environment
if [[ ! "$ENVIRONMENT" =~ ^(dev|staging|prod)$ ]]; then
    echo "❌ Invalid environment: $ENVIRONMENT"
    echo "Valid environments: dev, staging, prod"
    exit 1
fi

# Validate component
if [[ ! "$COMPONENT" =~ ^(backend|frontend)$ ]]; then
    echo "❌ Invalid component: $COMPONENT"
    echo "Valid components: backend, frontend"
    exit 1
fi

KUSTOMIZATION_FILE="../apps/leasing-app/overlays/${ENVIRONMENT}/kustomization.yaml"

if [ ! -f "$KUSTOMIZATION_FILE" ]; then
    echo "❌ Kustomization file not found: $KUSTOMIZATION_FILE"
    exit 1
fi

echo "📝 Updating image tag..."
echo "   Environment: $ENVIRONMENT"
echo "   Component: $COMPONENT"
echo "   New tag: $NEW_TAG"

# Update the image tag using sed
if [[ "$COMPONENT" == "backend" ]]; then
    sed -i.bak "s|acrrbc*.azurecr.io/leasing-app-backend:.*|acrrbc${ENVIRONMENT}.azurecr.io/leasing-app-backend:${NEW_TAG}|g" "$KUSTOMIZATION_FILE"
else
    sed -i.bak "s|acrrbc*.azurecr.io/leasing-app-frontend:.*|acrrbc${ENVIRONMENT}.azurecr.io/leasing-app-frontend:${NEW_TAG}|g" "$KUSTOMIZATION_FILE"
fi

# Remove backup file
rm -f "${KUSTOMIZATION_FILE}.bak"

echo "✅ Image tag updated successfully!"
echo ""
echo "📋 Next steps:"
echo "1. Commit the changes: git add $KUSTOMIZATION_FILE"
echo "2. Push to repository: git push"
echo "3. ArgoCD will detect and deploy the change"