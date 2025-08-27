# AKS Cluster Management Script for Dev Environment
# This script provides easy commands to start/stop the AKS cluster to save costs

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("start", "stop", "status", "costs")]
    [string]$Action
)

$ResourceGroup = "RBCLeasingApp-Dev"
$ClusterName = "aks-rbcleasing-dev"

function Show-Status {
    Write-Host "🔍 Checking AKS cluster status..." -ForegroundColor Cyan
    $powerState = az aks show --resource-group $ResourceGroup --name $ClusterName --query "powerState.code" --output tsv 2>$null
    
    if ($powerState -eq "Running") {
        Write-Host "✅ Cluster is RUNNING" -ForegroundColor Green
        Write-Host "💰 Cost: ~$2.40-3.60/day ($70-110/month)" -ForegroundColor Yellow
        
        # Show node count
        $nodeCount = az aks nodepool list --resource-group $ResourceGroup --cluster-name $ClusterName --query "[0].count" --output tsv 2>$null
        Write-Host "📊 Nodes: $nodeCount" -ForegroundColor Cyan
        
        # Show External IP
        Write-Host "`n🌐 Checking Load Balancer IP..." -ForegroundColor Cyan
        kubectl get service ingress-nginx-controller -n ingress-nginx 2>$null | Select-String "ingress-nginx"
    }
    elseif ($powerState -eq "Stopped") {
        Write-Host "⏹️ Cluster is STOPPED" -ForegroundColor Yellow
        Write-Host "💰 Cost: ~$0.20/day (only storage)" -ForegroundColor Green
    }
    else {
        Write-Host "⚠️ Cluster state: $powerState" -ForegroundColor Red
    }
}

function Start-Cluster {
    Write-Host "🚀 Starting AKS cluster..." -ForegroundColor Green
    Write-Host "This will take 3-5 minutes" -ForegroundColor Yellow
    
    az aks start --resource-group $ResourceGroup --name $ClusterName
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Cluster started successfully!" -ForegroundColor Green
        
        # Update kubectl context
        Write-Host "🔧 Updating kubectl credentials..." -ForegroundColor Cyan
        az aks get-credentials --resource-group $ResourceGroup --name $ClusterName --admin --overwrite-existing
        
        # Wait for services
        Write-Host "⏳ Waiting for services to be ready..." -ForegroundColor Yellow
        Start-Sleep -Seconds 30
        
        # Show status
        Show-Status
        
        Write-Host "`n📝 Next steps:" -ForegroundColor Cyan
        Write-Host "  1. Services will take 2-3 minutes to fully initialize"
        Write-Host "  2. External IP: 4.150.124.192"
        Write-Host "  3. ArgoCD: https://argocd-dev.cloud.rbccoach.com"
        Write-Host "  4. Local access: kubectl port-forward svc/argocd-server -n argocd 8080:443"
    }
    else {
        Write-Host "❌ Failed to start cluster" -ForegroundColor Red
    }
}

function Stop-Cluster {
    Write-Host "⏹️ Stopping AKS cluster..." -ForegroundColor Yellow
    Write-Host "This will save ~$2.40-3.60 per day" -ForegroundColor Green
    
    az aks stop --resource-group $ResourceGroup --name $ClusterName
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Cluster stopped successfully!" -ForegroundColor Green
        Write-Host "💰 Daily cost reduced to ~$0.20 (storage only)" -ForegroundColor Green
        Write-Host "`n📝 To restart: .\scripts\aks-management.ps1 start" -ForegroundColor Cyan
    }
    else {
        Write-Host "❌ Failed to stop cluster" -ForegroundColor Red
    }
}

function Show-Costs {
    Write-Host "💰 AKS Dev Environment Cost Breakdown" -ForegroundColor Cyan
    Write-Host "=====================================" -ForegroundColor Cyan
    
    $powerState = az aks show --resource-group $ResourceGroup --name $ClusterName --query "powerState.code" --output tsv 2>$null
    
    Write-Host "`nCurrent State: $powerState" -ForegroundColor Yellow
    
    Write-Host "`nWhen RUNNING:" -ForegroundColor Green
    Write-Host "  • Compute (1-3 B2s nodes): $1.50-4.50/day"
    Write-Host "  • Load Balancer (Standard): $0.83/day"
    Write-Host "  • Storage (30GB OS disk): $0.14/day"
    Write-Host "  • Total: ~$2.40-3.60/day ($70-110/month)"
    
    Write-Host "`nWhen STOPPED:" -ForegroundColor Yellow
    Write-Host "  • Compute: $0"
    Write-Host "  • Load Balancer: $0"
    Write-Host "  • Storage (preserved): $0.14/day"
    Write-Host "  • Total: ~$0.20/day ($6/month)"
    
    Write-Host "`n💡 Recommendations:" -ForegroundColor Cyan
    Write-Host "  • Stop cluster when not in use (nights/weekends)"
    Write-Host "  • Start only when actively developing"
    Write-Host "  • Consider scheduling automatic stop at 6 PM"
    
    if ($powerState -eq "Running") {
        Write-Host "`n⚠️ Cluster is currently RUNNING and incurring charges" -ForegroundColor Red
        Write-Host "Stop it with: .\scripts\aks-management.ps1 stop" -ForegroundColor Yellow
    }
}

# Main execution
switch ($Action) {
    "start"  { Start-Cluster }
    "stop"   { Stop-Cluster }
    "status" { Show-Status }
    "costs"  { Show-Costs }
}