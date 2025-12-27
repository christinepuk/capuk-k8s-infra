# Adding New WordPress Sites Guide

This guide covers how to add new WordPress sites to the multi-service Kubernetes deployment.

## Overview

Each WordPress site in this infrastructure includes:
- WordPress application container
- Dedicated MySQL database
- Persistent storage (WordPress files + MySQL data)
- Kubernetes services for internal communication
- Ingress with automatic SSL certificates
- Load balancer routing

## Prerequisites

- Kubernetes cluster running with multi-service Helm chart deployed
- cert-manager installed and configured with Let's Encrypt
- ingress-nginx controller running
- DNS control for the target domain

## Step-by-Step Process

### 1. Update Configuration Files

#### A. Update `lke-values.yaml` (Production Values)
Add the new site to the `wordpress.sites` section:

```yaml
# WordPress sites
wordpress:
  sites:
    site1:
      enabled: true
      name: "blog"
      host: "blog.christinepuk.net"
    site2:
      enabled: true
      name: "djpup"
      host: "djpup.christinepuk.net"
    site3:
      enabled: true
      name: "surf"
      host: "surf.christinepuk.net"
    site4:                           # <- ADD NEW SITE HERE
      enabled: true
      name: "your-site-name"         # Short name for internal use
      host: "yourdomain.com"         # Your actual domain
```

#### B. Update `charts/multi-service/values.yaml` (Template)
Add the same configuration to maintain consistency:

```yaml
# WordPress sites configuration
wordpress:
  sites:
    site1:
      enabled: true
      name: "site1"
      host: "site1.example.com"
    site2:
      enabled: true
      name: "site2"
      host: "site2.example.com"
    site3:
      enabled: true
      name: "site3"
      host: "site3.example.com"
    site4:                           # <- ADD NEW SITE HERE
      enabled: true
      name: "site4"
      host: "newdomain.com"
```

### 2. Deploy the Changes

#### A. Source Environment Variables
```bash
source ./.env
```

#### B. Upgrade the Helm Release
```bash
helm upgrade multi-service charts/multi-service/ \
  --namespace multi-service \
  --values lke-values.yaml
```

### 3. Verify Deployment

#### A. Check Helm Release Status
```bash
helm list -n multi-service
```

#### B. Verify Pods are Running
```bash
kubectl get pods -n multi-service | grep site4
```
Expected output:
```
multi-service-mysql-site4-xxxxx       1/1     Running   0     2m
multi-service-wordpress-site4-xxxxx   1/1     Running   0     2m
```

#### C. Check Persistent Volume Claims
```bash
kubectl get pvc -n multi-service | grep site4
```
Expected output:
```
multi-service-mysql-site4        Bound   pvc-xxxxx   50Gi   RWO   linode-block-storage-retain
multi-service-wordpress-site4    Bound   pvc-xxxxx   20Gi   RWO   linode-block-storage-retain
```

#### D. Verify Services
```bash
kubectl get svc -n multi-service | grep site4
```
Expected output:
```
multi-service-mysql-site4       ClusterIP   10.x.x.x     <none>   3306/TCP   5m
multi-service-wordpress-site4   ClusterIP   10.x.x.x     <none>   80/TCP     5m
```

#### E. Check Ingress Configuration
```bash
kubectl get ingress -n multi-service | grep site4
```
Expected output:
```
multi-service-wordpress-site4   nginx   yourdomain.com   172.237.141.119   80, 443   5m
```

### 4. Configure DNS

#### A. Get LoadBalancer IP
```bash
kubectl get ingress -n multi-service | grep site4
# Note the IP address (e.g., 172.237.141.119)
```

#### B. Configure DNS Records
In your domain registrar/DNS provider, add:
- **A Record**: `yourdomain.com` → `172.237.141.119`
- **CNAME Record** (optional): `www.yourdomain.com` → `yourdomain.com`

#### C. Verify DNS Propagation
```bash
nslookup yourdomain.com
```
Expected output:
```
Name:   yourdomain.com
Address: 172.237.141.119
```

### 5. SSL Certificate Verification

#### A. Check Certificate Status
```bash
kubectl get certificate -n multi-service site4-tls
```

#### B. Wait for Certificate Issuance
SSL certificates are automatically issued by Let's Encrypt once DNS resolves correctly.
This typically takes 1-5 minutes after DNS propagation.

Expected final status:
```
NAME        READY   SECRET      AGE
site4-tls   True    site4-tls   10m
```

## Troubleshooting

### Common Issues and Solutions

#### 1. Getting 404 Errors

**Symptoms:**
- Site returns 404 or connection errors
- Browser shows "This site can't be reached"

**Diagnosis Steps:**
```bash
# Check DNS resolution
nslookup yourdomain.com

# Test direct connection with Host header
curl -H "Host: yourdomain.com" http://172.237.141.119/

# Test HTTPS
curl -I https://yourdomain.com
```

