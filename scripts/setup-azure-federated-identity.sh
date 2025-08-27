#!/bin/bash

# Azure Federated Identity Setup Script for GitHub Actions
# This script configures federated identity credentials for GitHub Actions OIDC authentication

# Configuration
APP_NAME="sp-tourbus-github-actions"
GITHUB_ORG="RobertsBrothersCoach"
GITHUB_REPO="RBC-LeasingApp"
SUBSCRIPTION_ID="YOUR_SUBSCRIPTION_ID" # Replace with your actual subscription ID

echo "Setting up Azure Federated Identity Credentials for GitHub Actions..."

# Get the Application (Client) ID
APP_ID=$(az ad app list --display-name "$APP_NAME" --query "[0].appId" -o tsv)

if [ -z "$APP_ID" ]; then
    echo "Error: Application '$APP_NAME' not found"
    exit 1
fi

echo "Found Application ID: $APP_ID"

# Function to create federated credential
create_federated_credential() {
    local name=$1
    local subject=$2
    local description=$3
    
    echo "Creating federated credential: $name"
    
    az ad app federated-credential create \
        --id "$APP_ID" \
        --parameters "{
            \"name\": \"$name\",
            \"issuer\": \"https://token.actions.githubusercontent.com\",
            \"subject\": \"$subject\",
            \"description\": \"$description\",
            \"audiences\": [\"api://AzureADTokenExchange\"]
        }"
}

# Create federated credentials for different scenarios

# 1. Main branch deployments
create_federated_credential \
    "github-main-branch" \
    "repo:${GITHUB_ORG}/${GITHUB_REPO}:ref:refs/heads/main" \
    "GitHub Actions deployment from main branch"

# 2. QA Environment
create_federated_credential \
    "github-qa-environment" \
    "repo:${GITHUB_ORG}/${GITHUB_REPO}:environment:qa" \
    "GitHub Actions deployment to QA environment"

# 3. Development Environment
create_federated_credential \
    "github-dev-environment" \
    "repo:${GITHUB_ORG}/${GITHUB_REPO}:environment:development" \
    "GitHub Actions deployment to Development environment"

# 4. Production Environment
create_federated_credential \
    "github-prod-environment" \
    "repo:${GITHUB_ORG}/${GITHUB_REPO}:environment:production" \
    "GitHub Actions deployment to Production environment"

# 5. Production Approval Environment
create_federated_credential \
    "github-prod-approval" \
    "repo:${GITHUB_ORG}/${GITHUB_REPO}:environment:production-approval" \
    "GitHub Actions production approval environment"

# 6. Pull Request triggers (optional, for future use)
create_federated_credential \
    "github-pull-request" \
    "repo:${GITHUB_ORG}/${GITHUB_REPO}:pull_request" \
    "GitHub Actions for pull requests"

echo ""
echo "✅ Federated identity credentials setup complete!"
echo ""
echo "Next steps:"
echo "1. Ensure your GitHub repository has the following environments configured:"
echo "   - development"
echo "   - qa"
echo "   - production"
echo "   - production-approval"
echo ""
echo "2. Ensure the following GitHub Actions secrets are set:"
echo "   - AZURE_CLIENT_ID: $APP_ID"
echo "   - AZURE_TENANT_ID: (your tenant ID)"
echo "   - AZURE_SUBSCRIPTION_ID: (your subscription ID)"
echo ""
echo "3. Re-run the CD workflow to test the deployment"