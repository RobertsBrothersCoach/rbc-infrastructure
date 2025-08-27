# Azure Federated Identity Setup Script for GitHub Actions (PowerShell version)
# This script configures federated identity credentials for GitHub Actions OIDC authentication

# Configuration
$APP_NAME = "sp-tourbus-github-actions"
$GITHUB_ORG = "RobertsBrothersCoach"
$GITHUB_REPO = "RBC-LeasingApp"
$SUBSCRIPTION_ID = "YOUR_SUBSCRIPTION_ID" # Replace with your actual subscription ID

Write-Host "Setting up Azure Federated Identity Credentials for GitHub Actions..." -ForegroundColor Green

# Get the Application (Client) ID
$APP_ID = az ad app list --display-name "$APP_NAME" --query "[0].appId" -o tsv

if ([string]::IsNullOrEmpty($APP_ID)) {
    Write-Host "Error: Application '$APP_NAME' not found" -ForegroundColor Red
    exit 1
}

Write-Host "Found Application ID: $APP_ID" -ForegroundColor Yellow

# Function to create federated credential
function Create-FederatedCredential {
    param (
        [string]$Name,
        [string]$Subject,
        [string]$Description
    )
    
    Write-Host "Creating federated credential: $Name" -ForegroundColor Cyan
    
    # Create a temporary JSON file for the parameters
    $jsonContent = @{
        name = $Name
        issuer = "https://token.actions.githubusercontent.com"
        subject = $Subject
        description = $Description
        audiences = @("api://AzureADTokenExchange")
    } | ConvertTo-Json -Depth 10
    
    $tempFile = [System.IO.Path]::GetTempFileName()
    $jsonContent | Out-File -FilePath $tempFile -Encoding UTF8
    
    try {
        az ad app federated-credential create `
            --id "$APP_ID" `
            --parameters "@$tempFile" 2>&1 | Out-Host
    }
    catch {
        Write-Host "Warning: Credential may already exist or error occurred: $_" -ForegroundColor Yellow
    }
    finally {
        Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue
    }
}

# Create federated credentials for different scenarios

# 1. Main branch deployments
Create-FederatedCredential `
    -Name "github-main-branch" `
    -Subject "repo:${GITHUB_ORG}/${GITHUB_REPO}:ref:refs/heads/main" `
    -Description "GitHub Actions deployment from main branch"

# 2. QA Environment
Create-FederatedCredential `
    -Name "github-qa-environment" `
    -Subject "repo:${GITHUB_ORG}/${GITHUB_REPO}:environment:qa" `
    -Description "GitHub Actions deployment to QA environment"

# 3. Development Environment
Create-FederatedCredential `
    -Name "github-dev-environment" `
    -Subject "repo:${GITHUB_ORG}/${GITHUB_REPO}:environment:development" `
    -Description "GitHub Actions deployment to Development environment"

# 4. Production Environment
Create-FederatedCredential `
    -Name "github-prod-environment" `
    -Subject "repo:${GITHUB_ORG}/${GITHUB_REPO}:environment:production" `
    -Description "GitHub Actions deployment to Production environment"

# 5. Production Approval Environment
Create-FederatedCredential `
    -Name "github-prod-approval" `
    -Subject "repo:${GITHUB_ORG}/${GITHUB_REPO}:environment:production-approval" `
    -Description "GitHub Actions production approval environment"

# 6. Pull Request triggers (optional, for future use)
Create-FederatedCredential `
    -Name "github-pull-request" `
    -Subject "repo:${GITHUB_ORG}/${GITHUB_REPO}:pull_request" `
    -Description "GitHub Actions for pull requests"

Write-Host ""
Write-Host "✅ Federated identity credentials setup complete!" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "1. Ensure your GitHub repository has the following environments configured:"
Write-Host "   - development"
Write-Host "   - qa"
Write-Host "   - production"
Write-Host "   - production-approval"
Write-Host ""
Write-Host "2. Ensure the following GitHub Actions secrets are set:"
Write-Host "   - AZURE_CLIENT_ID: $APP_ID"
Write-Host "   - AZURE_TENANT_ID: (your tenant ID)"
Write-Host "   - AZURE_SUBSCRIPTION_ID: (your subscription ID)"
Write-Host ""
Write-Host "3. Re-run the CD workflow to test the deployment"