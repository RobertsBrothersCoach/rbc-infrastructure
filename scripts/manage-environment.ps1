param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('dev', 'staging', 'prod')]
    [string]$Environment,
    
    [Parameter(Mandatory=$true)]
    [ValidateSet('start', 'stop', 'status')]
    [string]$Action
)

# Environment configuration
$config = @{
    'dev' = @{
        ResourceGroup = 'RBCLeasingApp-Dev'
        AksCluster = 'aks-rbc-dev'
        PostgreSQL = 'psql-rbcleasing-dev'
        AppService = 'app-rbc-dev'
        AllowShutdown = $true
    }
    'staging' = @{
        ResourceGroup = 'RBCLeasingApp-Staging'
        AksCluster = 'aks-rbc-staging'
        PostgreSQL = 'psql-rbcleasing-staging'
        AppService = 'app-rbc-staging'
        AllowShutdown = $true
    }
    'prod' = @{
        ResourceGroup = 'RBCLeasingApp-Prod'
        AksCluster = 'aks-rbc-prod'
        PostgreSQL = 'psql-rbcleasing-prod'
        AppService = 'app-rbc-prod'
        AllowShutdown = $false
    }
}

$env = $config[$Environment]

# Check if production shutdown is attempted
if ($Environment -eq 'prod' -and $Action -eq 'stop') {
    Write-Host "❌ ERROR: Production environment cannot be shut down!" -ForegroundColor Red
    Write-Host "   Production must remain available 24/7" -ForegroundColor Yellow
    exit 1
}

Write-Host "🔧 Environment: $Environment" -ForegroundColor Cyan
Write-Host "🎯 Action: $Action" -ForegroundColor Cyan
Write-Host ""

switch ($Action) {
    'stop' {
        Write-Host "⏸️  Stopping $Environment environment..." -ForegroundColor Yellow
        Write-Host ""
        
        # Stop AKS Cluster
        Write-Host "  Stopping AKS cluster..." -ForegroundColor White
        az aks stop `
            --resource-group $env.ResourceGroup `
            --name $env.AksCluster `
            --no-wait
        
        # Stop PostgreSQL
        Write-Host "  Stopping PostgreSQL server..." -ForegroundColor White
        az postgres flexible-server stop `
            --resource-group $env.ResourceGroup `
            --name $env.PostgreSQL `
            --no-wait
        
        # Stop App Service (if exists)
        Write-Host "  Stopping App Service..." -ForegroundColor White
        az webapp stop `
            --resource-group $env.ResourceGroup `
            --name $env.AppService 2>$null
        
        Write-Host ""
        Write-Host "✅ Shutdown initiated for $Environment environment" -ForegroundColor Green
        Write-Host "   Resources will stop in the next few minutes" -ForegroundColor Gray
        Write-Host ""
        Write-Host "💰 Estimated savings:" -ForegroundColor Cyan
        if ($Environment -eq 'dev') {
            Write-Host "   ~$25/day when stopped" -ForegroundColor Green
        } else {
            Write-Host "   ~$40/day when stopped" -ForegroundColor Green
        }
    }
    
    'start' {
        Write-Host "▶️  Starting $Environment environment..." -ForegroundColor Yellow
        Write-Host ""
        
        # Start PostgreSQL (must start before AKS)
        Write-Host "  Starting PostgreSQL server..." -ForegroundColor White
        az postgres flexible-server start `
            --resource-group $env.ResourceGroup `
            --name $env.PostgreSQL
        
        # Start AKS Cluster
        Write-Host "  Starting AKS cluster..." -ForegroundColor White
        az aks start `
            --resource-group $env.ResourceGroup `
            --name $env.AksCluster `
            --no-wait
        
        # Start App Service (if exists)
        Write-Host "  Starting App Service..." -ForegroundColor White
        az webapp start `
            --resource-group $env.ResourceGroup `
            --name $env.AppService 2>$null
        
        Write-Host ""
        Write-Host "✅ Startup initiated for $Environment environment" -ForegroundColor Green
        Write-Host "   Resources will be available in 5-10 minutes" -ForegroundColor Gray
    }
    
    'status' {
        Write-Host "📊 Checking $Environment environment status..." -ForegroundColor Yellow
        Write-Host ""
        
        # Check AKS status
        $aksStatus = az aks show `
            --resource-group $env.ResourceGroup `
            --name $env.AksCluster `
            --query powerState.code `
            --output tsv 2>$null
        
        if ($aksStatus -eq 'Running') {
            Write-Host "  ✅ AKS Cluster: Running" -ForegroundColor Green
        } elseif ($aksStatus -eq 'Stopped') {
            Write-Host "  ⏸️  AKS Cluster: Stopped" -ForegroundColor Yellow
        } else {
            Write-Host "  ❓ AKS Cluster: $aksStatus" -ForegroundColor Gray
        }
        
        # Check PostgreSQL status
        $pgStatus = az postgres flexible-server show `
            --resource-group $env.ResourceGroup `
            --name $env.PostgreSQL `
            --query state `
            --output tsv 2>$null
        
        if ($pgStatus -eq 'Ready') {
            Write-Host "  ✅ PostgreSQL: Running" -ForegroundColor Green
        } elseif ($pgStatus -eq 'Stopped') {
            Write-Host "  ⏸️  PostgreSQL: Stopped" -ForegroundColor Yellow
        } else {
            Write-Host "  ❓ PostgreSQL: $pgStatus" -ForegroundColor Gray
        }
        
        # Check App Service status
        $appStatus = az webapp show `
            --resource-group $env.ResourceGroup `
            --name $env.AppService `
            --query state `
            --output tsv 2>$null
        
        if ($appStatus -eq 'Running') {
            Write-Host "  ✅ App Service: Running" -ForegroundColor Green
        } elseif ($appStatus -eq 'Stopped') {
            Write-Host "  ⏸️  App Service: Stopped" -ForegroundColor Yellow
        } else {
            Write-Host "  ❓ App Service: Not deployed or $appStatus" -ForegroundColor Gray
        }
        
        Write-Host ""
        
        # Show cost estimate
        if ($aksStatus -eq 'Running' -or $pgStatus -eq 'Ready') {
            Write-Host "💵 Estimated daily cost: " -NoNewline
            if ($Environment -eq 'dev') {
                Write-Host "~$27/day" -ForegroundColor Yellow
            } elseif ($Environment -eq 'staging') {
                Write-Host "~$40/day" -ForegroundColor Yellow
            } else {
                Write-Host "~$115/day" -ForegroundColor Yellow
            }
        } else {
            Write-Host "💰 Resources are stopped - minimal costs" -ForegroundColor Green
        }
    }
}

Write-Host ""
Write-Host "📝 Auto-shutdown schedule:" -ForegroundColor Cyan
if ($Environment -eq 'dev') {
    Write-Host "   Mon-Fri: Auto-stops at 7 PM, starts at 7 AM" -ForegroundColor Gray
    Write-Host "   Weekends: Stopped all day" -ForegroundColor Gray
} elseif ($Environment -eq 'staging') {
    Write-Host "   Daily: Auto-stops at 10 PM, starts at 6 AM" -ForegroundColor Gray
} else {
    Write-Host "   Production is always on (24/7)" -ForegroundColor Gray
}