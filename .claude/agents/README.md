# Claude Agents for RBC-Infrastructure

This directory contains specialized agent configurations for Claude Code to efficiently work with the RBC-Infrastructure repository. Each agent is an expert in a specific domain and provides detailed guidance, commands, and best practices.

## Available Agents

### 🏗️ Infrastructure Agents

1. **[bicep-deployment-agent](./bicep-deployment-agent.md)**
   - Azure Bicep infrastructure deployments
   - Environment-specific configurations
   - Zone redundancy setup
   - Resource naming conventions

2. **[argocd-gitops-agent](./argocd-gitops-agent.md)**
   - ArgoCD installation and management
   - Application synchronization
   - Image tag updates
   - GitOps workflows

3. **[kubernetes-manifest-agent](./kubernetes-manifest-agent.md)**
   - Kubernetes manifest creation
   - Kustomize overlay management
   - ConfigMap and Secret handling
   - Resource scaling configurations

### 🔒 Security & Compliance Agents

4. **[azure-security-agent](./azure-security-agent.md)**
   - Key Vault management
   - Entra ID authentication
   - RBAC configuration
   - Network security
   - Pod Security Standards

### 📊 Operations Agents

5. **[monitoring-alerts-agent](./monitoring-alerts-agent.md)**
   - Azure Monitor setup
   - Application Insights
   - Alert rule configuration
   - Cost tracking
   - Grafana dashboards

6. **[ci-cd-pipeline-agent](./ci-cd-pipeline-agent.md)**
   - GitHub Actions workflows
   - Deployment pipelines
   - Secret management
   - Approval workflows
   - Automated testing

### 🔄 Resilience Agents

7. **[disaster-recovery-agent](./disaster-recovery-agent.md)**
   - Backup configuration
   - Failover procedures
   - Zone redundancy testing
   - RPO/RTO management
   - Recovery runbooks

8. **[cost-optimization-agent](./cost-optimization-agent.md)**
   - Auto-shutdown configuration
   - Resource right-sizing
   - Budget management
   - Reserved instances
   - Cost analysis

## How to Use These Agents

### With Claude Code
When working with Claude Code, reference the specific agent for domain expertise:

```
"I need help setting up zone redundancy for PostgreSQL in production"
→ Refer to disaster-recovery-agent.md

"How do I update the backend image tag in staging?"
→ Refer to argocd-gitops-agent.md

"I want to configure auto-shutdown for the dev environment"
→ Refer to cost-optimization-agent.md
```

### Agent Selection Guide

| Task Category | Primary Agent | Secondary Agents |
|--------------|---------------|------------------|
| Deploy infrastructure | bicep-deployment | disaster-recovery, cost-optimization |
| Update application | argocd-gitops | kubernetes-manifest, ci-cd-pipeline |
| Security configuration | azure-security | monitoring-alerts |
| Cost reduction | cost-optimization | monitoring-alerts |
| Setup monitoring | monitoring-alerts | azure-security |
| Disaster recovery | disaster-recovery | bicep-deployment, argocd-gitops |
| CI/CD changes | ci-cd-pipeline | argocd-gitops |
| Kubernetes changes | kubernetes-manifest | argocd-gitops |

## Agent Capabilities Matrix

| Agent | Deploy | Monitor | Secure | Optimize | Recover |
|-------|--------|---------|---------|----------|---------|
| bicep-deployment | ✅ | - | ⚪ | ⚪ | ⚪ |
| argocd-gitops | ✅ | ⚪ | - | - | ⚪ |
| kubernetes-manifest | ⚪ | - | ⚪ | ⚪ | - |
| azure-security | - | ⚪ | ✅ | - | ⚪ |
| monitoring-alerts | - | ✅ | ⚪ | ⚪ | - |
| ci-cd-pipeline | ✅ | ⚪ | ⚪ | - | - |
| disaster-recovery | ⚪ | ⚪ | ⚪ | - | ✅ |
| cost-optimization | - | ⚪ | - | ✅ | - |

Legend: ✅ Primary capability | ⚪ Secondary capability | - Not applicable

## Common Workflows

### 1. Complete Infrastructure Deployment
```
bicep-deployment-agent → azure-security-agent → monitoring-alerts-agent
```

### 2. Application Update Flow
```
ci-cd-pipeline-agent → argocd-gitops-agent → monitoring-alerts-agent
```

### 3. Production Incident Response
```
monitoring-alerts-agent → disaster-recovery-agent → argocd-gitops-agent
```

### 4. Cost Optimization Review
```
cost-optimization-agent → monitoring-alerts-agent → bicep-deployment-agent
```

### 5. Security Hardening
```
azure-security-agent → kubernetes-manifest-agent → monitoring-alerts-agent
```

## Environment-Specific Guidance

### Development Environment
- **Primary agents**: cost-optimization, kubernetes-manifest
- **Focus**: Rapid iteration, cost control
- **Auto-shutdown**: Enabled (7 PM - 7 AM)

### Staging Environment
- **Primary agents**: argocd-gitops, ci-cd-pipeline
- **Focus**: Testing, validation
- **Auto-shutdown**: Enabled (10 PM - 6 AM)

### Production Environment
- **Primary agents**: disaster-recovery, monitoring-alerts, azure-security
- **Focus**: Stability, security, availability
- **Zone redundancy**: Required

## Best Practices

1. **Start with the most specific agent** for your task
2. **Cross-reference agents** for complex operations
3. **Follow the environment hierarchy**: dev → staging → prod
4. **Always validate** changes in lower environments first
5. **Use automation** where agents provide scripts
6. **Monitor costs** continuously with cost-optimization-agent
7. **Test DR procedures** regularly with disaster-recovery-agent
8. **Keep security current** with azure-security-agent

## Contributing

To add or update agents:
1. Create/modify the agent markdown file
2. Follow the existing structure
3. Include practical examples
4. Update this README with the new agent
5. Test the agent guidance with real scenarios

## Version
Last Updated: 2024-01-20
Compatible with: RBC-Infrastructure v1.0