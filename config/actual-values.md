# Actual Configuration Values for RBC Infrastructure

## Azure IDs
- **Subscription ID**: 026185ca-7fce-4ff3-9790-bc4ecdebc550
- **Tenant ID**: 2bf8eca0-5705-47f9-bad9-10a86ef58a19
- **Subscription Name**: Azure subscription 1

## GitHub Configuration
- **Organization**: RobertsBrothersCoach
- **Repository**: rbc-infrastructure (lowercase as per GitHub)

## Resource Naming Convention (to be created)
- **Resource Group**: RBCLeasingApp-Dev (follows pattern from main.bicep)
- **ACR Name**: acrrbc{env} (e.g., acrrbcdev, acrrbcstaging, acrrbcprod)
- **Key Vault**: kv-rbc-{env}
- **AKS Cluster**: aks-rbc-{env}

## Domain Configuration
- **Domain**: To be determined (needs to be purchased or configured)
- **Suggested**: rbcleasing.com or rbc-leasing.azurewebsites.net

## Service Principal (Development)
- **Client ID (App ID)**: e4e45f45-cdae-4b9d-b163-e2581e02e096
- **Display Name**: sp-rbc-infrastructure-dev
- **Secret**: Stored in GitHub Secrets as AZURE_CREDENTIALS_DEV

## Placeholders to Replace
1. `your-org` → `RobertsBrothersCoach` ✅
2. `your-acr.azurecr.io` → `acrrbcdev.azurecr.io` ✅ (will be created)
3. `yourdomain.com` → `rbc-leasing.azurewebsites.net` ✅
4. `YOUR_TENANT_ID` → `2bf8eca0-5705-47f9-bad9-10a86ef58a19` ✅
5. `YOUR_CLIENT_ID` → `e4e45f45-cdae-4b9d-b163-e2581e02e096` ✅
6. `YOUR_AZURE_AD_*_GROUP_ID` → To be created during ArgoCD setup