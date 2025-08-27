# Grant Role Assignment Permissions to Service Principal
# This script grants the User Access Administrator role to the service principal
# so it can create role assignments during deployment

param(
    [Parameter(Mandatory=$false)]
    [string]$ServicePrincipalName = "rbc-leasing-app-sp",
    
    [Parameter(Mandatory=$false)]
    [string]$SubscriptionId = "",
    
    [Parameter(Mandatory=$false)]
    [ValidateSet("Subscription", "ResourceGroup")]
    [string]$Scope = "ResourceGroup",
    
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupName = "RBCLeasingApp-Qa"
)

Write-Host "Granting Role Assignment Permissions to Service Principal" -ForegroundColor Green
Write-Host "=========================================================" -ForegroundColor Green

# Check if logged in to Azure
$context = Get-AzContext
if (-not $context) {
    Write-Host "Not logged in to Azure. Please run 'Connect-AzAccount' first." -ForegroundColor Red
    exit 1
}

# Get or set subscription
if ($SubscriptionId) {
    Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
}
$currentSub = Get-AzContext
Write-Host "Using subscription: $($currentSub.Subscription.Name) ($($currentSub.Subscription.Id))" -ForegroundColor Cyan

# Get service principal
Write-Host "`nFinding service principal: $ServicePrincipalName" -ForegroundColor Yellow
$sp = Get-AzADServicePrincipal -DisplayName $ServicePrincipalName

if (-not $sp) {
    Write-Host "Service principal '$ServicePrincipalName' not found." -ForegroundColor Red
    Write-Host "Available service principals:" -ForegroundColor Yellow
    Get-AzADServicePrincipal | Where-Object { $_.DisplayName -like "*rbc*" -or $_.DisplayName -like "*leasing*" } | Format-Table DisplayName, Id
    exit 1
}

Write-Host "Found service principal: $($sp.DisplayName)" -ForegroundColor Green
Write-Host "  Object ID: $($sp.Id)" -ForegroundColor Gray
Write-Host "  Application ID: $($sp.AppId)" -ForegroundColor Gray

# Determine scope
if ($Scope -eq "Subscription") {
    $scopePath = "/subscriptions/$($currentSub.Subscription.Id)"
    Write-Host "`nScope: Subscription level" -ForegroundColor Cyan
} else {
    # Check if resource group exists
    $rg = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
    if (-not $rg) {
        Write-Host "Resource group '$ResourceGroupName' not found. Creating it..." -ForegroundColor Yellow
        $rg = New-AzResourceGroup -Name $ResourceGroupName -Location "eastus2"
    }
    $scopePath = "/subscriptions/$($currentSub.Subscription.Id)/resourceGroups/$ResourceGroupName"
    Write-Host "`nScope: Resource Group '$ResourceGroupName'" -ForegroundColor Cyan
}

# Check existing role assignments
Write-Host "`nChecking existing role assignments..." -ForegroundColor Yellow
$existingRoles = Get-AzRoleAssignment -ObjectId $sp.Id -Scope $scopePath -ErrorAction SilentlyContinue

if ($existingRoles) {
    Write-Host "Current roles:" -ForegroundColor Cyan
    $existingRoles | ForEach-Object {
        Write-Host "  - $($_.RoleDefinitionName)" -ForegroundColor Gray
    }
}

# Define roles to assign
# User Access Administrator allows creating role assignments
# Contributor allows creating and managing resources
$rolesToAssign = @(
    "User Access Administrator",
    "Contributor"
)

foreach ($roleName in $rolesToAssign) {
    $existingRole = $existingRoles | Where-Object { $_.RoleDefinitionName -eq $roleName }
    
    if ($existingRole) {
        Write-Host "`nRole '$roleName' already assigned - skipping" -ForegroundColor Yellow
    } else {
        Write-Host "`nAssigning role '$roleName'..." -ForegroundColor Yellow
        try {
            New-AzRoleAssignment `
                -ObjectId $sp.Id `
                -RoleDefinitionName $roleName `
                -Scope $scopePath `
                -ErrorAction Stop | Out-Null
            
            Write-Host "  ✓ Successfully assigned '$roleName' role" -ForegroundColor Green
        } catch {
            Write-Host "  ✗ Failed to assign '$roleName' role: $_" -ForegroundColor Red
            
            # If we cannot assign at resource group level, we need subscription level
            if ($Scope -eq "ResourceGroup" -and $_.Exception.Message -like "*does not have authorization*") {
                Write-Host "`nYou do not have permission to assign roles at the resource group level." -ForegroundColor Yellow
                Write-Host "You need to either:" -ForegroundColor Yellow
                Write-Host "  1. Run this script with Owner or User Access Administrator role" -ForegroundColor Gray
                Write-Host "  2. Ask an admin to run this script" -ForegroundColor Gray
                Write-Host "  3. Use Azure Portal to manually assign roles" -ForegroundColor Gray
            }
        }
    }
}

# Verify final permissions
Write-Host "`nVerifying final role assignments..." -ForegroundColor Yellow
$finalRoles = Get-AzRoleAssignment -ObjectId $sp.Id -Scope $scopePath -ErrorAction SilentlyContinue

if ($finalRoles) {
    Write-Host "Final roles assigned:" -ForegroundColor Green
    $finalRoles | ForEach-Object {
        Write-Host "  ✓ $($_.RoleDefinitionName) at $($_.Scope)" -ForegroundColor Gray
    }
} else {
    Write-Host "No roles found. There may have been an issue with assignment." -ForegroundColor Red
}

Write-Host "`n=========================================================" -ForegroundColor Green
Write-Host "Script completed!" -ForegroundColor Green
Write-Host "" -ForegroundColor Green
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Wait 1-2 minutes for permissions to propagate" -ForegroundColor Gray
Write-Host "  2. Re-run the GitHub Actions deployment workflow" -ForegroundColor Gray
Write-Host "  3. The deployment should now be able to create role assignments" -ForegroundColor Gray