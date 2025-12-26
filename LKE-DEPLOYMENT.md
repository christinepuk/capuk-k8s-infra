# Linode LKE Deployment Guide

Complete deployment guide for Plex and 3 WordPress sites on Linode Kubernetes Engine (LKE) using domain **christinepuk.net**.

## Step 1: Create LKE Cluster

### Via Linode Cloud Manager
1. Log in to [Linode Cloud Manager](https://cloud.linode.com)
2. Navigate to **Kubernetes** → **Create Cluster**
3. Configure your cluster:
   - **Cluster Name**: `multi-service-cluster`
   - **Region**: Choose closest to your location
   - **Kubernetes Version**: Latest stable (1.28+)
   - **Node Pools**: 
     - **Shared CPU**: 3x Linode 4GB (recommended minimum)
     - Or **Dedicated CPU**: 2x Linode 8GB for better performance

### Via Linode CLI
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

## Step 2: Configure kubectl

```bash
# Download kubeconfig from Linode Cloud Manager
# Or get it via CLI:
linode-cli lke kubeconfig-view <cluster-id> --text --no-headers | base64 -d > kubeconfig.yaml

# Set KUBECONFIG
export KUBECONFIG=kubeconfig.yaml

# Verify connection
kubectl get nodes
```

## Step 3: Install Prerequisites

### Install Helm (if not already installed)
```bash
# Install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Verify installation
helm version
```

### Install NGINX Ingress Controller
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

### Install Cert-Manager (for SSL)
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

### Create ClusterIssuer for Let's Encrypt
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

## Step 4: Configure DNS

### Get Load Balancer IP
```bash
# Get the external IP of your ingress controller
kubectl get svc -n ingress-nginx ingress-nginx-controller
```

### Add DNS Records
In your domain registrar's DNS management:

```dns
# A Records pointing to your LKE LoadBalancer IP
cloud.christinepuk.net      A    <LOADBALANCER_IP>
tv.christinepuk.net         A    <LOADBALANCER_IP>
blog.christinepuk.net       A    <LOADBALANCER_IP>
djpup.christinepuk.net      A    <LOADBALANCER_IP>
surf.christinepuk.net       A    <LOADBALANCER_IP>
```

## Step 5: Deploy the Multi-Service Chart

### Create LKE-Optimized Values File
```bash
cat > lke-values.yaml <<EOF
# LKE-optimized configuration
global:
  storageClass: "linode-block-storage-retain"
  domain: "christinepuk.net"

# Nextcloud configuration
nextcloud:
  enabled: true
  persistence:
    size: 100Gi
    storageClass: "linode-block-storage-retain"
  resources:
    requests:
      memory: 1Gi
      cpu: 500m
    limits:
      memory: 2Gi
      cpu: 1000m
  ingress:
    host: "cloud.christinepuk.net"

# Plex configuration
plex:
  enabled: true
  claimToken: "claim-xxxxxxxxxxxxxxxxxxxx"  # Get from https://plex.tv/claim
  persistence:
    config:
      size: 50Gi
      storageClass: "linode-block-storage-retain"
    media:
      size: 1000Gi  # Adjust based on your media library size
      storageClass: "linode-block-storage-retain"
  resources:
    requests:
      memory: 2Gi
      cpu: 1000m
    limits:
      memory: 4Gi
      cpu: 2000m
  ingress:
    host: "tv.christinepuk.net"

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
  
  persistence:
    size: 20Gi
    storageClass: "linode-block-storage-retain"
  
  mysql:
    persistence:
      size: 50Gi
      storageClass: "linode-block-storage-retain"
EOF
```

### Configure Environment Variables
```bash
# Create your environment file
cp .env.example .env

# Edit with your actual secrets
nano .env

# Example .env content:
export MYSQL_PASSWORD="your_secure_mysql_password"
export MYSQL_ROOT_PASSWORD="your_secure_root_password"
export PLEX_CLAIM_TOKEN="claim-xxxxxxxxxxxx"  # From https://plex.tv/claim
export ACCESS_KEY="your_linode_object_storage_access_key"
export SECRET_KEY="your_linode_object_storage_secret_key"

# Source the environment (REQUIRED before Helm)
source .env
```

### Deploy the Chart
```bash
# Deploy with proper variable substitution
envsubst < lke-values.yaml | helm install multi-service ./charts/multi-service \
  -f - \
  --namespace multi-service \
  --create-namespace

# Watch the deployment
kubectl get pods -n multi-service -w
```

## Step 6: Verify Deployment

### Check All Components
```bash
# Check pods status
kubectl get pods -n multi-service

# Check services
kubectl get svc -n multi-service

# Check ingress
kubectl get ingress -n multi-service

# Check persistent volumes
kubectl get pvc -n multi-service

# Check SSL certificates
kubectl get certificates -n multi-service
```

### Test Services
```bash
# Test Nextcloud
curl -I https://cloud.christinepuk.net

# Test Plex
curl -I https://tv.christinepuk.net

# Test WordPress sites
curl -I https://blog.christinepuk.net
curl -I https://djpup.christinepuk.net
curl -I https://surf.christinepuk.net
```

## Step 7: Initial Configuration

### Nextcloud Setup
1. Visit `https://cloud.christinepuk.net`
2. Complete the AIO master interface setup
3. Configure your domain and SSL settings
4. Start the container stack

### Plex Setup
1. Visit `https://tv.christinepuk.net`
2. Sign in with your Plex account
3. The claim token will automatically link your server
4. Add your media libraries

### WordPress Sites
For each WordPress site:
1. Visit the site URL
2. Complete the 5-minute WordPress installation
3. Configure your admin account and site settings

## LKE Cost Optimization

### Storage Optimization
```bash
# Use different storage classes for different needs
# Fast SSD for databases and config
storageClassName: "linode-block-storage"

# Slower but cheaper for media storage
storageClassName: "linode-block-storage-retain"
```

### Resource Optimization
```bash
# Scale down resources during low usage
helm upgrade multi-service ./charts/multi-service \
  -f lke-values.yaml \
  --set nextcloud.resources.requests.cpu=250m \
  --set plex.resources.requests.cpu=500m
```

### Auto-scaling Setup
```bash
# Install cluster autoscaler for automatic node scaling
kubectl apply -f https://raw.githubusercontent.com/linode/linode-cloud-controller-manager/master/deploy/cluster-autoscaler/cluster-autoscaler.yaml
```

## Monitoring & Maintenance

### Install Monitoring Stack
```bash
# Install Prometheus and Grafana
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set grafana.service.type=LoadBalancer
```

### Backup Strategy
```bash
# Create backup script for LKE
cat > backup.sh <<'EOF'
#!/bin/bash
DATE=$(date +%Y%m%d)
NAMESPACE="multi-service"

# Backup WordPress databases
for site in blog djpup surf; do
  kubectl exec -n $NAMESPACE deployment/multi-service-mysql-$site -- \
    mysqldump -u wordpress -pwordpress wordpress | \
    gzip > backups/$DATE-$site-db.sql.gz
done

# Backup to Linode Object Storage (optional)
# s3cmd sync backups/ s3://your-backup-bucket/
EOF

chmod +x backup.sh
```

### Troubleshooting Common Issues

#### Pod Stuck in Pending
```bash
# Check node resources
kubectl describe nodes

# Check storage availability
kubectl get pvc -n multi-service
```

#### SSL Certificate Issues
```bash
# Check cert-manager logs
kubectl logs -n cert-manager deployment/cert-manager

# Check certificate status
kubectl describe certificate -n multi-service
```

#### LoadBalancer Not Getting IP
```bash
# Check LKE node balancer status in Cloud Manager
# Verify service configuration
kubectl describe svc -n ingress-nginx ingress-nginx-controller
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
  -f lke-values.yaml

# Update individual components
helm upgrade ingress-nginx ingress-nginx/ingress-nginx -n ingress-nginx
```

This completes your LKE deployment! Your multi-service stack should now be running on Linode with SSL certificates, persistent storage, and proper ingress configuration.