#!/bin/bash

# AKS Cluster Management Script for Dev Environment
# This script provides easy commands to start/stop the AKS cluster to save costs

RESOURCE_GROUP="RBCLeasingApp-Dev"
CLUSTER_NAME="aks-rbcleasing-dev"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

show_status() {
    echo -e "${CYAN}🔍 Checking AKS cluster status...${NC}"
    POWER_STATE=$(az aks show --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" --query "powerState.code" --output tsv 2>/dev/null)
    
    if [ "$POWER_STATE" == "Running" ]; then
        echo -e "${GREEN}✅ Cluster is RUNNING${NC}"
        echo -e "${YELLOW}💰 Cost: ~\$2.40-3.60/day (\$70-110/month)${NC}"
        
        # Show node count
        NODE_COUNT=$(az aks nodepool list --resource-group "$RESOURCE_GROUP" --cluster-name "$CLUSTER_NAME" --query "[0].count" --output tsv 2>/dev/null)
        echo -e "${CYAN}📊 Nodes: $NODE_COUNT${NC}"
        
        # Show External IP
        echo -e "\n${CYAN}🌐 Checking Load Balancer IP...${NC}"
        kubectl get service ingress-nginx-controller -n ingress-nginx 2>/dev/null | grep ingress-nginx || echo "kubectl not configured"
    elif [ "$POWER_STATE" == "Stopped" ]; then
        echo -e "${YELLOW}⏹️ Cluster is STOPPED${NC}"
        echo -e "${GREEN}💰 Cost: ~\$0.20/day (only storage)${NC}"
    else
        echo -e "${RED}⚠️ Cluster state: $POWER_STATE${NC}"
    fi
}

start_cluster() {
    echo -e "${GREEN}🚀 Starting AKS cluster...${NC}"
    echo -e "${YELLOW}This will take 3-5 minutes${NC}"
    
    az aks start --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Cluster started successfully!${NC}"
        
        # Update kubectl context
        echo -e "${CYAN}🔧 Updating kubectl credentials...${NC}"
        az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" --admin --overwrite-existing
        
        # Wait for services
        echo -e "${YELLOW}⏳ Waiting for services to be ready...${NC}"
        sleep 30
        
        # Show status
        show_status
        
        echo -e "\n${CYAN}📝 Next steps:${NC}"
        echo "  1. Services will take 2-3 minutes to fully initialize"
        echo "  2. External IP: 4.150.124.192"
        echo "  3. ArgoCD: https://argocd-dev.cloud.rbccoach.com"
        echo "  4. Local access: kubectl port-forward svc/argocd-server -n argocd 8080:443"
    else
        echo -e "${RED}❌ Failed to start cluster${NC}"
    fi
}

stop_cluster() {
    echo -e "${YELLOW}⏹️ Stopping AKS cluster...${NC}"
    echo -e "${GREEN}This will save ~\$2.40-3.60 per day${NC}"
    
    az aks stop --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Cluster stopped successfully!${NC}"
        echo -e "${GREEN}💰 Daily cost reduced to ~\$0.20 (storage only)${NC}"
        echo -e "\n${CYAN}📝 To restart: ./scripts/aks-management.sh start${NC}"
    else
        echo -e "${RED}❌ Failed to stop cluster${NC}"
    fi
}

show_costs() {
    echo -e "${CYAN}💰 AKS Dev Environment Cost Breakdown"
    echo "====================================="
    
    POWER_STATE=$(az aks show --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" --query "powerState.code" --output tsv 2>/dev/null)
    
    echo -e "\n${YELLOW}Current State: $POWER_STATE${NC}"
    
    echo -e "\n${GREEN}When RUNNING:${NC}"
    echo "  • Compute (1-3 B2s nodes): \$1.50-4.50/day"
    echo "  • Load Balancer (Standard): \$0.83/day"
    echo "  • Storage (30GB OS disk): \$0.14/day"
    echo "  • Total: ~\$2.40-3.60/day (\$70-110/month)"
    
    echo -e "\n${YELLOW}When STOPPED:${NC}"
    echo "  • Compute: \$0"
    echo "  • Load Balancer: \$0"
    echo "  • Storage (preserved): \$0.14/day"
    echo "  • Total: ~\$0.20/day (\$6/month)"
    
    echo -e "\n${CYAN}💡 Recommendations:${NC}"
    echo "  • Stop cluster when not in use (nights/weekends)"
    echo "  • Start only when actively developing"
    echo "  • Consider scheduling automatic stop at 6 PM"
    
    if [ "$POWER_STATE" == "Running" ]; then
        echo -e "\n${RED}⚠️ Cluster is currently RUNNING and incurring charges${NC}"
        echo -e "${YELLOW}Stop it with: ./scripts/aks-management.sh stop${NC}"
    fi
}

# Main execution
case "$1" in
    start)
        start_cluster
        ;;
    stop)
        stop_cluster
        ;;
    status)
        show_status
        ;;
    costs)
        show_costs
        ;;
    *)
        echo -e "${CYAN}Usage: $0 {start|stop|status|costs}${NC}"
        echo ""
        echo "Commands:"
        echo "  start  - Start the AKS cluster"
        echo "  stop   - Stop the AKS cluster (saves costs)"
        echo "  status - Show current cluster status"
        echo "  costs  - Show detailed cost breakdown"
        exit 1
        ;;
esac