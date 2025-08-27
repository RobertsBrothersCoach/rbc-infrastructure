# CI/CD Pipeline Agent

## Purpose
Expert agent for managing GitHub Actions workflows and CI/CD pipelines in the RBC-Infrastructure repository.

## Capabilities
- Create/modify workflow files
- Set up environment-specific deployments
- Configure build and test pipelines
- Manage GitHub secrets and variables
- Implement approval workflows
- Handle automated image tag updates

## GitHub Actions Structure

### Workflow Files Location
```
.github/
├── workflows/
│   ├── infrastructure-deployment.yml  # Bicep deployment
│   ├── gitops-update.yml             # Image tag updates
│   ├── security-scan.yml             # Security scanning
│   └── pr-validation.yml             # PR checks
├── dependabot.yml                    # Dependency updates
└── CODEOWNERS                        # Code ownership
```

## Infrastructure Deployment Workflow

### Main Deployment Pipeline
```yaml
name: Infrastructure Deployment

on:
  push:
    branches: [main]
    paths:
      - 'bicep/**'
      - '.github/workflows/infrastructure-deployment.yml'
  workflow_dispatch:
    inputs:
      environment:
        description: 'Environment to deploy'
        required: true
        type: choice
        options:
          - dev
          - qa
          - prod
      action:
        description: 'Deployment action'
        required: true
        type: choice
        options:
          - deploy
          - destroy
          - plan

env:
  AZURE_SUBSCRIPTION_ID: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

jobs:
  validate:
    name: Validate Bicep Templates
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Azure Login
        uses: azure/login@v1
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
      
      - name: Validate templates
        run: |
          az bicep build --file bicep/main.bicep
          for file in bicep/modules/*.bicep; do
            az bicep build --file "$file"
          done

  deploy-dev:
    name: Deploy to Development
    needs: validate
    if: github.ref == 'refs/heads/main'
    environment:
      name: development
      url: https://dev.yourdomain.com
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Azure Login
        uses: azure/login@v1
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID_DEV }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
      
      - name: Deploy infrastructure
        run: |
          az deployment sub create \
            --location eastus2 \
            --template-file bicep/main.bicep \
            --parameters environmentName=dev \
            --parameters administratorPassword=${{ secrets.POSTGRES_ADMIN_PASSWORD_DEV }}

  deploy-prod:
    name: Deploy to Production
    needs: [deploy-staging]
    if: github.ref == 'refs/heads/main'
    environment:
      name: production
      url: https://app.yourdomain.com
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Azure Login
        uses: azure/login@v1
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID_PROD }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
      
      - name: Deploy infrastructure
        run: |
          az deployment sub create \
            --location eastus2 \
            --template-file bicep/main.bicep \
            --parameters environmentName=prod \
            --parameters administratorPassword=${{ secrets.POSTGRES_ADMIN_PASSWORD_PROD }} \
            --confirm-with-what-if
```

## GitOps Update Workflow

### Automated Image Tag Updates
```yaml
name: Update GitOps Manifests

on:
  workflow_call:
    inputs:
      environment:
        required: true
        type: string
      component:
        required: true
        type: string
      image_tag:
        required: true
        type: string
    secrets:
      PAT_TOKEN:
        required: true

jobs:
  update-manifests:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout infrastructure repo
        uses: actions/checkout@v4
        with:
          token: ${{ secrets.PAT_TOKEN }}
          
      - name: Update image tag
        run: |
          cd kubernetes/scripts
          ./update-image-tag.sh ${{ inputs.environment }} ${{ inputs.component }} ${{ inputs.image_tag }}
          
      - name: Commit and push changes
        run: |
          git config --global user.name "GitHub Actions"
          git config --global user.email "actions@github.com"
          git add kubernetes/apps/leasing-app/overlays/${{ inputs.environment }}/kustomization.yaml
          git commit -m "Update ${{ inputs.component }} to ${{ inputs.image_tag }} in ${{ inputs.environment }}"
          git push
```

## Security Scanning Workflow

### Container & Code Scanning
```yaml
name: Security Scanning

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
  schedule:
    - cron: '0 2 * * *'  # Daily at 2 AM

jobs:
  trivy-scan:
    name: Trivy Security Scan
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Run Trivy vulnerability scanner in IaC mode
        uses: aquasecurity/trivy-action@master
        with:
          scan-type: 'config'
          scan-ref: '.'
          format: 'sarif'
          output: 'trivy-results.sarif'
          
      - name: Upload Trivy results to GitHub Security
        uses: github/codeql-action/upload-sarif@v2
        with:
          sarif_file: 'trivy-results.sarif'

  container-scan:
    name: Container Image Scan
    runs-on: ubuntu-latest
    steps:
      - name: Run Trivy on container images
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: 'your-acr.azurecr.io/leasing-app-backend:latest'
          format: 'sarif'
          output: 'container-results.sarif'
          
      - name: Upload results
        uses: github/codeql-action/upload-sarif@v2
        with:
          sarif_file: 'container-results.sarif'
```

## PR Validation Workflow

