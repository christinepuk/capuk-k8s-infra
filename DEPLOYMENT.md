# Installation and Deployment Guide

## Prerequisites Setup

Before deploying the multi-service Helm chart, ensure your Kubernetes cluster has the necessary components:

### 1. Install Ingress Controller
```bash
# Install NGINX Ingress Controller
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.type=LoadBalancer
```

### 2. Install Cert-Manager (for SSL)
```bash
# Install Cert-Manager
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set installCRDs=true
```

### 3. Create ClusterIssuer for SSL
```bash
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: your-email@example.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
EOF
```

## Deployment Steps

### Step 1: Prepare Values File
Create your custom values file:

```bash
cp charts/multi-service/values.yaml production-values.yaml
```

Edit `production-values.yaml` with your specific configuration:
- Replace `example.com` with your actual domain
- Set Plex claim token from https://plex.tv/claim
- Configure rclone object storage for Plex and AudioBookShelf (optional)
- Adjust storage sizes based on your needs
- Configure resource limits for your cluster capacity

### Step 2: Configure Environment Variables
```bash
# Create environment file from template
cp .env.example .env

# Edit .env with your actual values
nano .env

# Source the environment variables (REQUIRED)
source .env
```

### Step 3: Deploy the Chart
```bash
# Deploy with proper variable substitution
envsubst < production-values.yaml | helm install multi-service ./charts/multi-service \
  -f - \
  --namespace multi-service \
  --create-namespace
```

### Step 4: Verify Deployment
```bash
# Check all pods are running
kubectl get pods -n multi-service

# Check services
kubectl get svc -n multi-service

# Check ingress
kubectl get ingress -n multi-service

# Check persistent volumes
kubectl get pvc -n multi-service
```

### Step 4: Configure DNS
Point your domains to the ingress controller's external IP:
```bash
kubectl get svc -n ingress-nginx ingress-nginx-controller
```

Add DNS records for:
- plex.yourdomain.com
- books.yourdomain.com (AudioBookShelf)
- site1.yourdomain.com
- site2.yourdomain.com
- site3.yourdomain.com

## Post-Deployment Configuration

### AudioBookShelf Setup
1. Access `https://books.yourdomain.com`
2. Complete the initial AudioBookShelf setup
3. Add audiobook libraries pointing to `/data/Books/Audio` or `/data/Podcasts`
4. Configure users and access settings

### Plex Setup  
1. Access `https://plex.yourdomain.com`
2. Sign in with your Plex account
3. Add media libraries pointing to `/data`
4. Configure remote access settings

### Accessing Services
Your services should now be accessible via:

**AudioBookShelf**:
- **Domain access**: https://books.yourdomain.com
- **Local access**: `kubectl port-forward svc/multi-service-audiobookshelf 80:80 -n multi-service`

**Plex**:
- **Domain access**: https://plex.yourdomain.com  
- **Local access**: `kubectl port-forward svc/multi-service-plex 32400:32400 -n multi-service`
- **Web access**: http://localhost:32400/web

### WordPress Sites
For each WordPress site:
1. Access the site URL (e.g., `https://site1.yourdomain.com`)
2. Complete WordPress installation wizard
3. Configure admin account and site settings

## Maintenance

### Updates
```bash
# Update chart values
helm upgrade multi-service ./charts/multi-service \
  -f production-values.yaml \
  --namespace multi-service

# Update container images
# Edit values file with new image tags, then upgrade
```

### Backup Script Example
```bash
#!/bin/bash
# Create backup directory
mkdir -p backups/$(date +%Y%m%d)

# Backup WordPress databases
for site in site1 site2 site3; do
  kubectl exec -n multi-service deployment/multi-service-mysql-$site -- \
    mysqldump -u wordpress -pwordpress wordpress > \
    backups/$(date +%Y%m%d)/$site-database.sql
done

# Backup Plex configuration (example using tar)
kubectl exec -n multi-service deployment/multi-service-plex -- \
  tar czf - /config > backups/$(date +%Y%m%d)/plex-config.tar.gz
```

### Monitoring
Consider adding monitoring tools like Prometheus and Grafana to monitor your deployment:

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace
```