# Azure Security Agent

## Purpose
Expert agent for managing security configurations and compliance in the RBC-Infrastructure repository.

## Capabilities
- Configure Key Vault secrets and access policies
- Set up Entra ID (Azure AD) authentication
- Manage RBAC and role assignments
- Configure network security groups
- Implement Pod Security Standards
- Handle secret rotation policies

## Key Vault Management

### Secret Configuration
```powershell
# Create Key Vault secrets
az keyvault secret set --vault-name kv-rbc-{env} --name database-connection --value "Host=..."
az keyvault secret set --vault-name kv-rbc-{env} --name redis-connection --value "redis://..."
az keyvault secret set --vault-name kv-rbc-{env} --name jwt-secret --value "$(openssl rand -base64 32)"

# Set secret expiration
az keyvault secret set-attributes --vault-name kv-rbc-{env} --name database-connection --expires '2024-12-31T23:59:59Z'
```

### Access Policies
```powershell
# Grant access to managed identity
az keyvault set-policy --name kv-rbc-{env} \
  --spn {client-id} \
  --secret-permissions get list \
  --certificate-permissions get list

# Grant access to user/group
az keyvault set-policy --name kv-rbc-{env} \
  --upn user@domain.com \
  --secret-permissions get list set delete
```

### Secret Rotation Schedule
- **Production**: 
  - PostgreSQL passwords: 90 days
  - JWT signing keys: 365 days
  - API keys: 180 days
- **Non-Production**:
  - PostgreSQL passwords: 180 days
  - JWT signing keys: 365 days
  - API keys: 365 days

## Entra ID Configuration

### Application Registration
```powershell
# Run registration script
.\entra-id\Register-EntraIdApplication.ps1 -EnvironmentName dev

# Configure API scopes
.\entra-id\Configure-ApiScopes.ps1 -AppId {app-id}

# Set up security groups
.\entra-id\Configure-SecurityGroups.ps1

# Test configuration
.\entra-id\Test-EntraIdConfiguration.ps1 -EnvironmentName dev
```

### ArgoCD Azure AD Integration
```yaml
# kubernetes/argocd/install/argocd-cm-patch.yaml
oidc.config: |
  name: Azure AD
  issuer: https://login.microsoftonline.com/{tenant-id}/v2.0
  clientId: {client-id}
  clientSecret: $oidc.azure.clientSecret
  requestedScopes: ["openid", "profile", "email"]
  requestedIDTokenClaims: {"groups": {"essential": true}}
```

### Security Groups Structure
```
RBC-ArgoCD-Admins       # Full ArgoCD access
RBC-ArgoCD-Developers   # Dev/staging access
RBC-ArgoCD-ReadOnly     # Read-only access
RBC-AKS-Admins          # Kubernetes cluster admins
RBC-Azure-Contributors  # Azure resource contributors
```

## RBAC Configuration

### Azure RBAC
```powershell
# Grant role assignments
.\scripts\grant-role-assignment-permissions.ps1 `
  -ServicePrincipalId {sp-id} `
  -ResourceGroupName "RBCLeasingApp-{Env}"

# Common role assignments
az role assignment create \
  --assignee {principal-id} \
  --role "Key Vault Secrets User" \
  --scope /subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.KeyVault/vaults/{kv}
```

### Kubernetes RBAC
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: leasing-app-developer
  namespace: leasing-app-dev
