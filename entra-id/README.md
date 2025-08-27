# Azure Entra ID Infrastructure Setup

This directory contains all the infrastructure code and scripts needed to configure Azure Entra ID (formerly Azure Active Directory) authentication for the Tour Bus Leasing application.

## Overview

The Entra ID setup provides:
- Single Sign-On (SSO) authentication
- Role-Based Access Control (RBAC)
- Security group management
- Multi-environment support (dev, qa, prod)
- Secure credential storage in Key Vault

## Prerequisites

- Azure subscription with appropriate permissions
- Azure CLI installed and configured
- PowerShell 7+ with Az modules
- Key Vault already provisioned
- Global Administrator or Application Administrator role in Azure AD

## Quick Start

### 1. Register the Application

```powershell
# For development environment
.\Register-EntraIdApplication.ps1 `
  -Environment dev `
  -TenantId "your-tenant-id" `
  -KeyVaultName "kv-tourbus-dev" `
  -CreateSecurityGroups

# For QA environment
.\Register-EntraIdApplication.ps1 `
  -Environment qa `
  -TenantId "your-tenant-id" `
  -KeyVaultName "kv-tourbus-qa" `
  -CreateSecurityGroups

# For production environment
.\Register-EntraIdApplication.ps1 `
  -Environment prod `
  -TenantId "your-tenant-id" `
  -KeyVaultName "kv-tourbus-prod" `
  -CreateSecurityGroups
```

### 2. Configure Security Groups

```powershell
# Configure groups and assign users
.\Configure-SecurityGroups.ps1 `
  -Environment dev `
  -ApplicationId "your-app-id" `
  -AssignAppRoles

# Import users from CSV
.\Configure-SecurityGroups.ps1 `
  -Environment prod `
  -ApplicationId "your-app-id" `
  -ImportUsersFromCsv "users.csv" `
  -AssignAppRoles
```

### 3. Deploy Key Vault Secrets

```bash
# Deploy secrets using Bicep
az deployment group create \
  --resource-group rg-tourbus-dev \
  --template-file key-vault-secrets.bicep \
  --parameters \
    keyVaultName=kv-tourbus-dev \
    environmentName=dev \
    applicationId=$APP_ID \
    clientSecret=$CLIENT_SECRET \
    tenantId=$TENANT_ID
```

## Application Configuration

### Redirect URIs

| Environment | Redirect URIs |
|------------|--------------|
| **Development** | - `http://localhost:3000/auth/callback`<br>- `http://localhost:5173/auth/callback` |
| **QA** | - `https://qa-tourbus.azurewebsites.net/auth/callback`<br>- `https://qa-tourbus.azurecontainerapps.io/auth/callback` |
| **Production** | - `https://tourbus.azurewebsites.net/auth/callback`<br>- `https://tourbus.azurecontainerapps.io/auth/callback`<br>- `https://www.tourbus-leasing.com/auth/callback` |

### API Permissions

The application requests the following Microsoft Graph permissions:

| Permission | Type | Description |
|------------|------|-------------|
| `User.Read` | Delegated | Read user profile |
| `GroupMember.Read.All` | Delegated | Read group memberships |
| `openid` | Delegated | Sign in and read user profile |
| `profile` | Delegated | Read user's basic profile |
| `email` | Delegated | Read user's email address |

### Application Roles

| Role | Description | Access Level |
|------|-------------|--------------|
| **Administrator** | Full system access and administrative privileges | Full CRUD on all modules |
| **Manager** | Management level access to all modules | Full access except system config |
| **CRM User** | Access to CRM module for client management | CRM module only |
| **Fleet Manager** | Access to fleet management and maintenance | Fleet and maintenance modules |
| **Finance User** | Access to financial and reporting modules | Finance and reports |
| **Read Only User** | Read-only access to all modules | View only |

## Security Groups

Security groups are created with the following naming convention:
- `BusLeasing-{Role}-{Environment}`

Example: `BusLeasing-Administrators-dev`

### Group Structure

```
BusLeasing-Administrators-{env}
├── Full system access
├── Can manage other users
└── Access to all configuration

BusLeasing-Managers-{env}
├── Management features
├── Approve bookings
└── Generate reports

BusLeasing-CRM-Users-{env}
├── Customer management
├── Booking creation
└── Customer communications

BusLeasing-Fleet-Managers-{env}
├── Fleet inventory
├── Maintenance schedules
└── Vehicle assignments

BusLeasing-Finance-Users-{env}
├── Financial reports
├── Invoice management
└── Payment processing

BusLeasing-ReadOnly-Users-{env}
├── View all data
├── No modification rights
└── Reporting access
```

## Key Vault Secrets

