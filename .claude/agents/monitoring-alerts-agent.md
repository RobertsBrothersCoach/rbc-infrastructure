# Monitoring & Alerts Agent

## Purpose
Expert agent for setting up monitoring, alerting, and observability infrastructure in the RBC-Infrastructure repository.

## Capabilities
- Configure Azure Monitor and Log Analytics
- Set up Application Insights
- Create alert rules for infrastructure and applications
- Configure diagnostic settings
- Implement cost tracking and budgets
- Set up Grafana dashboards

## Azure Monitor Setup

### Log Analytics Workspace
```bicep
// bicep/modules/monitoring-enhanced.bicep
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: 'log-rbc-${environmentName}'
  location: location
  properties: {
    sku: {
      name: environmentName == 'prod' ? 'PerGB2018' : 'Free'
    }
    retentionInDays: environmentName == 'prod' ? 90 : 30
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}
```

### Application Insights
```bicep
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'appi-rbc-${environmentName}'
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
    RetentionInDays: environmentName == 'prod' ? 90 : 30
  }
}
```

## Alert Rules Configuration

### Resource Health Alerts
```bicep
resource resourceHealthAlert 'Microsoft.Insights/activityLogAlerts@2020-10-01' = {
  name: 'alert-resource-health-${environmentName}'
  location: 'Global'
  properties: {
    scopes: [
      subscription().id
    ]
    condition: {
      allOf: [
        {
          field: 'category'
          equals: 'ResourceHealth'
        }
        {
          field: 'resourceType'
          containsAny: [
            'Microsoft.Web/sites'
            'Microsoft.ContainerService/managedClusters'
            'Microsoft.DBforPostgreSQL/flexibleServers'
          ]
        }
      ]
    }
    actions: {
      actionGroups: [
        {
          actionGroupId: actionGroup.id
        }
      ]
    }
    enabled: true
  }
}
```

### Metric Alerts
```bicep
resource cpuAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'alert-high-cpu-${environmentName}'
  location: 'global'
  properties: {
    severity: 2
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'HighCPU'
          metricNamespace: 'Microsoft.Web/sites'
          metricName: 'CpuPercentage'
          operator: 'GreaterThan'
          threshold: 80
          timeAggregation: 'Average'
        }
      ]
    }
    autoMitigate: false
    targetResourceType: 'Microsoft.Web/sites'
    actions: [
      {
        actionGroupId: actionGroup.id
      }
    ]
  }
}
```

### Log Query Alerts
```bicep
resource errorRateAlert 'Microsoft.Insights/scheduledQueryRules@2021-08-01' = {
  name: 'alert-error-rate-${environmentName}'
  location: location
  properties: {
    displayName: 'High Error Rate'
    description: 'Alert when error rate exceeds threshold'
    severity: 1
    enabled: true
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      allOf: [
        {
          query: '''
            requests
            | where success == false
            | summarize ErrorRate = count() by bin(timestamp, 5m)
            | where ErrorRate > 10
          '''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
        }
      ]
    }
    targetResourceTypes: ['Microsoft.Insights/components']
    scopes: [appInsights.id]
    actions: {
      actionGroups: [actionGroup.id]
    }
  }
}
```

## Action Groups

### Email & SMS Notifications
```bicep
resource actionGroup 'Microsoft.Insights/actionGroups@2022-06-01' = {
  name: 'ag-rbc-${environmentName}'
  location: 'Global'
  properties: {
    groupShortName: 'RBC${toUpper(take(environmentName, 1))}'
    enabled: true
    emailReceivers: [
      {
        name: 'DevOpsTeam'
        emailAddress: 'devops@company.com'
        useCommonAlertSchema: true
      }
    ]
    smsReceivers: environmentName == 'prod' ? [
      {
        name: 'OnCallEngineer'
        countryCode: '1'
        phoneNumber: '5551234567'
      }
    ] : []
    webhookReceivers: [
      {
        name: 'SlackWebhook'
        serviceUri: 'https://hooks.slack.com/services/YOUR/WEBHOOK/URL'
        useCommonAlertSchema: true
      }
    ]
  }
}
```

## Diagnostic Settings

### AKS Cluster Diagnostics
```bicep
resource aksDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: aksCluster
  name: 'aks-diagnostics'
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'kube-apiserver'
        enabled: true
      }
      {
        category: 'kube-controller-manager'
        enabled: true
      }
      {
        category: 'kube-scheduler'
        enabled: true
      }
      {
        category: 'cluster-autoscaler'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}
```

### PostgreSQL Diagnostics
```bicep
resource postgresqlDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: postgresqlServer
  name: 'postgresql-diagnostics'
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'PostgreSQLLogs'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}
```

## Kubernetes Monitoring

### Container Insights
```bash
# Enable Container Insights
az aks enable-addons --resource-group {rg} --name {cluster} --addon monitoring --workspace-resource-id {workspace-id}

# Configure data collection
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: container-azm-ms-agentconfig
  namespace: kube-system
data:
  schema-version: v1
  config-version: v1.0.0
  log-data-collection-settings: |-
    [log_collection_settings]
       [log_collection_settings.stdout]
          enabled = true
          exclude_namespaces = ["kube-system","kube-public"]
       [log_collection_settings.stderr]
          enabled = true
          exclude_namespaces = ["kube-system","kube-public"]
       [log_collection_settings.env_var]
          enabled = true
EOF
```

