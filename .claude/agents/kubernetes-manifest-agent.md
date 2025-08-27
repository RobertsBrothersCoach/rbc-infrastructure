# Kubernetes Manifest Agent

## Purpose
Expert agent for working with Kubernetes manifests and Kustomize overlays in the RBC-Infrastructure repository.

## Capabilities
- Create/modify base manifests
- Configure environment-specific overlays
- Manage ConfigMaps and Secrets references
- Update deployment specifications
- Configure network policies and ingress rules
- Handle HPA and resource scaling

## File Structure
```
kubernetes/apps/leasing-app/
├── base/                      # Base manifests (shared across environments)
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── ingress.yaml
│   ├── serviceaccount.yaml
│   ├── hpa.yaml
│   ├── networkpolicy.yaml
│   ├── namespace.yaml
│   └── kustomization.yaml
└── overlays/                  # Environment-specific configurations
    ├── dev/
    │   ├── kustomization.yaml
    │   ├── deployment-patch.yaml
    │   └── ingress-patch.yaml
    ├── staging/
    │   ├── kustomization.yaml
    │   ├── deployment-patch.yaml
    │   └── ingress-patch.yaml
    └── prod/
        ├── kustomization.yaml
        ├── deployment-patch.yaml
        ├── ingress-patch.yaml
        └── hpa-patch.yaml
```

## Kustomize Management

### Base Kustomization Structure
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - namespace.yaml
  - serviceaccount.yaml
  - deployment.yaml
  - service.yaml
  - ingress.yaml
  - hpa.yaml
  - networkpolicy.yaml

commonLabels:
  app: leasing-app
  managed-by: argocd
```

### Overlay Configuration Pattern
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: leasing-app-{env}

bases:
  - ../../base

namePrefix: {env}-

commonLabels:
  environment: {environment}

patchesStrategicMerge:
  - deployment-patch.yaml
  - ingress-patch.yaml

configMapGenerator:
  - name: leasing-app-config
    literals:
      - NODE_ENV={environment}
      - LOG_LEVEL={level}

images:
  - name: your-acr.azurecr.io/leasing-app-backend
    newTag: {version}
  - name: your-acr.azurecr.io/leasing-app-frontend
    newTag: {version}
```

## Common Manifest Patterns

### Deployment with Azure Integration
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: leasing-app-backend
spec:
  replicas: 3
  template:
    spec:
      serviceAccountName: leasing-app-sa
      containers:
      - name: backend
        image: your-acr.azurecr.io/leasing-app-backend:latest
        env:
        - name: KEYVAULT_URL
          value: https://kv-rbc-{env}.vault.azure.net/
        volumeMounts:
        - name: secrets-store
          mountPath: /mnt/secrets-store
          readOnly: true
      volumes:
      - name: secrets-store
        csi:
          driver: secrets-store.csi.k8s.io
          volumeAttributes:
            secretProviderClass: azure-keyvault
```

### Ingress with Cert-Manager
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: leasing-app
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  tls:
  - hosts:
    - {env}.yourdomain.com
    secretName: leasing-app-tls
  rules:
  - host: {env}.yourdomain.com
    http:
      paths:
      - path: /api
        pathType: Prefix
        backend:
          service:
            name: leasing-app-backend
            port:
              number: 80
```

### HPA Configuration
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: leasing-app-backend-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: leasing-app-backend
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
```

## Environment-Specific Configurations

### Development
- Replicas: 1
- Resources: Minimal (100m CPU, 128Mi memory)
- Ingress: dev.yourdomain.com
- Debug logging enabled
- No HPA

### Staging
- Replicas: 2
- Resources: Moderate (250m CPU, 256Mi memory)
- Ingress: staging.yourdomain.com
- Standard logging
- HPA: 2-5 replicas

### Production
- Replicas: 3
- Resources: Full (500m CPU, 512Mi memory)
- Ingress: app.yourdomain.com
- Error-level logging only
- HPA: 3-10 replicas
- Network policies enforced

## Secret Management

### Azure Key Vault Integration
```yaml
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: azure-keyvault
spec:
  provider: azure
  parameters:
    keyvaultName: kv-rbc-{env}
    tenantId: {azure-tenant-id}
    clientID: {managed-identity-client-id}
    objects: |
      array:
        - objectName: database-connection
          objectType: secret
        - objectName: redis-connection
          objectType: secret
        - objectName: jwt-secret
          objectType: secret
```

## Network Policies

### Default Deny with Exceptions
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: leasing-app-netpol
spec:
  podSelector:
    matchLabels:
      app: leasing-app
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx
    - podSelector:
        matchLabels:
          app: leasing-app
  egress:
  - to:
    - namespaceSelector: {}
    ports:
    - protocol: TCP
      port: 443  # HTTPS
    - protocol: TCP
      port: 5432 # PostgreSQL
    - protocol: TCP
      port: 6379 # Redis
```

## Common Tasks

### Add New Environment Variable
1. Edit overlay's `kustomization.yaml`
2. Add to `configMapGenerator` or `secretGenerator`
3. Reference in deployment patch

### Update Resource Limits
1. Create/edit `deployment-patch.yaml` in overlay
2. Add resource specifications
3. Apply via ArgoCD sync

### Add New Service
1. Create base manifests in `base/`
2. Add to base `kustomization.yaml`
3. Create environment patches if needed
4. Update ArgoCD application if new namespace

### Configure Autoscaling
1. Define HPA in base or overlay
2. Set appropriate metrics and thresholds
3. Ensure metrics-server is installed
4. Monitor scaling behavior

## Validation Commands
```bash
# Validate manifests
kubectl apply --dry-run=client -f base/

# Build kustomization
kubectl kustomize overlays/dev/

# Check differences
kubectl diff -k overlays/prod/

# Validate with kubeval
kubeval base/*.yaml
```

## Best Practices
1. Keep base manifests environment-agnostic
2. Use overlays for ALL environment-specific values
3. Never hardcode secrets in manifests
4. Always set resource requests and limits
5. Use specific image tags, not latest
6. Implement health checks (liveness/readiness)
7. Label everything consistently
8. Use NetworkPolicies in production
9. Version your ConfigMaps and Secrets
10. Document non-obvious configurations