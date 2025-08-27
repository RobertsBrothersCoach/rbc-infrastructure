# DNS Configuration for *.cloud.rbccoach.com

This guide explains how to configure DNS records to enable custom domain access to your AKS services.

## Overview

Your AKS cluster uses nginx-ingress with a Load Balancer to route traffic to services. You need to point your DNS records to the Load Balancer IP.

## Get Load Balancer IP

First, get the public IP assigned to your nginx-ingress controller:

```bash
kubectl get service ingress-nginx-controller -n ingress-nginx
```

Look for the `EXTERNAL-IP` column. This is your Load Balancer IP.

## DNS Records Required

Configure these DNS records in your domain provider (where rbccoach.com is hosted):

### A Records
| Name | Type | Value | TTL |
|------|------|-------|-----|
| `*.cloud.rbccoach.com` | A | `<LOAD_BALANCER_IP>` | 300 |
| `argocd-dev.cloud.rbccoach.com` | A | `<LOAD_BALANCER_IP>` | 300 |

### Alternative: CNAME Records (if using wildcard is not supported)
| Name | Type | Value | TTL |
|------|------|-------|-----|
| `argocd-dev.cloud.rbccoach.com` | CNAME | `cloud.rbccoach.com` | 300 |
| `grafana-dev.cloud.rbccoach.com` | CNAME | `cloud.rbccoach.com` | 300 |
| `app-dev.cloud.rbccoach.com` | CNAME | `cloud.rbccoach.com` | 300 |

Then create:
| Name | Type | Value | TTL |
|------|------|-------|-----|
| `cloud.rbccoach.com` | A | `<LOAD_BALANCER_IP>` | 300 |

## Domain Provider Instructions

### CloudFlare
1. Go to CloudFlare Dashboard → DNS
2. Click "Add record"
3. Type: A
4. Name: `*.cloud.rbccoach.com`
5. IPv4 address: `<LOAD_BALANCER_IP>`
6. TTL: Auto
7. Click "Save"

### GoDaddy
1. Go to GoDaddy DNS Management
2. Click "Add" → "A Record"
3. Host: `*.cloud`
4. Points to: `<LOAD_BALANCER_IP>`
5. TTL: 1 Hour
6. Click "Save"

### Namecheap
1. Go to Namecheap → Domain List → Manage
2. Advanced DNS tab
3. Add New Record
4. Type: A Record
5. Host: `*.cloud`
6. Value: `<LOAD_BALANCER_IP>`
7. TTL: Automatic
8. Click "Save All Changes"

### Route 53 (AWS)
1. Go to Route 53 → Hosted Zones
2. Select rbccoach.com
3. Click "Create Record"
4. Record name: `*.cloud`
5. Record type: A
6. Value: `<LOAD_BALANCER_IP>`
7. TTL: 300
8. Click "Create records"

## Verify DNS Configuration

After configuring DNS, verify the records:

```bash
# Test wildcard DNS
nslookup argocd-dev.cloud.rbccoach.com

# Test specific subdomain
dig argocd-dev.cloud.rbccoach.com

# Alternative test
ping argocd-dev.cloud.rbccoach.com
```

You should see the DNS resolving to your Load Balancer IP.

## SSL Certificates

Once DNS is configured, cert-manager will automatically:

1. **Detect** the ingress with `cert-manager.io/cluster-issuer` annotation
2. **Request** SSL certificate from Let's Encrypt
3. **Validate** domain ownership via HTTP-01 challenge
4. **Install** certificate and enable HTTPS

Monitor certificate issuance:

```bash
# Check certificate requests
kubectl get certificaterequests -A

# Check certificates
kubectl get certificates -A

# Check certificate details
kubectl describe certificate argocd-tls -n argocd
```

## Troubleshooting

### DNS Not Resolving
- Wait 5-15 minutes for DNS propagation
- Check TTL settings (lower = faster propagation)
- Use online DNS checker tools
- Verify wildcard support with your provider

### SSL Certificate Issues
```bash
# Check cert-manager logs
kubectl logs -n cert-manager deployment/cert-manager

# Check certificate status
kubectl describe certificate argocd-tls -n argocd

# Check challenge status
kubectl get challenges -A
```

### Load Balancer Issues
```bash
# Check nginx-ingress controller
kubectl get pods -n ingress-nginx
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller

# Check service
kubectl describe service ingress-nginx-controller -n ingress-nginx
```

## Services Available

Once DNS is configured, these services will be available:

- **ArgoCD**: https://argocd-dev.cloud.rbccoach.com
- **Future Apps**: https://[app-name]-dev.cloud.rbccoach.com

## Cost Optimization

The nginx-ingress + cert-manager setup adds approximately **$15-25/month** to your infrastructure cost:

- **Load Balancer**: ~$15-20/month (Basic SKU)
- **Compute Resources**: ~$3-5/month (minimal resource requests)
- **SSL Certificates**: Free (Let's Encrypt)

This provides professional-grade domain access with automatic HTTPS for all your services.