# Kubernetes Security Architecture

## Overview

This document outlines the multi-layered security approach for restricting access to services hosted on AKS.

## Security Layers

### 1. Network Security

#### Load Balancer Level
- **Azure Basic Load Balancer** with restricted NSG rules
- **DDoS Protection** via Azure (Basic tier included)
- **WAF** capabilities via nginx-ingress ModSecurity (optional)

#### Ingress Controller (nginx)
- **SSL/TLS Termination** with Let's Encrypt certificates
- **Rate Limiting** per IP/endpoint
- **IP Whitelisting** for sensitive services
- **Security Headers** (HSTS, X-Frame-Options, CSP)

#### Network Policies
- **Zero Trust Model**: Default deny all traffic
- **Explicit allow rules** for service communication
- **Namespace isolation** between environments
- **Database access** restricted to backend services only

```yaml
# Example: Only allow traffic from specific pods
spec:
  podSelector:
    matchLabels:
      tier: database
  ingress:
  - from:
    - podSelector:
        matchLabels:
          tier: backend
```

### 2. Authentication Methods

#### Azure AD Integration (Primary)
- **OAuth2 Proxy** with Azure AD
- **Group-based access** (rbc-developers, rbc-admins)
- **MFA enforcement** via Azure AD policies
- **Conditional Access** based on location/device

```yaml
# Ingress annotation for OAuth2
nginx.ingress.kubernetes.io/auth-url: "https://auth.cloud.rbccoach.com/oauth2/auth"
nginx.ingress.kubernetes.io/auth-signin: "https://auth.cloud.rbccoach.com/oauth2/start"
```

#### Basic Authentication (Fallback)
- **htpasswd** based authentication
- **Bcrypt hashed** passwords
- Used for emergency access or simple services

#### API Token Authentication
- **Service Account tokens** for automated access
- **JWT tokens** with expiration
- **Webhook token authentication** for external services

### 3. Authorization (RBAC)

#### Kubernetes RBAC
Maps Azure AD groups to Kubernetes permissions:

| Azure AD Group | Kubernetes Role | Permissions |
|----------------|-----------------|-------------|
| rbc-infrastructure-admins | cluster-admin | Full cluster access |
| rbc-developers | developer-role | Read pods/services, exec into pods |
| rbc-auditors | auditor-role | Read-only access to all resources |
| rbc-dev-team | namespace-admin | Full access to dev namespace |

#### ArgoCD RBAC
```yaml
policy.csv: |
  g, rbc-infrastructure-admins, role:admin
  g, rbc-developers, role:dev
  p, role:dev, applications, get, */*, allow
  p, role:dev, logs, get, */*, allow
```

### 4. Pod Security

#### Security Contexts
Every pod runs with:
- **Non-root user** (UID 1000+)
- **Read-only root filesystem**
- **Dropped capabilities** (ALL except required)
- **No privilege escalation**

```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  allowPrivilegeEscalation: false
  capabilities:
    drop: ["ALL"]
```

#### Pod Security Policies
- **Restricted PSP**: Production workloads
- **Baseline PSP**: Development/testing
- **OPA Policies**: Runtime enforcement

#### Resource Limits
Prevent resource exhaustion:
```yaml
resources:
  limits:
    memory: "128Mi"
    cpu: "500m"
  requests:
    memory: "64Mi"
    cpu: "250m"
```

### 5. Secrets Management

#### Azure Key Vault Integration
- **CSI Secret Store Driver** for mounting secrets
- **Managed identities** for authentication
- **Automatic rotation** of secrets
- **Audit logging** of secret access

```yaml
# Mount Key Vault secrets as volumes
volumes:
- name: secrets-store
  csi:
    driver: secrets-store.csi.k8s.io
    readOnly: true
    volumeAttributes:
      secretProviderClass: azure-keyvault
```

#### Kubernetes Secrets
- **Encrypted at rest** in etcd
- **RBAC restricted** access
- **Sealed Secrets** for GitOps (optional)

### 6. Access Restrictions by Service Type

