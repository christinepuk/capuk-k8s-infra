# Multi-Service Helm Chart

This Helm chart deploys a comprehensive multi-application stack on Kubernetes including:

- **Plex Media Server**: Media streaming server with transcoding support
- **WordPress Sites**: Three separate WordPress installations with dedicated MySQL databases

## Prerequisites

- Kubernetes cluster (1.19+) - **Linode LKE supported**
- Helm 3.x
- Storage classes configured for persistent volumes
- Ingress controller (nginx recommended)
- Cert-manager for SSL certificates (optional but recommended)

## 🚀 Linode LKE Deployment Guide

Complete deployment guide for **christinepuk.net** on Linode Kubernetes Engine (LKE).

### 🏗️ Step 1: Create LKE Cluster

#### Via Linode Cloud Manager
1. Log in to [Linode Cloud Manager](https://cloud.linode.com)
2. Navigate to **Kubernetes** → **Create Cluster**
3. Configure your cluster:
   - **Cluster Name**: `multi-service-cluster`
   - **Region**: Choose closest to your location
   - **Kubernetes Version**: Latest stable (1.28+)
   - **Node Pools**: 
     - **Shared CPU**: 3x Linode 4GB (recommended minimum)
     - Or **Dedicated CPU**: 2x Linode 8GB for better performance

#### Via Linode CLI
```bash
# Install Linode CLI
pip3 install linode-cli

# Configure CLI
linode-cli configure

# Create cluster
linode-cli lke cluster-create \
  --label multi-service-cluster \
  --region us-east \
  --k8s_version 1.28 \
  --node_pools.type g6-standard-2 \
  --node_pools.count 3
```

### 🔧 Step 2: Configure kubectl

```bash
# Download kubeconfig from Linode Cloud Manager
# Set KUBECONFIG (replace with your actual kubeconfig file)
export KUBECONFIG=/path/to/your-kubeconfig.yaml

# Make it permanent
echo 'export KUBECONFIG=/path/to/your-kubeconfig.yaml' >> ~/.bashrc

# Verify connection
kubectl get nodes
```

### 📦 Step 3: Install Prerequisites

#### Install Helm (if not already installed)
```bash
# Install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Verify installation
helm version
```

#### Install NGINX Ingress Controller
```bash
# Add ingress-nginx repository
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

# Install with LoadBalancer service for LKE
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.type=LoadBalancer \
  --set controller.service.externalTrafficPolicy=Local
```

#### Install Cert-Manager (for SSL)
```bash
# Add cert-manager repository
helm repo add jetstack https://charts.jetstack.io
helm repo update

# Install cert-manager
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set installCRDs=true
```

#### Create ClusterIssuer for Let's Encrypt
```bash
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@christinepuk.net
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
EOF
```

### 🌐 Step 4: Configure DNS

#### Get Load Balancer IP
```bash
# Get the external IP of your ingress controller
kubectl get svc -n ingress-nginx ingress-nginx-controller
```

#### Add DNS Records to christinepuk.net
```dns
# A Records pointing to your LKE LoadBalancer IP
tv.christinepuk.net         A    <LOADBALANCER_IP>
blog.christinepuk.net       A    <LOADBALANCER_IP>
djpup.christinepuk.net      A    <LOADBALANCER_IP>
surf.christinepuk.net       A    <LOADBALANCER_IP>
```

### 🚀 Step 5: Deploy the Multi-Service Chart

#### Create/Use LKE-Optimized Values File
The `lke-values.yaml` file contains:

```yaml
# LKE-optimized configuration for christinepuk.net
global:
  storageClass: "linode-block-storage-retain"
  domain: "christinepuk.net"

plex:
  enabled: true
  claimToken: "claim-xxxxxxxxxxxxxxxxxxxx"  # Get from https://plex.tv/claim
  persistence:
    config:
      size: 50Gi
    media:
      size: 1000Gi  # Adjust based on your media library size
  ingress:
    host: "tv.christinepuk.net"

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

#### Deploy the Chart
```bash
# Deploy with LKE-optimized values
helm install multi-service ./charts/multi-service \
  -f lke-values.yaml \
  --namespace multi-service \
  --create-namespace

# Watch the deployment
kubectl get pods -n multi-service -w
```

### 📊 Step 6: Verify Deployment

#### Check All Components
```bash
# Check pod status
kubectl get pods -n multi-service

# Check services
kubectl get svc -n multi-service

# Check ingress
kubectl get ingress -n multi-service

# Check SSL certificates
kubectl get certificates -n multi-service
```

### 🎬 Step 7: Complete Plex Setup

After deployment, complete the initial Plex server configuration:

#### Access Plex Setup Interface
```bash
# Create port-forward to access Plex locally
kubectl port-forward -n multi-service deployment/multi-service-plex 32400:32400
# Output: Forwarding from 127.0.0.1:32400 -> 32400
#         Forwarding from [::1]:32400 -> 32400
```

#### Complete Setup Wizard
1. **Open browser** and navigate to: `http://localhost:32400/web`
2. **Sign in** to your Plex account (required for remote access)
3. **Name your server** (e.g., "Kubernetes Plex Server")
4. **Add media libraries** if using rclone object storage:
   - Movies: `/data/Film`
   - TV Shows: `/data/TV`  
   - Music: `/data/Music`
   - Audiobooks: `/data/Books/Audio`
5. **Complete wizard** and stop port-forward (Ctrl+C)

#### Verify External Access
```bash
# Test external Plex access
curl -I https://tv.christinepuk.net
# Should return HTTP/2 401 or 200 (not connection refused)

# Test WordPress sites
curl -I https://blog.christinepuk.net
curl -I https://djpup.christinepuk.net
curl -I https://surf.christinepuk.net
```

**Important**: Initial Plex setup must be done via `localhost:32400` for security. After setup, access via `https://tv.christinepuk.net`

### 📊 Step 8: Monitor Deployment

#### Check All Components
```bash

# Check services
kubectl get svc -n multi-service

# Check ingress
kubectl get ingress -n multi-service

# Check persistent volumes
kubectl get pvc -n multi-service

# Check SSL certificates
kubectl get certificates -n multi-service
```

#### Test Services
```bash
# Test Plex
curl -I https://tv.christinepuk.net

# Test WordPress sites
curl -I https://blog.christinepuk.net
curl -I https://djpup.christinepuk.net
curl -I https://surf.christinepuk.net
```

### 🔧 Step 7: Initial Configuration

#### Plex Setup
1. Visit `https://tv.christinepuk.net`
2. Sign in with your Plex account
3. The claim token will automatically link your server
4. Add your media libraries

**Note**: If you get a 502 Bad Gateway, wait 2-3 minutes for Plex to fully start.

#### WordPress Sites
For each WordPress site:
1. Visit the site URL (blog, djpup, surf)
2. Complete the 5-minute WordPress installation
3. Configure your admin account and site settings

## Services and Access

After deployment, your services will be available at:

- **Plex**: `https://tv.christinepuk.net`
- **Blog**: `https://blog.christinepuk.net`
- **DJ Pup**: `https://djpup.christinepuk.net`
- **Surf**: `https://surf.christinepuk.net`

## Configuration

### Storage Configuration

The chart supports different storage classes for each service:

```yaml
global:
  storageClass: "linode-block-storage-retain"  # LKE default

plex:
  persistence:
    media:
      size: 1Ti
      storageClass: "linode-block-storage-retain"  # Large media files
      # NOTE: Use ReadWriteOnce - LKE doesn't support ReadWriteMany
    config:
      size: 50Gi
      storageClass: "linode-block-storage-retain"  # Config storage
```

### Plex Configuration

For Plex to work properly, you need to:

1. Get a claim token from https://plex.tv/claim
2. Set it in your values:
```yaml
plex:
  claimToken: "claim-xxxxxxxxxxxx"
```

3. For GPU transcoding (optional):
```yaml
plex:
  resources:
    limits:
      nvidia.com/gpu: 1
```

## Monitoring and Troubleshooting

### Check Pod Status
```bash
kubectl get pods -n multi-service
kubectl get pods -l app.kubernetes.io/instance=multi-service
```

### View Logs
```bash
# Plex logs  
kubectl logs -l app.kubernetes.io/component=plex -n multi-service

# WordPress logs (for blog site)
kubectl logs -l app.kubernetes.io/component=wordpress,app.kubernetes.io/instance=site1 -n multi-service
```

### Check Storage
```bash
kubectl get pvc -n multi-service
```

## 💰 LKE Cost Optimization

### Resource Planning
**Important**: Plan your LKE node capacity carefully:
- **3x 2CPU nodes** can be resource-constrained with all services  
- **Plex + 3 WordPress + 3 MySQL** = ~2.5 CPU cores needed
- Consider **3x 4CPU nodes** or **4x 2CPU nodes** for comfortable margins
- **LKE-specific**: Use ReadWriteOnce storage only (ReadWriteMany not supported)

### Storage Optimization
```bash
# Use linode-block-storage-retain for data persistence
# Cheaper than premium storage options
# IMPORTANT: Only ReadWriteOnce access mode supported on LKE
storageClassName: "linode-block-storage-retain"
accessModes:
  - ReadWriteOnce  # Required for LKE
```

### Resource Optimization
```bash  
# Scale down resources for smaller LKE clusters
helm upgrade multi-service ./charts/multi-service \
  -f lke-values.yaml \
  --set plex.resources.requests.cpu=250m \
  --set plex.resources.requests.memory=512Mi \
  --set wordpress.resources.requests.cpu=100m \
  --set wordpress.resources.requests.memory=128Mi
```

## Backup and Recovery

### Database Backups
```bash
# Create backup script for LKE
#!/bin/bash
DATE=$(date +%Y%m%d)
NAMESPACE="multi-service"

# Backup WordPress databases
for site in blog djpup surf; do
  kubectl exec -n $NAMESPACE deployment/multi-service-mysql-$site -- \
    mysqldump -u wordpress -pwordpress wordpress | \
    gzip > backups/$DATE-$site-db.sql.gz
done
```

### File Backups
Important directories to backup:
- Plex config: `/config`
- WordPress files: `/var/www/html`

## Security Considerations

1. **Change default passwords** in `lke-values.yaml`
2. **Enable SSL/TLS** for all services (automatic with cert-manager)
3. **Use strong storage encryption** if handling sensitive data
4. **Regular security updates** - update container images periodically
5. **Network policies** - implement Kubernetes network policies if needed

## Scaling

### WordPress Scaling
You can scale WordPress deployments individually:
```bash
kubectl scale deployment multi-service-wordpress-site1 --replicas=3 -n multi-service
```

### Resource Limits
Adjust resource limits based on your cluster capacity:
```yaml
wordpress:
  resources:
    limits:
      memory: 1Gi
      cpu: 1000m
```

## Updates and Upgrades

### Upgrade Kubernetes Version
1. Go to Linode Cloud Manager
2. Select your cluster → Settings → Upgrade
3. Choose new version and upgrade nodes

### Upgrade Applications
```bash
# Update Helm chart
helm upgrade multi-service ./charts/multi-service \
  -f lke-values.yaml \
  --namespace multi-service

# Update individual components
helm upgrade ingress-nginx ingress-nginx/ingress-nginx -n ingress-nginx
```

## Troubleshooting

### Common Issues

1. **Pod Stuck in Pending**: Check node resources and storage availability
2. **SSL Certificate Issues**: Check cert-manager logs and certificate status
3. **LoadBalancer Not Getting IP**: Verify LKE node balancer in Cloud Manager
4. **Plex Access Mode Issues**: Use ReadWriteOnce instead of ReadWriteMany for LKE
5. **Plex Permission Errors**: Remove securityContext restrictions that prevent file access
6. **502 Bad Gateway for Plex**: Usually indicates Plex is starting up or configuration needed
7. **Resource Constraints**: Reduce CPU/memory requests for multi-service deployments
8. **WordPress Database Connection**: Check MySQL readiness probes

### LKE-Specific Issues

- **Storage Access Modes**: LKE only supports ReadWriteOnce, not ReadWriteMany
- **CPU Limits**: 2-core nodes require careful resource allocation for multiple services
- **Security Contexts**: Some containers need elevated permissions initially

### Support

For issues specific to:
- **Plex**: Refer to [Plex Docker documentation](https://github.com/plexinc/pms-docker)
- **WordPress**: See [WordPress Docker documentation](https://hub.docker.com/_/wordpress)
- **LKE**: Consult [Linode Kubernetes Engine documentation](https://www.linode.com/products/kubernetes/)

## License

This Helm chart is released under the MIT License.