# API Permissions and Scopes Documentation

## Overview

This document provides comprehensive documentation for all API permissions and custom scopes configured for the Tour Bus Leasing application's Azure Entra ID integration.

## Microsoft Graph API Permissions

### Delegated Permissions (User Context)

| Permission | Permission ID | Type | Admin Consent Required | Justification |
|------------|--------------|------|----------------------|---------------|
| **User.Read** | `e1fe6dd8-ba31-4d61-89e7-88639da4683d` | Delegated | No | Allows the app to read the signed-in user's profile. Used for displaying user information in the application UI and personalizing the user experience. |
| **GroupMember.Read.All** | `98830695-27a2-44f7-8c18-0c3ebc9698f6` | Delegated | Yes | Allows the app to read group memberships of the signed-in user. Critical for RBAC implementation to determine user's security groups and associated permissions. |
| **openid** | `37f7f235-527c-4136-accd-4a02d197296e` | Delegated | No | Required for OpenID Connect authentication flow. Enables single sign-on (SSO) functionality. |
| **profile** | `14dad69e-099b-42c9-810b-d002981feec1` | Delegated | No | Allows access to user's basic profile information (name, photo, etc.). Used for user identification within the application. |
| **email** | `64a6cdd6-aab1-4aaf-94b8-3cc8405e90d0` | Delegated | No | Allows the app to read the user's primary email address. Used for notifications and communication features. |

## Custom OAuth2 Scopes

### Application-Specific Permissions

| Scope | Display Name | Type | Description | Use Case |
|-------|--------------|------|-------------|----------|
| **BusLeasing.Read** | Read bus leasing data | User | Grants read access to bus leasing data including fleet information, bookings, and basic customer data | Standard users, read-only users, and all roles requiring data viewing capabilities |
| **BusLeasing.Write** | Write bus leasing data | User | Grants create and update permissions for bus leasing data including creating bookings, updating fleet status, and modifying customer records | CRM users, Fleet managers, and roles requiring data modification |
| **BusLeasing.Admin** | Administer bus leasing data | Admin | Grants full administrative access including delete operations, system configuration, and user management | Administrators and system managers only |

## Permission Matrix by Role

| Security Group | Graph Permissions | Custom Scopes | Effective Access |
|----------------|------------------|---------------|------------------|
| **BusLeasing-Administrators** | All | BusLeasing.Read, BusLeasing.Write, BusLeasing.Admin | Full system access |
| **BusLeasing-Managers** | All | BusLeasing.Read, BusLeasing.Write | Read/write access to all modules except admin functions |
| **BusLeasing-CRM-Users** | User.Read, GroupMember.Read.All | BusLeasing.Read, BusLeasing.Write | Customer and booking management |
| **BusLeasing-Fleet-Managers** | User.Read, GroupMember.Read.All | BusLeasing.Read, BusLeasing.Write | Fleet and maintenance management |
| **BusLeasing-Finance-Users** | User.Read, GroupMember.Read.All | BusLeasing.Read | Financial data and reporting (read-only) |
| **BusLeasing-ReadOnly-Users** | User.Read, GroupMember.Read.All | BusLeasing.Read | View-only access to all modules |

## Implementation Guide

### Frontend (React with MSAL)

```javascript
// authConfig.js
export const loginRequest = {
    scopes: [
        "openid",
        "profile",
        "User.Read",
        "GroupMember.Read.All",
        `api://${msalConfig.auth.clientId}/BusLeasing.Read`
    ]
};

// For write operations
export const writeRequest = {
    scopes: [
        ...loginRequest.scopes,
        `api://${msalConfig.auth.clientId}/BusLeasing.Write`
    ]
};

// For admin operations
export const adminRequest = {
    scopes: [
        ...writeRequest.scopes,
        `api://${msalConfig.auth.clientId}/BusLeasing.Admin`
    ]
};
```

### Backend (Node.js/Express)

```javascript
// middleware/scopeValidator.js
const requireScope = (requiredScope) => {
    return (req, res, next) => {
        const token = req.authInfo;
        
        // Check if token contains required scope
        if (!token.scp || !token.scp.includes(requiredScope)) {
            return res.status(403).json({
                error: 'Insufficient scope',
                required: requiredScope,
                provided: token.scp || []
            });
        }
        
        next();
    };
};