The following secrets are stored in Key Vault:

| Secret Name | Description |
|-------------|-------------|
| `EntraId-ApplicationId` | Application (client) ID |
| `EntraId-ClientSecret` | Client secret for authentication |
| `EntraId-TenantId` | Azure AD tenant ID |
| `EntraId-Authority` | Authority URL for authentication |
| `EntraId-RedirectUri` | Primary redirect URI |
| `EntraId-ApiScope` | API scope for token requests |

## Application Integration

### Frontend Configuration (React)

```javascript
// authConfig.js
export const msalConfig = {
  auth: {
    clientId: process.env.REACT_APP_CLIENT_ID,
    authority: `https://login.microsoftonline.com/${process.env.REACT_APP_TENANT_ID}`,
    redirectUri: process.env.REACT_APP_REDIRECT_URI
  }
};

export const loginRequest = {
  scopes: ["User.Read", "GroupMember.Read.All"]
};
```

### Backend Configuration (Node.js)

```javascript
// auth.config.js
module.exports = {
  credentials: {
    tenantID: process.env.TENANT_ID,
    clientID: process.env.CLIENT_ID,
    clientSecret: process.env.CLIENT_SECRET
  },
  resource: {
    scope: ["api://tourbus-{env}/.default"]
  },
  metadata: {
    authority: "login.microsoftonline.com",
    discovery: ".well-known/openid-configuration",
    version: "v2.0"
  }
};
```

## Manual Steps Required

After running the scripts, complete these manual steps:

1. **Grant Admin Consent**
   - Navigate to Azure Portal > Azure Active Directory
   - Go to App registrations > Your app > API permissions
   - Click "Grant admin consent for {tenant}"

2. **Configure Conditional Access (Optional)**
   - Set up MFA requirements
   - Configure trusted locations
   - Set device compliance policies

3. **Test Authentication**
   - Use the Azure AD test feature in the portal
   - Verify token acquisition
   - Test role assignments

## Troubleshooting

### Common Issues

1. **"Insufficient privileges" error**
   - Ensure you have Application Administrator or Global Administrator role
   - Check Azure AD permissions

2. **"App registration already exists"**
   - Use the `-UpdateExisting` flag
   - Or manually delete the existing registration

3. **Key Vault access denied**
   - Verify Key Vault access policies
   - Ensure your account has Secret management permissions

4. **Group creation fails**
   - Check if groups already exist
   - Verify you have Group Administrator permissions

### Validation Checklist

- [ ] Application registered in Azure AD
- [ ] Client secret generated and stored
- [ ] Redirect URIs configured for all environments
- [ ] API permissions configured and admin consent granted
- [ ] Security groups created
- [ ] Users assigned to appropriate groups
- [ ] App roles configured and assigned
- [ ] Secrets stored in Key Vault
- [ ] Test authentication successful

## Security Best Practices

1. **Rotate Secrets Regularly**
   - Client secrets expire after 2 years
   - Set up alerts 30 days before expiration
   - Use certificate authentication for production

2. **Principle of Least Privilege**
   - Grant only necessary permissions
   - Use app roles for fine-grained access control
   - Regular access reviews

3. **Monitor and Audit**
   - Enable Azure AD sign-in logs
   - Set up alerts for suspicious activities
   - Regular security group membership reviews

4. **Secure Development**
   - Never commit secrets to source control
   - Use Key Vault references in App Service
   - Enable managed identities where possible

## Files in This Directory

| File | Description |
|------|-------------|
| `app-registration.bicep` | Bicep template documenting app registration configuration |
| `Register-EntraIdApplication.ps1` | PowerShell script to register and configure the application |
| `Configure-SecurityGroups.ps1` | PowerShell script to create and manage security groups |
| `key-vault-secrets.bicep` | Bicep template to store secrets in Key Vault |
| `README.md` | This documentation file |

## Support

For issues or questions:
1. Check the troubleshooting section above
2. Review Azure AD audit logs
3. Contact the infrastructure team
4. Open an issue in the repository

## Next Steps

After completing the Entra ID setup:
1. Configure the application code with authentication
2. Implement authorization middleware
3. Set up token validation
4. Configure refresh token handling
5. Implement logout functionality

## References

- [Azure AD Documentation](https://docs.microsoft.com/en-us/azure/active-directory/)
- [MSAL.js Documentation](https://docs.microsoft.com/en-us/azure/active-directory/develop/msal-js-overview)
- [App Registration Best Practices](https://docs.microsoft.com/en-us/azure/active-directory/develop/identity-platform-integration-checklist)
- [Security Best Practices](https://docs.microsoft.com/en-us/azure/active-directory/develop/identity-platform-security-best-practices)