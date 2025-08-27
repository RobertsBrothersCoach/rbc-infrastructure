@description('Environment name')
param environmentName string

@description('Azure region for resources')
param location string = resourceGroup().location

@description('Key Vault name for storing cluster credentials')
param keyVaultName string

@description('Log Analytics workspace ID for monitoring')
param logAnalyticsWorkspaceId string

@description('Enable auto-shutdown for cost savings')
param enableAutoShutdown bool = environmentName != 'prod'

@description('Minimum node count (0 for cost savings in dev)')
param minNodeCount int = environmentName == 'prod' ? 1 : 0

@description('Maximum node count')
param maxNodeCount int = environmentName == 'prod' ? 5 : 3

@description('Node VM size - cost-effective options')
param nodeVmSize string = environmentName == 'prod' ? 'Standard_D2s_v3' : 'Standard_B2s'

// Cost-effective AKS cluster
resource aksCluster 'Microsoft.ContainerService/managedClusters@2024-02-01' = {
  name: 'aks-rbcleasing-${environmentName}'
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    kubernetesVersion: '1.29.4' // Stable version
    dnsPrefix: 'rbc-${environmentName}'
    
    // Cost-effective agent pool
    agentPoolProfiles: [
      {
        name: 'system'
        count: environmentName == 'prod' ? 2 : 1 // Minimal for dev
        vmSize: nodeVmSize
        type: 'VirtualMachineScaleSets'
        mode: 'System'
        osType: 'Linux'
        osDiskSizeGB: 30 // Minimal OS disk
        osDiskType: 'Managed'
        vnetSubnetID: null // Use default subnet for cost savings
        enableAutoScaling: true
        minCount: minNodeCount
        maxCount: maxNodeCount
        maxPods: 30
        
        // Cost optimization tags
        tags: {
          Environment: environmentName
          'Cost-Center': 'Development'
          'Auto-Shutdown': enableAutoShutdown ? 'true' : 'false'
        }
      }
    ]
    
    // Network configuration - basic for cost savings
    networkProfile: {
      networkPlugin: 'kubenet' // More cost-effective than Azure CNI
      networkPolicy: 'calico'   // Free network policy
      loadBalancerSku: 'Basic'  // Basic load balancer for dev
      serviceCidr: '10.100.0.0/16'
      dnsServiceIP: '10.100.0.10'
      podCidr: '10.101.0.0/16'
    }
    
    // Add-ons - minimal for cost
    addonProfiles: {
      omsAgent: {
        enabled: true
        config: {
          logAnalyticsWorkspaceResourceID: logAnalyticsWorkspaceId
        }
      }
      azurePolicy: {
        enabled: false // Disable to save costs
      }
      httpApplicationRouting: {
        enabled: false // Use ingress instead
      }
    }
    
    // RBAC and security
    enableRBAC: true
    aadProfile: {
      managed: true
      enableAzureRBAC: true
    }
    
    // Cost optimization features
    autoUpgradeProfile: {
      upgradeChannel: environmentName == 'prod' ? 'stable' : 'patch'
    }
    
    // Auto-scaler for cost optimization
    autoScalerProfile: {
      'scale-down-delay-after-add': '10m'
      'scale-down-unneeded-time': '10m'
      'scale-down-utilization-threshold': '0.5'
    }
  }
  
  tags: {
    Environment: environmentName
    Application: 'RBCLeasingApp'
    ManagedBy: 'Bicep'
    CostOptimized: 'true'
  }
}

// Store AKS admin credentials in Key Vault
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

resource aksCredentialSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'aks-admin-credentials-${environmentName}'
  properties: {
    value: base64ToString(aksCluster.listClusterAdminCredential().kubeconfigs[0].value)
    attributes: {
      enabled: true
    }
  }
}

// Auto-shutdown schedule for cost savings (dev only)
resource autoShutdownSchedule 'Microsoft.DevTestLab/schedules@2018-09-15' = if (enableAutoShutdown && environmentName != 'prod') {
  name: 'shutdown-computevm-aks-rbcleasing-${environmentName}'
  location: location
  properties: {
    status: 'Enabled'
    taskType: 'ComputeVmShutdownTask'
    dailyRecurrence: {
      time: '1900' // 7 PM shutdown
    }
    timeZoneId: 'Eastern Standard Time'
    targetResourceId: aksCluster.id
    notificationSettings: {
      status: 'Disabled'
    }
  }
  tags: {
    Environment: environmentName
    Purpose: 'CostOptimization'
  }
}

// Role assignments for AKS - now that service principal has User Access Administrator role
resource aksContainerRegistryPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: resourceGroup()
  name: guid(resourceGroup().id, 'aks-acr-pull', environmentName)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d') // AcrPull
    principalId: aksCluster.properties.identityProfile.kubeletidentity.objectId
    principalType: 'ServicePrincipal'
  }
}

// Outputs
output clusterName string = aksCluster.name
output clusterFqdn string = aksCluster.properties.fqdn
output principalId string = aksCluster.identity.principalId
output kubeletIdentityObjectId string = aksCluster.properties.identityProfile.kubeletidentity.objectId
output kubernetesVersion string = aksCluster.properties.kubernetesVersion
output nodeResourceGroup string = aksCluster.properties.nodeResourceGroup

// Cost information
output estimatedMonthlyCost string = environmentName == 'prod' ? '$200-400' : '$50-100'
output costOptimizationFeatures array = [
  'Auto-scaling with scale-to-zero (dev)'
  'Kubenet networking (vs Azure CNI)'
  'Basic load balancer (dev)'
  'Minimal OS disk (30GB)'
  'Cost-effective VM sizes (B2s for dev)'
  'Auto-shutdown scheduling (dev)'
  'Single node for system pool (dev)'
]