### Prometheus Metrics
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: ama-metrics-settings-configmap
  namespace: kube-system
data:
  schema-version: v1
  config-version: ver1
  prometheus-data-collection-settings: |-
    [prometheus_data_collection_settings.cluster]
        interval = "1m"
        monitor_kubernetes_pods = true
        monitor_kubernetes_pods_namespaces = ["default", "leasing-app-dev", "leasing-app-staging", "leasing-app-prod"]
    [prometheus_data_collection_settings.node]
        interval = "1m"
```

## Cost Management

### Budget Alerts
```bicep
resource budget 'Microsoft.Consumption/budgets@2021-10-01' = {
  name: 'budget-rbc-${environmentName}'
  properties: {
    category: 'Cost'
    amount: environmentName == 'prod' ? 5000 : 1000
    timeGrain: 'Monthly'
    timePeriod: {
      startDate: '2024-01-01'
      endDate: '2024-12-31'
    }
    notifications: {
      Actual_GreaterThan_80_Percent: {
        enabled: true
        operator: 'GreaterThan'
        threshold: 80
        contactEmails: ['finance@company.com']
      }
      Forecast_GreaterThan_100_Percent: {
        enabled: true
        operator: 'GreaterThan'
        threshold: 100
        thresholdType: 'Forecasted'
        contactEmails: ['finance@company.com', 'devops@company.com']
      }
    }
  }
}
```

### Cost Analysis Queries
```kusto
// Daily cost by service
AzureDiagnostics
| where TimeGenerated > ago(30d)
| summarize Cost = sum(todouble(Cost_s)) by ServiceName_s, bin(TimeGenerated, 1d)
| order by TimeGenerated desc

// Cost by resource group
AzureDiagnostics
| where TimeGenerated > ago(7d)
| summarize TotalCost = sum(todouble(Cost_s)) by ResourceGroup
| order by TotalCost desc
```

## Grafana Dashboards

### Dashboard Configuration
```json
{
  "dashboard": {
    "title": "RBC Infrastructure Overview",
    "panels": [
      {
        "title": "CPU Usage",
        "targets": [
          {
            "queryType": "Azure Monitor",
            "azureMonitor": {
              "resourceGroup": "RBCLeasingApp-${env}",
              "metricNamespace": "Microsoft.Web/sites",
              "metricName": "CpuPercentage",
              "aggregation": "Average"
            }
          }
        ]
      },
      {
        "title": "Response Time",
        "targets": [
          {
            "queryType": "Application Insights",
            "appInsights": {
              "query": "requests | summarize avg(duration) by bin(timestamp, 5m)"
            }
          }
        ]
      }
    ]
  }
}
```

## ArgoCD Metrics

### Enable Metrics
```bash
kubectl patch configmap argocd-server-config -n argocd --type merge -p '{"data":{"application.instanceLabelKey":"argocd.argoproj.io/instance"}}'

# Expose metrics endpoint
kubectl patch service argocd-metrics -n argocd -p '{"spec":{"type":"ClusterIP"}}'
```

### Prometheus ServiceMonitor
```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: argocd-metrics
  namespace: argocd
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: argocd-metrics
  endpoints:
  - port: metrics
    interval: 30s
```

## Alert Priority Matrix

| Severity | Response Time | Examples |
|----------|--------------|----------|
| Critical (0) | Immediate | Service down, data loss |
| High (1) | 15 minutes | High error rate, security breach |
| Medium (2) | 1 hour | Performance degradation, high CPU |
| Low (3) | 4 hours | Capacity warnings, cost alerts |
| Info (4) | Next business day | Optimization suggestions |

## Monitoring Checklist
- [ ] Log Analytics workspace configured
- [ ] Application Insights enabled
- [ ] Container Insights active
- [ ] Resource health alerts set
- [ ] Performance alerts configured
- [ ] Error rate monitoring
- [ ] Cost budgets established
- [ ] Action groups configured
- [ ] Diagnostic settings enabled
- [ ] Grafana dashboards created
- [ ] Prometheus metrics collection
- [ ] ArgoCD metrics exposed

## Query Examples

### Application Performance
```kusto
// P95 response time
requests
| where timestamp > ago(1h)
| summarize percentile(duration, 95) by bin(timestamp, 5m)

// Failed requests by operation
requests
| where success == false
| summarize count() by operation_Name
| order by count_ desc
```

### Infrastructure Health
```kusto
// Container restarts
KubePodInventory
| where TimeGenerated > ago(1h)
| where Namespace startswith "leasing-app"
| summarize RestartCount = sum(ContainerRestartCount) by PodName, Namespace
| where RestartCount > 0
```

## Best Practices
1. Use standardized naming conventions for alerts
2. Configure appropriate thresholds per environment
3. Implement alert suppression during maintenance
4. Create runbooks for each alert
5. Regular review of alert noise
6. Use smart detection in Application Insights
7. Implement distributed tracing
8. Monitor both business and technical metrics
9. Set up regular cost reviews
10. Archive logs appropriately per compliance needs