**Solutions:**
- **DNS not configured**: Configure A record pointing to LoadBalancer IP
- **DNS propagation delay**: Wait 5-60 minutes for DNS to propagate globally
- **SSL certificate pending**: Wait for cert-manager to issue certificate

#### 2. WordPress Shows Installation Page

**Symptoms:**
- Site redirects to `/wp-admin/install.php`
- Fresh WordPress installation screen

**This is Normal!** 
- New WordPress installations redirect to setup page
- Complete the WordPress installation process
- After setup, the site homepage will be accessible

#### 3. Pods Not Starting

**Check Pod Status:**
```bash
kubectl get pods -n multi-service | grep site4
kubectl describe pod -n multi-service <pod-name>
```

**Common Causes:**
- Storage provisioning delays
- MySQL initialization time
- Resource constraints

#### 4. SSL Certificate Issues

**Check Certificate Details:**
```bash
kubectl describe certificate -n multi-service site4-tls
```

**Common Issues:**
- DNS not pointing to cluster (certificate validation fails)
- Rate limiting from Let's Encrypt (wait or use staging issuer)

#### 5. Ingress Not Routing

**Check Ingress Configuration:**
```bash
kubectl describe ingress -n multi-service multi-service-wordpress-site4
```

**Verify:**
- Host field matches your domain exactly
- Backend service name is correct
- TLS section is properly configured

## Testing Commands Reference

### Quick Health Check Script
```bash
#!/bin/bash
SITE_NAME="site4"
DOMAIN="yourdomain.com"

echo "=== WordPress Site Health Check: $DOMAIN ==="
echo ""

echo "1. Checking pods..."
kubectl get pods -n multi-service | grep $SITE_NAME

echo ""
echo "2. Checking ingress..."
kubectl get ingress -n multi-service | grep $SITE_NAME

echo ""
echo "3. Checking SSL certificate..."
kubectl get certificate -n multi-service ${SITE_NAME}-tls

echo ""
echo "4. Testing DNS resolution..."
nslookup $DOMAIN

echo ""
echo "5. Testing HTTP connection..."
curl -I https://$DOMAIN 2>/dev/null | head -3

echo ""
echo "=== Health Check Complete ==="
```

### Useful Monitoring Commands
```bash
# Watch pod status in real-time
watch kubectl get pods -n multi-service

# Follow WordPress logs
kubectl logs -n multi-service -l app.kubernetes.io/instance=site4 -f

# Check all resources for a site
kubectl get all -n multi-service -l app.kubernetes.io/instance=site4

# Monitor certificate issuance
watch kubectl get certificate -n multi-service
```

## Resource Allocation

Each WordPress site uses:
- **WordPress Pod**: 256Mi-512Mi RAM, 250m-500m CPU
- **MySQL Pod**: 512Mi-1Gi RAM, 250m-500m CPU  
- **WordPress Storage**: 20Gi persistent volume
- **MySQL Storage**: 50Gi persistent volume

## Site Naming Conventions

- **Site Key** (`site1`, `site2`, etc.): Internal Kubernetes identifier
- **Site Name** (`blog`, `djpup`, etc.): Human-readable short name
- **Host** (`blog.christinepuk.net`): Actual domain name

## Security Considerations

- Each site has its own isolated MySQL instance
- Persistent volumes use `linode-block-storage-retain` class
- SSL certificates are automatically managed by cert-manager
- WordPress and MySQL run as non-root users
- Network policies isolate database traffic

## Maintenance

### Updating Sites
```bash
# Update a specific site configuration
helm upgrade multi-service charts/multi-service/ \
  --namespace multi-service \
  --values lke-values.yaml

# Restart a site's pods
kubectl rollout restart deployment -n multi-service \
  multi-service-wordpress-site4 \
  multi-service-mysql-site4
```

### Scaling
```bash
# Scale WordPress pods (if needed)
kubectl scale deployment -n multi-service multi-service-wordpress-site4 --replicas=2
```

### Backup Considerations
- WordPress files are stored in persistent volumes
- MySQL data is in separate persistent volumes
- Consider implementing regular volume snapshots
- Export WordPress database for additional backups

## Next Steps After Adding Site

1. **Complete WordPress Setup**: Visit `https://yourdomain.com/wp-admin/install.php`
2. **Configure WordPress**: Set site title, admin user, and basic settings
3. **Install Themes/Plugins**: Customize as needed
4. **Set up Monitoring**: Add site to any monitoring systems
5. **Configure Backups**: Implement backup strategy for the new site
6. **Update Documentation**: Record any site-specific configurations

---

**Last Updated**: December 27, 2025  
**Tested With**: Kubernetes 1.28+, Helm 3.x, cert-manager 1.19+