// Usage in routes
app.get('/api/buses', 
    validateJWT, 
    requireScope('BusLeasing.Read'), 
    getBuses
);

app.post('/api/buses', 
    validateJWT, 
    requireScope('BusLeasing.Write'), 
    createBus
);

app.delete('/api/buses/:id', 
    validateJWT, 
    requireScope('BusLeasing.Admin'), 
    deleteBus
);
```

## Configuration Steps

### 1. Configure Scopes in Azure Portal

1. Navigate to Azure Portal → Azure Active Directory → App registrations
2. Select your application (Tour Bus Leasing Management)
3. Go to "Expose an API"
4. Add scope with Application ID URI: `api://{application-id}`
5. Add each custom scope with appropriate admin and user consent descriptions

### 2. Grant Admin Consent

```powershell
# Using Azure CLI
az ad app permission admin-consent --id {application-id}

# Or in Azure Portal
# Navigate to API permissions → Grant admin consent for {tenant}
```

### 3. Configure Pre-authorized Applications

For trusted first-party applications:

```powershell
# Add pre-authorized client applications
az ad app update --id {application-id} --set api.preAuthorizedApplications='[
    {
        "appId": "{client-application-id}",
        "delegatedPermissionIds": ["{scope-ids}"]
    }
]'
```

## Security Considerations

### Principle of Least Privilege

- Users should only be granted the minimum scopes necessary for their role
- Use incremental consent to request additional permissions as needed
- Regularly audit scope usage and remove unnecessary permissions

### Token Security

- Access tokens containing scopes expire after 1 hour by default
- Refresh tokens should be stored securely (encrypted at rest)
- Implement token validation on every API request

### Audit and Monitoring

```javascript
// Log scope usage for audit purposes
const auditScopeUsage = (req, res, next) => {
    const { scp, oid, name } = req.authInfo;
    
    console.log({
        timestamp: new Date().toISOString(),
        userId: oid,
        userName: name,
        scopes: scp,
        endpoint: req.path,
        method: req.method
    });
    
    next();
};
```

## Testing Permissions

### Manual Testing

1. **Test User Creation**: Create test users in each security group
2. **Scope Request**: Use the test application to request different scope combinations
3. **API Validation**: Verify that API endpoints correctly enforce scope requirements

### Automated Testing

```powershell
# Run the permission test script
.\Test-ApiPermissions.ps1 `
    -ApplicationId "{app-id}" `
    -TenantId "{tenant-id}" `
    -TestUserEmail "testuser@domain.com"
```

## Troubleshooting

### Common Issues

| Issue | Cause | Resolution |
|-------|-------|------------|
| "Invalid scope" error | Scope not configured in app registration | Add scope in "Expose an API" section |
| "Consent required" error | Admin consent not granted | Grant admin consent in Azure Portal |
| "Insufficient privileges" error | User missing required scope | Check user's group membership and scope assignment |
| Token doesn't contain scopes | Wrong token type or audience | Ensure requesting access token for correct resource |

### Debug Checklist

- [ ] Verify application ID and tenant ID are correct
- [ ] Check that all scopes are enabled in app registration
- [ ] Confirm admin consent has been granted
- [ ] Validate token contains expected scopes (decode at jwt.ms)
- [ ] Ensure user is member of appropriate security group
- [ ] Check API is validating scopes correctly

## Compliance and Governance

### Regular Reviews

- **Quarterly**: Review and audit API permissions usage
- **Annually**: Reassess permission requirements based on role changes
- **On-demand**: Update permissions for new features or role modifications

### Documentation Requirements

- Maintain justification for each permission
- Document any changes to permission configuration
- Keep audit logs of permission-related incidents

## References

- [Microsoft Graph Permissions Reference](https://docs.microsoft.com/en-us/graph/permissions-reference)
- [OAuth 2.0 Scopes for Azure AD](https://docs.microsoft.com/en-us/azure/active-directory/develop/v2-permissions-and-consent)
- [Best Practices for Least Privilege](https://docs.microsoft.com/en-us/azure/active-directory/develop/secure-least-privileged-access)