rules:
- apiGroups: ["*"]
  resources: ["pods", "services", "deployments"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]
  resources: ["deployments/scale"]
  verbs: ["patch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: leasing-app-developer-binding
  namespace: leasing-app-dev
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: leasing-app-developer
subjects:
- kind: Group
  name: {azure-ad-group-id}
  apiGroup: rbac.authorization.k8s.io
```

## Network Security

### NSG Rules Configuration
```bicep
// bicep/modules/network-security-enhanced.bicep
securityRules: [
  {
    name: 'AllowHTTPS'
    properties: {
      priority: 100
      direction: 'Inbound'
      access: 'Allow'
      protocol: 'Tcp'
      sourcePortRange: '*'
      destinationPortRange: '443'
      sourceAddressPrefix: 'Internet'
      destinationAddressPrefix: '*'
    }
  }
  {
    name: 'AllowAzureLoadBalancer'
    properties: {
      priority: 110
      direction: 'Inbound'
      access: 'Allow'
      protocol: '*'
      sourcePortRange: '*'
      destinationPortRange: '*'
      sourceAddressPrefix: 'AzureLoadBalancer'
      destinationAddressPrefix: '*'
    }
  }
  {
    name: 'DenyAllInbound'
    properties: {
      priority: 4096
      direction: 'Inbound'
      access: 'Deny'
      protocol: '*'
      sourcePortRange: '*'
      destinationPortRange: '*'
      sourceAddressPrefix: '*'
      destinationAddressPrefix: '*'
    }
  }
]
```

### Private Endpoints
```bicep
// Configure private endpoints for services
resource privateEndpoint 'Microsoft.Network/privateEndpoints@2023-05-01' = {
  name: 'pe-${resourceName}'
  location: location
  properties: {
    subnet: {
      id: subnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'plsc-${resourceName}'
        properties: {
          privateLinkServiceId: resourceId
          groupIds: ['sqlServer']
        }
      }
    ]
  }
}
```

## Pod Security Standards

### Namespace Labels
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: leasing-app-prod
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

### Security Context
```yaml
apiVersion: apps/v1
kind: Deployment
spec:
  template:
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        fsGroup: 2000
        seccompProfile:
          type: RuntimeDefault
      containers:
      - name: app
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop:
            - ALL
          readOnlyRootFilesystem: true
```

## Secrets Store CSI Driver

### Installation
```bash
helm repo add csi-secrets-store-provider-azure https://azure.github.io/secrets-store-csi-driver-provider-azure/charts
helm install csi-secrets-store-provider-azure/csi-secrets-store-provider-azure \
  --generate-name --namespace kube-system
```

### SecretProviderClass
```yaml
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: azure-keyvault
spec:
  provider: azure
  parameters:
    keyvaultName: kv-rbc-{env}
    tenantId: {tenant-id}
    clientID: {client-id}
    cloudName: AzurePublicCloud
    objects: |
      array:
        - objectName: database-connection
          objectType: secret
        - objectName: redis-connection
          objectType: secret
```

## Managed Identity Configuration

### Enable on AKS
```bash
# Enable managed identity
az aks update -g {rg} -n {cluster} --enable-managed-identity

# Get identity client ID
IDENTITY_CLIENT_ID=$(az aks show -g {rg} -n {cluster} \
  --query identityProfile.kubeletidentity.clientId -o tsv)

# Grant Key Vault access
az keyvault set-policy -n {kv-name} \
  --secret-permissions get list \
  --spn $IDENTITY_CLIENT_ID
```

### Workload Identity
```bash
# Create service account
kubectl create serviceaccount leasing-app-sa -n leasing-app-prod

# Annotate with client ID
kubectl annotate serviceaccount leasing-app-sa \
  -n leasing-app-prod \
  azure.workload.identity/client-id={client-id}
```

## Security Monitoring

### Enable Diagnostic Settings
```bicep
resource diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'security-logs'
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        category: 'AuditEvent'
        enabled: true
      }
      {
        category: 'AzurePolicyEvaluationDetails'
        enabled: true
      }
    ]
  }
}
```

### Alert Rules
```bicep
resource secretExpirationAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'secret-expiration-alert'
  properties: {
    severity: 2
    evaluationFrequency: 'P1D'
    windowSize: 'P1D'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'SecretNearExpiry'
          metricNamespace: 'Microsoft.KeyVault/vaults'
          metricName: 'SecretNearExpiry'
          operator: 'GreaterThan'
          threshold: 0
          timeAggregation: 'Average'
        }
      ]
    }
  }
}
```

## Compliance Checklist
- [ ] All secrets in Key Vault
- [ ] Managed identities enabled
- [ ] Network policies configured
- [ ] Private endpoints for data services
- [ ] TLS/SSL for all endpoints
- [ ] Pod security standards enforced
- [ ] RBAC properly configured
- [ ] Audit logging enabled
- [ ] Secret rotation scheduled
- [ ] Security alerts configured

## Best Practices
1. Never store secrets in code or config files
2. Use managed identities over service principals
3. Enable audit logging for all security events
4. Implement defense in depth
5. Regular security assessments
6. Automate secret rotation
7. Use private endpoints for PaaS services
8. Implement zero-trust networking
9. Regular access reviews
10. Monitor for security anomalies