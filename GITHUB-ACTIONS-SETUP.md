# GitHub Actions CI/CD Setup Guide

This guide explains how to set up automated deployments using GitHub Actions with secure secret management.

## Prerequisites

1. GitHub repository with your Kubernetes manifests
2. Linode LKE cluster running
3. Kubectl access to your cluster
4. Domain configured with DNS pointing to your LoadBalancer

## Required GitHub Secrets

Configure these secrets in your GitHub repository: **Settings → Secrets and variables → Actions**

### Infrastructure Secrets

| Secret Name | Description | How to Get |
|-------------|-------------|-----------|
| `KUBECONFIG` | Base64-encoded kubeconfig file | `cat ~/.kube/config \| base64 -w 0` |
| `LINODE_TOKEN` | Linode API token (optional) | Linode Cloud Manager → API Tokens |

### Application Secrets

| Secret Name | Description | Example Format |
|-------------|-------------|---------------|
| `PLEX_CLAIM_TOKEN` | Plex server claim token | `claim-xxxxxxxxxxxx` |
| `CERT_MANAGER_EMAIL` | Email for Let's Encrypt | `admin@christinepuk.net` |
| `MYSQL_ROOT_PASSWORD` | MySQL root password | Strong random password |
| `MYSQL_PASSWORD` | WordPress database password | Strong random password |

### Object Storage Secrets

| Secret Name | Description | Format |
|-------------|-------------|--------|
| `RCLONE_CONFIG` | Complete rclone configuration | See rclone config format below |

#### rclone Configuration Format
```ini
[linode]
type = s3
access_key_id = YOUR_ACCESS_KEY
endpoint = us-iad-1.linodeobjects.com
env_auth = false
provider = Other
region = us-iad-1
secret_access_key = YOUR_SECRET_KEY
```

## Setting Up Secrets

### 1. Encode kubeconfig
```bash
# Get your kubeconfig and encode it
cat ~/.kube/config | base64 -w 0
# Copy the output to KUBECONFIG secret
```

### 2. Generate secure passwords
```bash
# Generate MySQL passwords
openssl rand -base64 32  # For MYSQL_ROOT_PASSWORD
openssl rand -base64 32  # For MYSQL_PASSWORD
```

### 3. Get Plex claim token
1. Visit https://plex.tv/claim
2. Copy the claim token (valid for 4 minutes)
3. Add to `PLEX_CLAIM_TOKEN` secret

### 4. Prepare rclone config
```bash
# If you have existing rclone config
cat ~/.config/rclone/rclone.conf
# Copy the [linode] section to RCLONE_CONFIG secret
```

## Repository Structure

Your repository should have this structure:
```
capuk-k8s-infra/
├── .github/
│   └── workflows/
│       ├── deploy.yml           # Main deployment workflow
│       └── cleanup.yml          # Optional: cleanup old resources
├── charts/
│   └── multi-service/
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/
├── environments/
│   ├── production-values.yaml   # Production overrides
│   └── staging-values.yaml      # Staging overrides
├── scripts/
│   ├── setup-secrets.sh         # Secret setup helper
│   └── health-check.sh          # Post-deploy verification
└── README.md
```

## Security Best Practices

### 1. Environment Protection
Configure environment protection rules in GitHub:
- **Settings → Environments → production**
- Add required reviewers
- Add deployment branches rule (main only)

### 2. Secret Rotation
```bash
#!/bin/bash
# scripts/rotate-secrets.sh

# Update MySQL passwords
NEW_MYSQL_ROOT=$(openssl rand -base64 32)
NEW_MYSQL_PASS=$(openssl rand -base64 32)

# Update secrets in cluster
kubectl create secret generic mysql-root-secret \
  --from-literal=mysql-root-password="$NEW_MYSQL_ROOT" \
  --namespace=multi-service \
  --dry-run=client -o yaml | kubectl apply -f -

# Update GitHub secrets via API or manually
echo "New MySQL root password: $NEW_MYSQL_ROOT"
echo "New MySQL password: $NEW_MYSQL_PASS"
```

