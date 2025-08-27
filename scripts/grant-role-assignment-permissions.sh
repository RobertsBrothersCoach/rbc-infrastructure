#!/bin/bash

# Grant Role Assignment Permissions to Service Principal
# This script grants the User Access Administrator role to the service principal
# so it can create role assignments during deployment

set -e

# Default values
SERVICE_PRINCIPAL_NAME="${1:-rbc-leasing-app-sp}"
SCOPE="${2:-ResourceGroup}"
RESOURCE_GROUP_NAME="${3:-RBCLeasingApp-Qa}"

echo -e "\033[32mGranting Role Assignment Permissions to Service Principal\033[0m"
echo -e "\033[32m=========================================================\033[0m"

# Check if logged in to Azure
if ! az account show &>/dev/null; then
    echo -e "\033[31mNot logged in to Azure. Please run 'az login' first.\033[0m"
    exit 1
fi

# Get current subscription
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
SUBSCRIPTION_NAME=$(az account show --query name -o tsv)
echo -e "\033[36mUsing subscription: $SUBSCRIPTION_NAME ($SUBSCRIPTION_ID)\033[0m"

# Find service principal
echo -e "\n\033[33mFinding service principal: $SERVICE_PRINCIPAL_NAME\033[0m"
SP_ID=$(az ad sp list --display-name "$SERVICE_PRINCIPAL_NAME" --query "[0].id" -o tsv 2>/dev/null || true)

if [ -z "$SP_ID" ]; then
    echo -e "\033[31mService principal '$SERVICE_PRINCIPAL_NAME' not found.\033[0m"
    echo -e "\033[33mAvailable service principals:\033[0m"
    az ad sp list --query "[?contains(displayName, 'rbc') || contains(displayName, 'leasing')].{Name:displayName, ID:id}" -o table
    exit 1
fi

SP_APP_ID=$(az ad sp list --display-name "$SERVICE_PRINCIPAL_NAME" --query "[0].appId" -o tsv)
echo -e "\033[32mFound service principal: $SERVICE_PRINCIPAL_NAME\033[0m"
echo -e "\033[90m  Object ID: $SP_ID\033[0m"
echo -e "\033[90m  Application ID: $SP_APP_ID\033[0m"

# Determine scope
if [ "$SCOPE" == "Subscription" ]; then
    SCOPE_PATH="/subscriptions/$SUBSCRIPTION_ID"
    echo -e "\n\033[36mScope: Subscription level\033[0m"
else
    # Check if resource group exists
    if ! az group show --name "$RESOURCE_GROUP_NAME" &>/dev/null; then
        echo -e "\033[33mResource group '$RESOURCE_GROUP_NAME' not found. Creating it...\033[0m"
        az group create --name "$RESOURCE_GROUP_NAME" --location "eastus2"
    fi
    SCOPE_PATH="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP_NAME"
    echo -e "\n\033[36mScope: Resource Group '$RESOURCE_GROUP_NAME'\033[0m"
fi

# Check existing role assignments
echo -e "\n\033[33mChecking existing role assignments...\033[0m"
EXISTING_ROLES=$(az role assignment list --assignee "$SP_ID" --scope "$SCOPE_PATH" --query "[].roleDefinitionName" -o tsv 2>/dev/null || true)

if [ -n "$EXISTING_ROLES" ]; then
    echo -e "\033[36mCurrent roles:\033[0m"
    echo "$EXISTING_ROLES" | while read -r role; do
        echo -e "\033[90m  - $role\033[0m"
    done
fi

# Define roles to assign
ROLES_TO_ASSIGN=("User Access Administrator" "Contributor")

for ROLE in "${ROLES_TO_ASSIGN[@]}"; do
    if echo "$EXISTING_ROLES" | grep -q "^$ROLE$"; then
        echo -e "\n\033[33mRole '$ROLE' already assigned - skipping\033[0m"
    else
        echo -e "\n\033[33mAssigning role '$ROLE'...\033[0m"
        if az role assignment create \
            --assignee "$SP_ID" \
            --role "$ROLE" \
            --scope "$SCOPE_PATH" 2>/dev/null; then
            echo -e "\033[32m  ✓ Successfully assigned '$ROLE' role\033[0m"
        else
            echo -e "\033[31m  ✗ Failed to assign '$ROLE' role\033[0m"
            echo -e "\n\033[33mYou may need higher permissions. Try:\033[0m"
            echo -e "\033[90m  1. Run this script with Owner or User Access Administrator role\033[0m"
            echo -e "\033[90m  2. Ask an admin to run this script\033[0m"
            echo -e "\033[90m  3. Use Azure Portal to manually assign roles\033[0m"
        fi
    fi
done

# Verify final permissions
echo -e "\n\033[33mVerifying final role assignments...\033[0m"
FINAL_ROLES=$(az role assignment list --assignee "$SP_ID" --scope "$SCOPE_PATH" --query "[].roleDefinitionName" -o tsv 2>/dev/null || true)

if [ -n "$FINAL_ROLES" ]; then
    echo -e "\033[32mFinal roles assigned:\033[0m"
    echo "$FINAL_ROLES" | while read -r role; do
        echo -e "\033[90m  ✓ $role\033[0m"
    done
else
    echo -e "\033[31mNo roles found. There may have been an issue with assignment.\033[0m"
fi

echo -e "\n\033[32m=========================================================\033[0m"
echo -e "\033[32mScript completed!\033[0m"
echo ""
echo -e "\033[36mNext steps:\033[0m"
echo -e "\033[90m  1. Wait 1-2 minutes for permissions to propagate\033[0m"
echo -e "\033[90m  2. Re-run the GitHub Actions deployment workflow\033[0m"
echo -e "\033[90m  3. The deployment should now be able to create role assignments\033[0m"