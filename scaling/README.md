# Auto-Scaling Configuration

This directory contains auto-scaling configurations for all Tour Bus Leasing application services to efficiently handle 50-500 concurrent users while optimizing costs.

## Overview

The auto-scaling configuration provides:
- HTTP-based scaling for Container Apps
- CPU/Memory-based scaling for App Service
- Connection pooling for PostgreSQL
- Memory-based scaling for Redis Cache
- Load testing scenarios for validation
- Cost-optimized scaling rules per environment

## Components

### 1. Container Apps Scaling (`container-apps-scaling.bicep`)

Configures HTTP concurrent request-based scaling:

| Environment | Min Replicas | Max Replicas | Trigger |
|------------|--------------|--------------|---------|
| Dev | 0 | 2 | 30 concurrent requests |
| QA | 0 | 3 | 30 concurrent requests |
| Prod | 1 | 10 | 30 concurrent requests + CPU/Memory |

### 2. App Service Auto-Scale (`app-service-autoscale.json`)

CPU and Memory-based scaling with time-based profiles:

| Environment | Min Instances | Max Instances | CPU Threshold | Memory Threshold |
|------------|---------------|---------------|---------------|------------------|
| Dev | 1 | 2 | 80% | 80% |
| QA | 1 | 3 | 75% | 75% |
| Prod | 1 | 10 | 70% | 70% |

**Time-based Profiles:**
- Business hours (7 AM - 7 PM EST): Full scaling
- Night time (8 PM - 7 AM): Reduced capacity
- Weekends: Minimal capacity

### 3. PostgreSQL Connection Pooling (`postgresql-connection-pooling.bicep`)

PgBouncer configuration for efficient connection management:

| Environment | Default Pool | Max Pool | Max Clients | Auto-Pause |
|------------|--------------|----------|-------------|------------|
| Dev | 25 | 50 | 100 | 60 min |
| QA | 30 | 75 | 150 | 60 min |
| Prod | 50 | 100 | 500 | Never |

### 4. Redis Scaling (`redis-scaling-config.json`)

Memory-based scaling with eviction policies:

| Environment | SKU | Capacity | Memory Policy | Shards |
|------------|-----|----------|---------------|---------|
| Dev | Basic C0 | 250 MB | allkeys-lru | 1 |
| QA | Standard C1 | 1 GB | allkeys-lru | 1 |
| Prod | Premium P1 | 6 GB | allkeys-lru | 2 |

## Deployment

### Deploy Container Apps Scaling

```bash
az deployment group create \
  --resource-group rg-tourbus-dev \
  --template-file container-apps-scaling.bicep \
  --parameters \
    environmentName=dev \
    containerAppName=ca-tourbus-frontend
```

### Deploy App Service Auto-Scale

```bash
az deployment group create \
  --resource-group rg-tourbus-dev \
  --template-file app-service-autoscale.json \
  --parameters \
    appServicePlanName=asp-tourbus-api \
    environmentName=dev
```

### Deploy PostgreSQL Connection Pooling

```bash
az deployment group create \
  --resource-group rg-tourbus-dev \
  --template-file postgresql-connection-pooling.bicep \
  --parameters \
    postgresServerName=psql-tourbus-dev \
    environmentName=dev
```

### Deploy Redis Scaling

```bash
az deployment group create \
  --resource-group rg-tourbus-dev \
  --template-file redis-scaling-config.json \
  --parameters \
    redisCacheName=redis-tourbus-dev \
    environmentName=dev
```

## Load Testing

Run load tests to validate scaling behavior:

```bash
# Install Azure Load Testing CLI extension
az extension add --name load

# Create load test
az load test create \
  --name tourbus-scaling-test \
  --resource-group rg-tourbus-test \
  --location eastus

# Run gradual ramp test
az load test run create \
  --test-id tourbus-scaling-test \
  --load-test-config-file load-tests/scaling-test.yaml \
  --description "Gradual ramp test"

# Monitor results
az load test run show \
  --test-id tourbus-scaling-test \
  --run-id <run-id>
```

## Monitoring

### Key Metrics to Monitor

1. **Response Time**: p95 < 500ms
2. **Error Rate**: < 10%
3. **Scale Latency**: < 5 minutes
4. **Resource Utilization**: 
   - CPU < 70%
   - Memory < 70%
   - Connections < 80%

### Setting Up Alerts

```powershell
# CPU Alert
az monitor metrics alert create \
  --name high-cpu-alert \
  --resource-group rg-tourbus-prod \
  --scopes /subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Web/serverfarms/{plan} \
  --condition "avg CpuPercentage > 80" \
  --window-size 5m \
  --evaluation-frequency 1m

# Memory Alert
az monitor metrics alert create \
  --name high-memory-alert \
  --resource-group rg-tourbus-prod \
  --scopes /subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Web/serverfarms/{plan} \
  --condition "avg MemoryPercentage > 80" \
  --window-size 5m \
  --evaluation-frequency 1m

# Response Time Alert
az monitor metrics alert create \
  --name slow-response-alert \
  --resource-group rg-tourbus-prod \
  --scopes /subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Web/sites/{site} \
  --condition "avg ResponseTime > 1000" \
  --window-size 5m \
  --evaluation-frequency 1m
```

## Cost Optimization

### Scale-to-Zero Configuration

Development and QA environments are configured to scale to zero when not in use:

- **Container Apps**: Min replicas = 0
- **App Service**: Night/weekend profiles with 0-1 instances
- **PostgreSQL**: Auto-pause after 60 minutes of inactivity

### Estimated Cost Savings

| Environment | Without Scaling | With Scaling | Savings |
|------------|----------------|--------------|---------|
| Dev | $400/month | $100/month | 75% |
| QA | $600/month | $200/month | 67% |
| Prod | $2,000/month | $1,500/month | 25% |

## Troubleshooting

### Common Issues

1. **Slow Scale-Out**
   - Check metric evaluation frequency
   - Reduce cooldown periods
   - Lower threshold values

2. **Frequent Scaling Events**
   - Increase cooldown periods
   - Adjust threshold values
   - Review metric aggregation windows

3. **Connection Pool Exhaustion**
   - Increase max pool size
   - Review connection leak issues
   - Implement connection retry logic

4. **Redis Memory Pressure**
   - Review eviction policy
   - Increase cache size
   - Implement cache warming

### Performance Tuning

1. **Container Apps**
   ```bash
   # Update concurrent request threshold
   az containerapp update \
     --name ca-tourbus-frontend \
     --resource-group rg-tourbus-prod \
     --scale-rule-http-concurrency 25
   ```

2. **App Service**
   ```bash
   # Update CPU threshold
   az monitor autoscale rule create \
     --resource-group rg-tourbus-prod \
     --autoscale-name autoscale-asp-tourbus \
     --condition "CpuPercentage > 65 avg 5m" \
     --scale out 1
   ```

3. **PostgreSQL**
   ```sql
   -- Check connection pool stats
   SELECT * FROM pg_stat_database WHERE datname = 'tourbus';
   
   -- Monitor active connections
   SELECT count(*) FROM pg_stat_activity WHERE state = 'active';
   ```

## Best Practices

1. **Test Scaling Changes**: Always test in non-production first
2. **Monitor After Changes**: Watch metrics for 24-48 hours after changes
3. **Document Changes**: Keep scaling configuration in version control
4. **Regular Reviews**: Review scaling metrics monthly
5. **Cost Monitoring**: Set up cost alerts for unexpected scaling

## Support

For issues or questions:
1. Check Azure Monitor metrics and logs
2. Review load test results
3. Contact DevOps team for assistance