### 3. RBAC Configuration
Create service account for GitHub Actions:
```yaml
# k8s-rbac.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: github-actions
  namespace: multi-service
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: multi-service
  name: github-actions-role
rules:
- apiGroups: [""]
  resources: ["pods", "services", "secrets", "configmaps", "persistentvolumeclaims"]
  verbs: ["get", "list", "create", "update", "patch", "delete"]
- apiGroups: ["apps"]
  resources: ["deployments", "replicasets"]
  verbs: ["get", "list", "create", "update", "patch", "delete"]
- apiGroups: ["networking.k8s.io"]
  resources: ["ingresses"]
  verbs: ["get", "list", "create", "update", "patch", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: github-actions-binding
  namespace: multi-service
subjects:
- kind: ServiceAccount
  name: github-actions
  namespace: multi-service
roleRef:
  kind: Role
  name: github-actions-role
  apiGroup: rbac.authorization.k8s.io
```

## Alternative: External Secrets Operator

For enhanced security, use External Secrets Operator with Linode:

### 1. Install External Secrets Operator
```bash
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets -n external-secrets-system --create-namespace
```

### 2. Configure Linode Secret Store
```yaml
# external-secrets-store.yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: linode-secret-store
  namespace: multi-service
spec:
  provider:
    webhook:
      url: "https://api.linode.com/v4/object-storage/keys"
      headers:
        Authorization: "Bearer {{ .remoteRef.key }}"
      secrets:
        - name: linode-token
          key: token
---
apiVersion: v1
kind: Secret
metadata:
  name: linode-token
  namespace: multi-service
type: Opaque
data:
  token: <base64-encoded-linode-token>
```

### 3. Create External Secret
```yaml
# plex-external-secret.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: plex-secrets
  namespace: multi-service
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: linode-secret-store
    kind: SecretStore
  target:
    name: plex-secret
    creationPolicy: Owner
  data:
  - secretKey: claim-token
    remoteRef:
      key: plex-claim-token
```

## Monitoring and Observability

### 1. Deployment Notifications
Add Slack/Discord notifications to workflow:
```yaml
- name: Notify deployment status
  if: always()
  uses: 8398a7/action-slack@v3
  with:
    status: ${{ job.status }}
    webhook_url: ${{ secrets.SLACK_WEBHOOK }}
```

### 2. Health Checks
```bash
#!/bin/bash
# scripts/health-check.sh

echo "🔍 Running health checks..."

# Check pods
kubectl get pods -n multi-service

# Check ingress
kubectl get ingress -n multi-service

# Test endpoints
curl -f https://tv.christinepuk.net/web/index.html || echo "❌ Plex health check failed"
curl -f https://blog.christinepuk.net || echo "❌ Blog health check failed"

echo "✅ Health checks completed"
```

## Deployment Process

### Manual Deployment
```bash
# Trigger manual deployment
gh workflow run deploy.yml -f environment=production
```

### Automatic Deployment
- Push to `main` branch triggers production deployment
- Pull requests trigger validation only
- Manual dispatch allows environment selection

## Rollback Procedure
```bash
# Via GitHub Actions
gh workflow run deploy.yml -f environment=production

# Via Helm directly
helm rollback multi-service -n multi-service

# Emergency: Scale down problematic services
kubectl scale deployment multi-service-plex --replicas=0 -n multi-service
```

## Cost Optimization

### 1. Staging Environment
Use smaller resources for staging:
```yaml
# environments/staging-values.yaml
plex:
  resources:
    requests:
      cpu: 100m
      memory: 512Mi
    limits:
      cpu: 500m
      memory: 1Gi

wordpress:
  replicas: 1
  resources:
    requests:
      cpu: 50m
      memory: 128Mi
```

### 2. Scheduled Deployments
Deploy only during maintenance windows:
```yaml
on:
  schedule:
    - cron: '0 2 * * 0'  # Sundays at 2 AM UTC
```

This setup provides a robust, secure, and automated deployment pipeline for your Kubernetes infrastructure!