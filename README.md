# Multi-Service Kubernetes Deployment

A production-ready Helm chart for deploying Plex Media Server and WordPress sites on Kubernetes, optimized for Linode LKE.

## What's Deployed

- **Plex Media Server** with object storage integration
- **AudioBookShelf** for audiobooks and podcasts
- **3 WordPress Sites** with dedicated MySQL databases
- **Automatic SSL** certificates via Let's Encrypt
- **Ingress routing** for multiple domains

## Live Services

After deployment, services are available at:

- **Plex**: https://tv.christinepuk.net
- **AudioBookShelf**: https://books.christinepuk.net
- **Blog**: https://blog.christinepuk.net  
- **DJ Pup**: https://djpup.christinepuk.net
- **Surf**: https://surf.christinepuk.net

## Quick Start

### Prerequisites

- Kubernetes 1.19+ (LKE supported)
- Helm 3.x
- Domain with DNS control
- Linode Object Storage bucket (optional, for Plex media)

### 1. Deploy Infrastructure

```bash
# Clone repository
git clone <this-repo>
cd capuk-k8s-infra

# Install prerequisites (ingress-nginx, cert-manager)
./scripts/install-prerequisites.sh

# Source environment variables (REQUIRED)
source .env

# Deploy applications with proper variable substitution
envsubst < lke-values.yaml | helm install multi-service ./charts/multi-service \
  -f - \
  --namespace multi-service \
  --create-namespace
```

### 2. Complete Plex Setup

```bash
# Port-forward for initial setup
kubectl port-forward svc/multi-service-plex 32400:32400 -n multi-service

# Open browser to http://localhost:32400/web
# Complete Plex server setup wizard
```

### 3. Configure WordPress Sites

Visit each WordPress site and complete the 5-minute installation:
- https://blog.christinepuk.net
- https://djpup.christinepuk.net  
- https://surf.christinepuk.net

## Documentation

| Guide | Description |
|-------|-------------|
| [DEPLOYMENT.md](DEPLOYMENT.md) | Complete step-by-step deployment guide |
| [LKE-DEPLOYMENT.md](LKE-DEPLOYMENT.md) | Linode LKE specific setup instructions |
| [PLEX-OBJECT-STORAGE.md](PLEX-OBJECT-STORAGE.md) | Configure Plex with object storage |
| [TROUBLESHOOTING.md](TROUBLESHOOTING.md) | Common issues and solutions |
| [MAINTENANCE.md](MAINTENANCE.md) | Cluster maintenance and operations |

## Configuration

### Plex Configuration

Key settings in `lke-values.yaml`:

```yaml
plex:
  enabled: true
  claimToken: "claim-xxxxxxxxxxxx"  # Get from https://plex.tv/claim
  ingress:
    host: "tv.christinepuk.net"
  
  # Object storage integration (optional)
  rclone:
    enabled: true
    config: |
      [linode]
      type = s3
      access_key_id = YOUR_ACCESS_KEY
      endpoint = us-iad-1.linodeobjects.com
      env_auth = false
      provider = Other
      region = us-iad-1
      secret_access_key = YOUR_SECRET_KEY
```

### WordPress Configuration

```yaml
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
```

## Common Operations

### Check Status
```bash
kubectl get pods -n multi-service
kubectl get ingress -n multi-service
kubectl get certificates -n multi-service
```

### View Logs
```bash
# Plex logs
kubectl logs deployment/multi-service-plex -n multi-service

# WordPress logs
kubectl logs deployment/multi-service-wordpress-site1 -n multi-service
```

### Scale Services
```bash
# Scale WordPress
kubectl scale deployment multi-service-wordpress-site1 --replicas=2 -n multi-service

# Update resource limits
helm upgrade multi-service ./charts/multi-service -f lke-values.yaml -n multi-service
```

## LKE-Specific Notes

### Resource Planning
- **Minimum**: 3x 2GB nodes (tight resource constraints)
- **Recommended**: 3x 4GB nodes or 4x 2GB nodes
- **Total needs**: ~2.5 CPU cores + 4GB RAM for all services

### Storage Limitations
- Use `ReadWriteOnce` only (ReadWriteMany not supported)
- Storage class: `linode-block-storage-retain`

### Cost Optimization
```yaml
# Reduce resource requests for smaller clusters
plex:
  resources:
    requests:
      cpu: 300m
      memory: 1Gi

wordpress:
  resources:
    requests:
      cpu: 100m  
      memory: 128Mi
```

## Maintenance

### Backup Data
```bash
# Database backups
./scripts/backup-databases.sh

# Plex configuration
kubectl exec deployment/multi-service-plex -c plex -n multi-service -- \
  tar czf - /config > plex-config-backup.tar.gz
```

### Update Applications
```bash
# Update Helm chart
helm upgrade multi-service ./charts/multi-service -f lke-values.yaml -n multi-service

# Update Kubernetes cluster via Linode Cloud Manager
```

## Troubleshooting

### Quick Diagnostics
```bash
# Check all components
kubectl get all -n multi-service

# Check events
kubectl get events -n multi-service --sort-by='.lastTimestamp'

# Check SSL certificates
kubectl describe certificate -n multi-service
```

### Common Issues

| Issue | Solution |
|-------|----------|
| Pod pending with "Insufficient CPU" | Reduce resource requests or add nodes |
| Plex 502 Bad Gateway | Wait for startup or check port-forward setup |
| SSL certificate failed | Check DNS A records and cert-manager logs |
| WordPress database errors | Verify MySQL pod is running |

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for detailed solutions.

## Security

- SSL certificates automatically provisioned via Let's Encrypt
- Default passwords should be changed in `lke-values.yaml`
- Network policies can be added for additional isolation
- Regular updates recommended for container images

## License

MIT License - see [LICENSE](LICENSE) for details.

---

**Need help?** Check the documentation links above or create an issue for support.# Trigger workflow
