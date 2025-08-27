# RBC Leasing Application - Infrastructure Requirements

This document contains all the application-specific information needed for infrastructure configuration and deployment.

## Application Architecture

### Frontend Application
- **Framework**: React 19 with TypeScript
- **Build Tool**: Vite
- **Port**: 5173 (development), 80 (production)
- **Container**: nginx:alpine
- **Static Assets**: Served from /dist directory

### Backend Application
- **Framework**: Node.js 18 with Express
- **Port**: 5000
- **Database**: PostgreSQL 15
- **Cache**: Redis (optional)
- **ORM**: Sequelize

## Environment Variables Required

### Frontend Environment Variables
```env
# Required
VITE_API_URL=http://localhost:5000/api  # Backend API URL
VITE_AZURE_AD_CLIENT_ID=                 # Azure AD Application ID
VITE_AZURE_AD_TENANT_ID=                 # Azure AD Tenant ID
VITE_AZURE_AD_REDIRECT_URI=              # OAuth redirect URI

# Optional
VITE_ENABLE_ANALYTICS=false              # Enable analytics
VITE_LOG_LEVEL=info                      # Logging level
```

### Backend Environment Variables
```env
# Database Configuration
DB_HOST=localhost
DB_PORT=5432
DB_USER=postgres
DB_PASSWORD=
DB_NAME=rbc_leasing

# Application Configuration
NODE_ENV=development
PORT=5000
JWT_SECRET=                               # JWT signing secret

# Azure AD Configuration
AZURE_AD_TENANT_ID=                      # Same as frontend
AZURE_AD_CLIENT_ID=                      # Same as frontend
AZURE_AD_CLIENT_SECRET=                  # Application secret

# Redis Configuration (Optional)
REDIS_URL=redis://localhost:6379
REDIS_PASSWORD=

# Email Configuration (Optional)
SMTP_HOST=
SMTP_PORT=587
SMTP_USER=
SMTP_PASSWORD=
EMAIL_FROM=noreply@rbcleasing.com

# SMS Configuration (Optional)
TWILIO_ACCOUNT_SID=
TWILIO_AUTH_TOKEN=
TWILIO_PHONE_NUMBER=
```

## Container Registry Configuration

### Images to Build
```yaml
Frontend:
  context: ./client
  dockerfile: ./client/Dockerfile
  image: rbcleasing/frontend:${VERSION}
  
Backend:
  context: ./server
  dockerfile: ./server/Dockerfile
  image: rbcleasing/backend:${VERSION}
```

## Database Schema Requirements

### PostgreSQL Database
- **Version**: 15+
- **Extensions Required**:
  - uuid-ossp
  - pgcrypto
- **Initial Size**: 10GB
- **Connection Pool**: 20 connections
- **Backup**: Daily automated backups

### Database Migrations
- Located in: `/server/migrations/`
- Run via: `npx sequelize-cli db:migrate`
- Seeds in: `/server/seeders/`

## Network Requirements

### Ingress Rules
```yaml
Frontend:
  - Path: /
  - Port: 80/443
  - Domain: www.rbcleasing.com, rbcleasing.com

Backend API:
  - Path: /api
  - Port: 5000
  - Domain: api.rbcleasing.com

Health Checks:
  - Frontend: GET /
  - Backend: GET /api/health
```

### External Service Dependencies
- **Azure AD**: Authentication
- **Azure Maps API**: Route optimization (optional)
- **SendGrid/SMTP**: Email notifications
- **Twilio**: SMS notifications (optional)

## Security Requirements

### RBAC Roles
```javascript
Roles:
  - SUPER_ADMIN: Full system access
  - ADMIN: Administrative functions
  - MANAGER: Manage tours and fleet
  - SALES: Manage quotes and clients
  - DRIVER: View assigned tours
  - CUSTOMER: View own bookings
```

### API Authentication
- **Method**: JWT Bearer tokens
- **Token Expiry**: 24 hours
- **Refresh Token**: 7 days
- **Multi-factor**: Via Azure AD

### Data Protection
- **PII Encryption**: AES-256
- **SSL/TLS**: Required for all endpoints
- **CORS**: Configured for specific domains
- **Rate Limiting**: 100 requests/minute per IP

## Scaling Requirements

### Frontend
- **Min Replicas**: 2
- **Max Replicas**: 10
- **CPU Target**: 70%
- **Memory Target**: 80%

### Backend
- **Min Replicas**: 2
- **Max Replicas**: 20
- **CPU Target**: 60%
- **Memory Target**: 70%

### Database
- **Read Replicas**: 1 (production)
- **Connection Pooling**: PgBouncer
- **Auto-scaling**: Based on CPU/Memory

## Monitoring & Logging

### Application Metrics
- Response time
- Error rate
- Request rate
- Active users
- Database query time

### Business Metrics
- Tours completed
- Quotes generated
- Conversion rate
- Revenue metrics
- Fleet utilization

### Log Aggregation
- Application logs → Application Insights
- Access logs → Log Analytics
- Error tracking → Application Insights
- Audit logs → Separate secure storage

## CI/CD Pipeline Requirements

### Build Pipeline
```yaml
Frontend:
  - Install dependencies
  - Run linting
  - Run tests
  - Build production bundle
  - Build Docker image
  - Push to registry

Backend:
  - Install dependencies
  - Run linting
  - Run tests
  - Run migrations (staging/prod)
  - Build Docker image
  - Push to registry
```

### Deployment Pipeline
```yaml
Development:
  - Trigger: Push to main
  - Auto-deploy: Yes
  - Approval: No

Staging:
  - Trigger: Tag v*-rc*
  - Auto-deploy: Yes
  - Approval: No

Production:
  - Trigger: Tag v*
  - Auto-deploy: No
  - Approval: Required
```

## Health Checks & Readiness Probes

### Frontend Health Check
```http
GET / HTTP/1.1
Expected: 200 OK
```

### Backend Health Check
```http
GET /api/health HTTP/1.1
Expected Response:
{
  "status": "healthy",
  "database": "connected",
  "redis": "connected",
  "version": "1.0.0"
}
```

### Readiness Check
```http
GET /api/ready HTTP/1.1
Expected Response:
{
  "ready": true,
  "services": {
    "database": true,
    "cache": true,
    "email": true
  }
}
```

## Disaster Recovery

### Backup Requirements
- **Database**: Daily full backup, hourly incremental
- **File Storage**: Daily backup of uploads
- **Configuration**: Version controlled in Git

### RTO/RPO Targets
- **RTO**: 4 hours
- **RPO**: 1 hour
- **Backup Retention**: 30 days
- **DR Region**: Secondary Azure region

## Cost Optimization

### Auto-shutdown Schedule (Non-Production)
- **Development**: Shutdown at 8 PM, Start at 6 AM
- **Staging**: Always on
- **Production**: Always on

### Resource Limits
```yaml
Frontend:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 512Mi

Backend:
  requests:
    cpu: 250m
    memory: 512Mi
  limits:
    cpu: 1000m
    memory: 1Gi
```

## Contact Information

### Application Team
- **Product Owner**: [Name]
- **Tech Lead**: [Name]
- **DevOps Lead**: [Name]

### Escalation Path
1. On-call Developer
2. Tech Lead
3. Infrastructure Team
4. Product Owner

## Related Documentation
- [Application Repository](https://github.com/RobertsBrothersCoach/RBC-LeasingApp)
- [API Documentation](/docs/api)
- [Database Schema](/docs/database)
- [Security Policies](/docs/security)