#### Public Services (via Ingress)
```yaml
annotations:
  # Public but with rate limiting
  nginx.ingress.kubernetes.io/limit-rps: "10"
  nginx.ingress.kubernetes.io/limit-connections: "10"
```

#### Internal Services (with Auth)
```yaml
annotations:
  # Requires Azure AD authentication
  nginx.ingress.kubernetes.io/auth-url: "https://auth.cloud.rbccoach.com/oauth2/auth"
  # IP whitelist for office/VPN
  nginx.ingress.kubernetes.io/whitelist-source-range: "10.0.0.0/8"
```

#### Admin Services (ArgoCD, Grafana)
```yaml
annotations:
  # Multiple layers: OAuth2 + IP whitelist + rate limit
  nginx.ingress.kubernetes.io/auth-url: "https://auth.cloud.rbccoach.com/oauth2/auth"
  nginx.ingress.kubernetes.io/whitelist-source-range: "10.0.0.0/8"
  nginx.ingress.kubernetes.io/limit-rps: "5"
```

#### Database/Cache Access
- **No external ingress** - internal only
- **Network policies** restrict to backend pods
- **Service mesh** for mTLS (optional)

### 7. Audit and Compliance

#### Audit Logging
- **AKS audit logs** → Log Analytics
- **nginx access logs** → Application Insights
- **Failed auth attempts** → Security alerts
- **RBAC changes** → Audit trail

#### Compliance Scanning
- **Azure Policy** for AKS compliance
- **OPA/Gatekeeper** for runtime policies
- **Falco** for runtime security (optional)
- **Container image scanning** in ACR

### 8. Implementation Checklist

#### Immediate (Day 1)
- [x] nginx-ingress with SSL/TLS
- [x] Basic network policies
- [x] RBAC with Azure AD groups
- [ ] IP whitelisting for admin services
- [ ] Basic authentication backup

#### Short-term (Week 1)
- [ ] OAuth2 proxy deployment
- [ ] Pod security policies
- [ ] Resource limits on all pods
- [ ] Secret encryption at rest

#### Long-term (Month 1)
- [ ] OPA for policy enforcement
- [ ] Service mesh for mTLS
- [ ] Falco for runtime security
- [ ] Full audit logging pipeline

## Example: Securing ArgoCD

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server-ingress
  namespace: argocd
  annotations:
    # SSL/TLS
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    
    # Authentication (choose based on requirements)
    # Option 1: OAuth2 with Azure AD
    nginx.ingress.kubernetes.io/auth-url: "https://auth.cloud.rbccoach.com/oauth2/auth"
    
    # Option 2: IP Whitelist (office/VPN only)
    nginx.ingress.kubernetes.io/whitelist-source-range: "203.0.113.0/24"
    
    # Rate limiting
    nginx.ingress.kubernetes.io/limit-rps: "10"
    
    # Security headers
    nginx.ingress.kubernetes.io/configuration-snippet: |
      more_set_headers "X-Frame-Options: DENY";
      more_set_headers "X-Content-Type-Options: nosniff";
spec:
  tls:
  - hosts:
    - argocd-dev.cloud.rbccoach.com
    secretName: argocd-tls
  rules:
  - host: argocd-dev.cloud.rbccoach.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: argocd-server
            port:
              number: 80
```

## Cost Impact

| Security Feature | Monthly Cost | Value |
|-----------------|--------------|-------|
| nginx-ingress | ~$15-20 | Load balancing, SSL, WAF |
| OAuth2 Proxy | ~$2-3 | Azure AD integration |
| Network Policies | Free | Traffic isolation |
| RBAC | Free | Access control |
| Pod Security | Free | Runtime protection |
| **Total** | **~$17-23** | **Enterprise security** |

## Emergency Access

In case authentication systems fail:

1. **kubectl port-forward** (requires cluster credentials)
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

2. **Basic auth** (backup credentials)
3. **Azure Portal** → AKS → Workloads (read-only)

## Security Contacts

- **Security Issues**: security@rbccoach.com
- **Azure AD Admin**: admin@rbccoach.com
- **On-call DevOps**: devops@rbccoach.com