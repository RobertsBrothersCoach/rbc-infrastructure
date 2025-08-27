# Tour Bus Leasing - Dev Environment Entra ID Configuration

## Configuration Summary
**Date Created**: August 13, 2025  
**Environment**: Development (dev)  
**Tenant ID**: `2bf8eca0-5705-47f9-bad9-10a86ef58a19`

## Application Registration

| Property | Value |
|----------|-------|
| **Display Name** | Tour Bus Leasing Management DEV |
| **Application ID** | `5dfd53af-7a13-49c7-8bb2-fa329b619774` |
| **Object ID** | `74338103-dabe-4fa7-9abd-fb5f9ed37721` |
| **Service Principal ID** | `d48030ca-3de5-4e38-824e-6d07ad8b7a45` |
| **Identifier URI** | `api://5dfd53af-7a13-49c7-8bb2-fa329b619774` |

## Redirect URIs

### Web Platform
- `http://localhost:3000/auth/callback`
- `http://localhost:5173/auth/callback`

### SPA Platform (if configured)
- `http://localhost:3000`
- `http://localhost:5173`

## Security Groups Created

| Group Name | Purpose |
|------------|---------|
| `BusLeasing-Administrators-dev` | Full system access and administrative privileges |
| `BusLeasing-Managers-dev` | Management level access to all modules |
| `BusLeasing-CRM-Users-dev` | Access to CRM module for client management |
| `BusLeasing-Fleet-Managers-dev` | Access to fleet management and maintenance |
| `BusLeasing-Finance-Users-dev` | Access to financial and reporting modules |
| `BusLeasing-ReadOnly-Users-dev` | Read-only access to all modules |

## Key Vault Secrets

**Key Vault Name**: `clientacq-dev-kv-7r7omy`

| Secret Name | Description |
|-------------|-------------|
| `EntraId-ApplicationId-dev` | Application (Client) ID |
| `EntraId-ClientSecret-dev` | Client Secret (expires in 2 years) |
| `EntraId-TenantId-dev` | Azure AD Tenant ID |

## Next Steps

1. **Grant Admin Consent**
   - Go to Azure Portal > Azure Active Directory > App registrations
   - Select "Tour Bus Leasing Management DEV"
   - Navigate to API permissions
   - Click "Grant admin consent for rbccoach.com"

2. **Add Users to Security Groups**
   ```bash
   # Example: Add user to Administrators group
   az ad group member add --group "BusLeasing-Administrators-dev" --member-id <user-object-id>
   ```

3. **Configure Application Code**
   ```javascript
   // Frontend (React) - .env.development
   REACT_APP_CLIENT_ID=5dfd53af-7a13-49c7-8bb2-fa329b619774
   REACT_APP_TENANT_ID=2bf8eca0-5705-47f9-bad9-10a86ef58a19
   REACT_APP_REDIRECT_URI=http://localhost:3000/auth/callback
   
   // Backend (Node.js) - .env
   CLIENT_ID=5dfd53af-7a13-49c7-8bb2-fa329b619774
   TENANT_ID=2bf8eca0-5705-47f9-bad9-10a86ef58a19
   CLIENT_SECRET=<retrieve from Key Vault>
   ```

4. **Test Authentication**
   ```bash
   # Test the configuration
   cd infrastructure/entra-id
   pwsh ./Test-EntraIdConfiguration.ps1 `
     -ApplicationId "5dfd53af-7a13-49c7-8bb2-fa329b619774" `
     -TenantId "2bf8eca0-5705-47f9-bad9-10a86ef58a19" `
     -Environment dev `
     -KeyVaultName "clientacq-dev-kv-7r7omy"
   ```

## Security Notes

- Client secret is stored securely in Key Vault
- Secret expires in 2 years (needs rotation before expiry)
- All security groups are environment-specific (dev suffix)
- Single tenant configuration (AzureADMyOrg)

## Troubleshooting

If you encounter authentication issues:
1. Verify admin consent has been granted
2. Check redirect URIs match exactly
3. Ensure users are members of appropriate security groups
4. Verify Key Vault access permissions

## QA and Production Setup

To set up QA and Production environments later:
1. Run the same registration process with different environment parameters
2. Use appropriate redirect URIs for each environment
3. Create separate security groups with qa/prod suffixes
4. Store credentials in environment-specific Key Vaults