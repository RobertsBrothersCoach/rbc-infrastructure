# API Permissions and Scopes Configuration
Generated: 2025-08-13 12:11:27
Environment: dev
Application ID: 5dfd53af-7a13-49c7-8bb2-fa329b619774

## Microsoft Graph Permissions (Delegated)
| Permission | ID | Justification |
|------------|-----|---------------|
| User.Read | e1fe6dd8-ba31-4d61-89e7-88639da4683d | Read user profile for personalization |
| GroupMember.Read.All | 98830695-27a2-44f7-8c18-0c3ebc9698f6 | Determine user's security group memberships for RBAC |
| openid | 37f7f235-527c-4136-accd-4a02d197296e | Enable OpenID Connect authentication flow |
| profile | 14dad69e-099b-42c9-810b-d002981feec1 | Access user's basic profile information |
| email | 64a6cdd6-aab1-4aaf-94b8-3cc8405e90d0 | Access user's email for notifications |

## Custom OAuth2 Scopes
| Scope | Type | Description |
|-------|------|-------------|
| BusLeasing.Read | User | Read access to bus leasing data |
| BusLeasing.Write | User | Write access to bus leasing data |
| BusLeasing.Admin | Admin | Administrative access to all bus leasing functions |

## Usage Examples

### Frontend (MSAL.js)
\\\javascript
const loginRequest = {
    scopes: [
        "openid",
        "profile", 
        "User.Read",
        "GroupMember.Read.All",
        "api://5dfd53af-7a13-49c7-8bb2-fa329b619774/BusLeasing.Read",
        "api://5dfd53af-7a13-49c7-8bb2-fa329b619774/BusLeasing.Write"
    ]
};
\\\

### Backend (Token Validation)
\\\javascript
// Validate scope in JWT token
const requiredScope = 'BusLeasing.Write';
if (!token.scp.includes(requiredScope)) {
    return res.status(403).json({ error: 'Insufficient scope' });
}
\\\

## Next Steps
1. Grant admin consent in Azure Portal if not done automatically
2. Update application code to request appropriate scopes
3. Implement scope-based authorization in API endpoints
4. Test with different user accounts and permission levels