### Pull Request Checks
```yaml
name: PR Validation

on:
  pull_request:
    branches: [main]

jobs:
  validate-bicep:
    name: Validate Bicep Changes
    runs-on: ubuntu-latest
    if: contains(github.event.pull_request.changed_files, 'bicep/')
    steps:
      - uses: actions/checkout@v4
      
      - name: Validate Bicep files
        run: |
          az bicep build --file bicep/main.bicep
          
      - name: Run What-If
        run: |
          az deployment sub what-if \
            --location eastus2 \
            --template-file bicep/main.bicep \
            --parameters environmentName=dev

  validate-kubernetes:
    name: Validate Kubernetes Manifests
    runs-on: ubuntu-latest
    if: contains(github.event.pull_request.changed_files, 'kubernetes/')
    steps:
      - uses: actions/checkout@v4
      
      - name: Install tools
        run: |
          curl -L https://github.com/instrumenta/kubeval/releases/latest/download/kubeval-linux-amd64.tar.gz | tar xz
          sudo mv kubeval /usr/local/bin
          
      - name: Validate manifests
        run: |
          find kubernetes/apps -name '*.yaml' -exec kubeval {} \;
          
      - name: Validate Kustomization
        run: |
          kubectl kustomize kubernetes/apps/leasing-app/overlays/dev
          kubectl kustomize kubernetes/apps/leasing-app/overlays/staging
          kubectl kustomize kubernetes/apps/leasing-app/overlays/prod
```

## GitHub Environments Configuration

### Environment Protection Rules
```yaml
# Development Environment
- name: development
  protection_rules:
    - required_reviewers: 0
    - wait_timer: 0
    - prevent_self_review: false
  
# Staging Environment
- name: staging
  protection_rules:
    - required_reviewers: 1
    - wait_timer: 0
    - prevent_self_review: true
    
# Production Environment
- name: production
  protection_rules:
    - required_reviewers: 2
    - wait_timer: 15  # minutes
    - prevent_self_review: true
    - required_environments:
      - staging
```

## Secrets Management

### Required GitHub Secrets
```yaml
# Azure Service Principal (per environment)
AZURE_CLIENT_ID_DEV
AZURE_CLIENT_ID_STAGING
AZURE_CLIENT_ID_PROD
AZURE_TENANT_ID
AZURE_SUBSCRIPTION_ID

# Database Passwords (per environment)
POSTGRES_ADMIN_PASSWORD_DEV
POSTGRES_ADMIN_PASSWORD_STAGING
POSTGRES_ADMIN_PASSWORD_PROD

# Container Registry
ACR_USERNAME
ACR_PASSWORD

# GitHub PAT for GitOps updates
PAT_TOKEN

# Monitoring
SLACK_WEBHOOK_URL
PAGERDUTY_KEY
```

### Setup Script
```bash
# Set GitHub secrets
gh secret set AZURE_CLIENT_ID_DEV --env development
gh secret set AZURE_CLIENT_ID_STAGING --env staging
gh secret set AZURE_CLIENT_ID_PROD --env production

# Set repository variables
gh variable set AZURE_REGION --body "eastus2"
gh variable set BACKUP_REGION --body "westcentralus"
```

## Reusable Workflows

### Docker Build & Push
```yaml
name: Build and Push Docker Image

on:
  workflow_call:
    inputs:
      dockerfile_path:
        required: true
        type: string
      image_name:
        required: true
        type: string
    outputs:
      image_tag:
        description: "The generated image tag"
        value: ${{ jobs.build.outputs.tag }}

jobs:
  build:
    runs-on: ubuntu-latest
    outputs:
      tag: ${{ steps.meta.outputs.tags }}
    steps:
      - uses: actions/checkout@v4
      
      - name: Generate metadata
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: your-acr.azurecr.io/${{ inputs.image_name }}
          tags: |
            type=ref,event=branch
            type=ref,event=pr
            type=semver,pattern={{version}}
            type=sha,prefix={{branch}}-
            
      - name: Login to ACR
        uses: docker/login-action@v3
        with:
          registry: your-acr.azurecr.io
          username: ${{ secrets.ACR_USERNAME }}
          password: ${{ secrets.ACR_PASSWORD }}
          
      - name: Build and push
        uses: docker/build-push-action@v5
        with:
          context: .
          file: ${{ inputs.dockerfile_path }}
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
```

## Deployment Status Notifications

### Slack Notifications
```yaml
- name: Notify deployment status
  if: always()
  uses: 8398a7/action-slack@v3
  with:
    status: ${{ job.status }}
    text: |
      Deployment to ${{ inputs.environment }} ${{ job.status }}
      Component: ${{ inputs.component }}
      Version: ${{ inputs.image_tag }}
      Actor: ${{ github.actor }}
    webhook_url: ${{ secrets.SLACK_WEBHOOK_URL }}
    fields: repo,message,commit,author,action,eventName,ref,workflow
```

## Matrix Strategy for Multi-Environment

### Parallel Environment Validation
```yaml
jobs:
  validate:
    strategy:
      matrix:
        environment: [dev, staging, prod]
        region: [eastus2, westcentralus]
        exclude:
          - environment: dev
            region: westcentralus
    runs-on: ubuntu-latest
    steps:
      - name: Validate ${{ matrix.environment }} in ${{ matrix.region }}
        run: |
          az deployment sub what-if \
            --location ${{ matrix.region }} \
            --template-file bicep/main.bicep \
            --parameters environmentName=${{ matrix.environment }}
```

## Best Practices
1. Use environments for deployment protection
2. Implement proper secret rotation
3. Use reusable workflows to avoid duplication
4. Enable required status checks for PRs
5. Use OIDC for Azure authentication (no secrets)
6. Implement proper versioning strategy
7. Cache dependencies for faster builds
8. Use matrix strategy for parallel testing
9. Implement rollback mechanisms
10. Monitor workflow run duration and costs