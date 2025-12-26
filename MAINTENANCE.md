# Kubernetes Maintenance Guide

Complete maintenance guide for managing your LKE cluster, Plex, and WordPress deployments.

## Manual Deployment Upgrades

### Prerequisites
Ensure you have local access to the cluster and repository:
```bash
# Verify kubectl access
kubectl get pods -n multi-service

# Ensure you're in the project directory
cd /path/to/capuk-k8s-infra

# Source environment variables (REQUIRED)
source .env

# Verify critical environment variables are set
echo "MySQL Password: $MYSQL_PASSWORD"
echo "Plex Token: $PLEX_CLAIM_TOKEN"

# Check current Helm release status
helm status multi-service -n multi-service
```

**Important**: The `lke-values.yaml` file uses environment variable substitution (e.g., `${MYSQL_PASSWORD}`). You must source the `.env` file before running any Helm commands, or the deployment will use empty values for critical configuration like database passwords.

### Standard Helm Upgrade Process
```bash
# 1. Update configuration files (if needed)
# Edit lke-values.yaml or charts/multi-service/values.yaml

# 2. Run the upgrade with proper variable substitution
envsubst < lke-values.yaml | helm upgrade multi-service ./charts/multi-service \
  -f - \
  --namespace multi-service

# 3. Monitor the rollout
kubectl rollout status deployment/multi-service-plex -n multi-service
kubectl rollout status deployment/multi-service-wordpress-site1 -n multi-service
kubectl rollout status deployment/multi-service-wordpress-site2 -n multi-service
kubectl rollout status deployment/multi-service-wordpress-site3 -n multi-service

# 4. Verify all pods are running
kubectl get pods -n multi-service

# 5. Test services
kubectl get ingress -n multi-service
```

### Configuration-Only Updates (Faster)
For changes that don't require pod restarts (e.g., ingress, service configs):
```bash
# Apply specific template updates
envsubst < lke-values.yaml | helm upgrade multi-service ./charts/multi-service \
  -f - \
  --namespace multi-service \
  --reuse-values

# Or restart deployments to pick up config changes
kubectl rollout restart deployment/multi-service-plex -n multi-service
```

### Upgrade with Secret Updates
If updating secrets (Plex token, storage credentials):
```bash
# 1. Update secrets first
kubectl create secret generic multi-service-rclone-config \
  --from-literal=rclone.conf="$(cat rclone.conf)" \
  --namespace multi-service \
  --dry-run=client -o yaml | kubectl apply -f -

# 2. Then upgrade Helm chart
envsubst < lke-values.yaml | helm upgrade multi-service ./charts/multi-service \
  -f - \
  --namespace multi-service

# 3. Restart pods to pick up new secrets
kubectl rollout restart deployment/multi-service-plex -n multi-service
```

### Rollback if Issues Occur
```bash
# Check rollout history
helm history multi-service -n multi-service

# Rollback to previous version
helm rollback multi-service <revision-number> -n multi-service

# Or rollback to previous revision
helm rollback multi-service -n multi-service

# Monitor rollback
kubectl get pods -n multi-service -w
```

### Common Upgrade Issues and Solutions
- **Volume attachment conflicts**: See [TROUBLESHOOTING.md](TROUBLESHOOTING.md#volume-attachment-and-deployment-issues)
- **Resource constraints**: Check cluster capacity before upgrading
- **PVC size changes**: These require PVC deletion/recreation (see troubleshooting guide)

## Cluster Scaling

### Manual Cluster Scaling
```bash
# Check current node count
kubectl get nodes

# Scale up cluster (via Linode Cloud Manager)
# 1. Go to Kubernetes -> Your Cluster -> Resize
# 2. Adjust node pool size
# 3. Wait 3-5 minutes for new nodes

# Verify new nodes
kubectl get nodes -o wide
```

### Automatic Scaling (Cluster Autoscaler)
```bash
# Check if autoscaler is installed
kubectl get deployment cluster-autoscaler -n kube-system

# Install cluster autoscaler if missing
curl -o cluster-autoscaler-autodiscover.yaml https://raw.githubusercontent.com/kubernetes/autoscaler/master/cluster-autoscaler/cloudprovider/linode/examples/cluster-autoscaler-autodiscover.yaml

# Edit with your cluster name and deploy
kubectl apply -f cluster-autoscaler-autodiscover.yaml

# Check autoscaler logs
kubectl logs deployment/cluster-autoscaler -n kube-system -f
```

### Pod-Level Scaling
```bash
# Scale specific deployments
kubectl scale deployment multi-service-plex --replicas=2 -n multi-service
kubectl scale deployment multi-service-wordpress-site1 --replicas=3 -n multi-service

# Check scaling status
kubectl get deployment -n multi-service

# Enable Horizontal Pod Autoscaler (HPA)
kubectl autoscale deployment multi-service-wordpress-site1 --cpu-percent=70 --min=1 --max=5 -n multi-service

# Check HPA status
kubectl get hpa -n multi-service
```

### Resource Limit Adjustments
```bash
# Update resource limits in values file
# Edit lke-values.yaml:
plex:
  resources:
    requests:
      cpu: 500m
      memory: 1Gi
    limits:
      cpu: 1000m      # Increased
      memory: 2Gi     # Increased

# Apply changes
helm upgrade multi-service ./charts/multi-service -f lke-values.yaml -n multi-service

# Verify new limits
kubectl describe pod <plex-pod-name> -n multi-service | grep -A 5 -B 5 Resources
```

## Log Management

### Application Logs
```bash
# Plex logs
kubectl logs deployment/multi-service-plex -n multi-service
kubectl logs deployment/multi-service-plex -c plex -n multi-service    # Main container
kubectl logs deployment/multi-service-plex -c rclone -n multi-service  # Sidecar

# WordPress logs
kubectl logs deployment/multi-service-wordpress-site1 -n multi-service

# MySQL logs
kubectl logs deployment/multi-service-mysql-site1 -n multi-service

# Follow logs in real-time
kubectl logs -f deployment/multi-service-plex -n multi-service
```

### System Logs
```bash
# Ingress controller logs
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller -f

# Cert-manager logs
kubectl logs -n cert-manager deployment/cert-manager -f

# Cluster autoscaler logs
kubectl logs -n kube-system deployment/cluster-autoscaler -f

# Node logs (requires SSH access)
# Get node IP first
kubectl get nodes -o wide
# SSH to node: ssh root@<node-ip>
# View kubelet logs: journalctl -u kubelet -f
```

### Log Aggregation Setup
```bash
# Install ELK stack for log aggregation
helm repo add elastic https://helm.elastic.co
helm repo update

# Install Elasticsearch
helm install elasticsearch elastic/elasticsearch -n logging --create-namespace

# Install Kibana
helm install kibana elastic/kibana -n logging

# Install Filebeat
helm install filebeat elastic/filebeat -n logging

# Access Kibana dashboard
kubectl port-forward svc/kibana-kibana 5601:5601 -n logging
# Open: http://localhost:5601
```

### Log Rotation and Cleanup
```bash
# Clean up old logs (runs on each node)
kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: CronJob
metadata:
  name: log-cleanup
  namespace: kube-system
spec:
  schedule: "0 2 * * *"  # Daily at 2 AM
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: log-cleanup
            image: alpine:latest
            command:
            - /bin/sh
            - -c
            - |
              echo "Cleaning up logs older than 7 days..."
              find /var/log/pods -name "*.log" -mtime +7 -delete
              find /var/log/containers -name "*.log" -mtime +7 -delete
            volumeMounts:
            - name: var-log
              mountPath: /var/log
          volumes:
          - name: var-log
            hostPath:
              path: /var/log
          restartPolicy: OnFailure
          nodeSelector:
            kubernetes.io/os: linux
EOF
```

## rclone Debugging

### Check rclone Configuration
```bash
# View rclone secret
kubectl get secret rclone-secret -o yaml -n multi-service

# Decode and view config
kubectl get secret rclone-secret -o jsonpath='{.data.rclone\.conf}' -n multi-service | base64 -d

# Expected working config format:
# [linode]
# type = s3
# access_key_id = YOUR_KEY
# endpoint = us-iad-1.linodeobjects.com
# env_auth = false
# provider = Other
# region = us-iad-1
# secret_access_key = YOUR_SECRET
```

### Test rclone Connectivity
```bash
# Test from rclone sidecar container
kubectl exec -it deployment/multi-service-plex -c rclone -n multi-service -- rclone ls linode:capuk-media

# Test configuration
kubectl exec -it deployment/multi-service-plex -c rclone -n multi-service -- rclone config show

# Test mount point
kubectl exec -it deployment/multi-service-plex -c plex -n multi-service -- ls -la /data

# Check mount status
kubectl exec -it deployment/multi-service-plex -c rclone -n multi-service -- mount | grep fuse
```

### rclone Performance Tuning
```bash
# Check current rclone mount options
kubectl exec -it deployment/multi-service-plex -c rclone -n multi-service -- ps aux | grep rclone

# Update mount command with performance options (in deployment template):
rclone mount linode:capuk-media /data \
  --allow-other \
  --allow-non-empty \
  --vfs-cache-mode writes \
  --vfs-cache-max-age 1h \
  --vfs-cache-max-size 2G \
  --buffer-size 64M \
  --daemon

# Monitor rclone stats
kubectl exec -it deployment/multi-service-plex -c rclone -n multi-service -- rclone rc core/stats
```

### rclone Troubleshooting Commands
```bash
# Check rclone logs with debug
kubectl logs deployment/multi-service-plex -c rclone -n multi-service --tail=50

# Interactive rclone debugging
kubectl exec -it deployment/multi-service-plex -c rclone -n multi-service -- /bin/sh

# Inside container:
rclone version
rclone config show linode
rclone ls linode:capuk-media --max-depth 1
rclone check /data linode:capuk-media --one-way

# Test upload/download
echo "test" > /tmp/test.txt
rclone copy /tmp/test.txt linode:capuk-media/test/
rclone copy linode:capuk-media/test/test.txt /tmp/downloaded.txt
```

### Fix Common rclone Issues
```bash
# Issue: Mount disappears after container restart
# Solution: Add mount check in startup script
kubectl patch deployment multi-service-plex -n multi-service --patch='
spec:
  template:
    spec:
      containers:
      - name: rclone
        livenessProbe:
          exec:
            command:
            - /bin/sh
            - -c
            - "test -d /data && ls /data > /dev/null"
          initialDelaySeconds: 30
          periodSeconds: 60'

# Issue: Permission denied accessing mounted files
# Solution: Add proper security context
kubectl patch deployment multi-service-plex -n multi-service --patch='
spec:
  template:
    spec:
      securityContext:
        fsGroup: 1000
      containers:
      - name: rclone
        securityContext:
          privileged: true'
```

## Node Management

### When to Restart Nodes
**Restart nodes when:**
- Node shows "NotReady" status for >5 minutes
- High memory/disk usage (>90%) that won't clear
- Kernel updates requiring reboot
- Network connectivity issues
- Kubelet service failures

### Safe Node Restart Process
```bash
# 1. Check node status
kubectl get nodes

# 2. Cordon the node (prevent new pods)
kubectl cordon <node-name>

# 3. Drain the node (move existing pods)
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data --force

# 4. Restart node via Linode Cloud Manager
# Go to Linodes -> Select node -> Reboot

# 5. Wait for node to come back online
kubectl get nodes -w

# 6. Uncordon the node
kubectl uncordon <node-name>

# 7. Verify pods redistribute
kubectl get pods -n multi-service -o wide
```

### When to Delete Nodes
**Delete nodes when:**
- Persistent hardware issues
- Downsizing cluster
- Node type no longer suitable
- Corrupted system requiring rebuild

### Safe Node Deletion Process
```bash
# 1. Ensure cluster has spare capacity
kubectl top nodes
kubectl describe nodes | grep -A 5 "Allocated resources"

# 2. Cordon and drain the node
kubectl cordon <node-name>
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data --force --timeout=300s

# 3. Delete from Kubernetes
kubectl delete node <node-name>

# 4. Delete from Linode Cloud Manager
# Go to Kubernetes -> Cluster -> Node Pools -> Remove node

# 5. Verify cluster stability
kubectl get nodes
kubectl get pods -n multi-service
```

### Emergency Node Recovery
```bash
# If node is completely unresponsive:

# 1. Force delete pods from bad node
kubectl get pods --all-namespaces --field-selector spec.nodeName=<bad-node-name>
kubectl delete pod <pod-name> -n <namespace> --grace-period=0 --force

# 2. Remove node from cluster immediately
kubectl delete node <bad-node-name> --grace-period=0 --force

# 3. Create replacement node
# Via Linode Cloud Manager: Add new node to pool

# 4. Verify workloads redistribute
kubectl get pods -n multi-service -o wide
```

## Kubernetes Upgrades

### Pre-Upgrade Checklist
```bash
# 1. Backup current cluster state
kubectl get all --all-namespaces -o yaml > cluster-backup-$(date +%Y%m%d).yaml

# 2. Check current version
kubectl version --short

# 3. Check node versions
kubectl get nodes -o wide

# 4. Review upgrade path (only upgrade one minor version at a time)
# Example: 1.28 -> 1.29 -> 1.30 (not 1.28 -> 1.30 directly)

# 5. Check application compatibility
# Review: https://kubernetes.io/docs/reference/using-api/deprecation-guide/
```

### LKE Kubernetes Upgrade Process
```bash
# 1. Via Linode Cloud Manager:
# Go to Kubernetes -> Your Cluster -> Settings -> Upgrade Available

# 2. Or via Linode CLI:
linode-cli lke clusters-list
linode-cli lke cluster-upgrade <cluster-id> --k8s_version 1.29

# 3. Monitor upgrade progress
kubectl get nodes -w

# 4. Verify all nodes upgraded
kubectl get nodes -o wide

# 5. Check system pods
kubectl get pods -n kube-system

# 6. Test applications
kubectl get pods -n multi-service
helm test multi-service -n multi-service
```

### Post-Upgrade Validation
```bash
# 1. Check cluster health
kubectl cluster-info
kubectl get componentstatuses

# 2. Verify all namespaces
kubectl get pods --all-namespaces

# 3. Test ingress connectivity
curl -I https://plex.christinepuk.net
curl -I https://blog.christinepuk.net

# 4. Check PVC functionality
kubectl get pvc -n multi-service

# 5. Verify log collection still works
kubectl logs deployment/multi-service-plex -n multi-service --tail=10

# 6. Test scaling works
kubectl scale deployment multi-service-wordpress-site1 --replicas=2 -n multi-service
kubectl get pods -n multi-service
kubectl scale deployment multi-service-wordpress-site1 --replicas=1 -n multi-service
```

### Rollback Strategy (if upgrade fails)
```bash
# 1. LKE doesn't support direct rollback, but you can:
# - Restore from etcd backup (if configured)
# - Redeploy applications from working configuration

# 2. Restore application state
kubectl apply -f cluster-backup-$(date +%Y%m%d).yaml

# 3. Restore Helm releases
helm list -n multi-service
helm rollback multi-service <revision-number> -n multi-service

# 4. For complete cluster recovery, create new cluster:
# - Create new LKE cluster with previous K8s version
# - Restore data from backups
# - Redeploy applications
```

## Data Export and Backup

### Database Backups
```bash
# Create backup directory
mkdir -p backups/$(date +%Y%m%d)

# MySQL backups for WordPress
for site in site1 site2 site3; do
  echo "Backing up WordPress $site database..."
  kubectl exec deployment/multi-service-mysql-$site -n multi-service -- \
    mysqldump -u wordpress -pwordpress wordpress | \
    gzip > backups/$(date +%Y%m%d)/wordpress-$site-$(date +%H%M).sql.gz
done

# Verify backup files
ls -lh backups/$(date +%Y%m%d)/
```

### Plex Configuration Backup
```bash
# Backup Plex database and configuration
kubectl exec deployment/multi-service-plex -c plex -n multi-service -- \
  tar czf - /config | \
  cat > backups/$(date +%Y%m%d)/plex-config-$(date +%H%M).tar.gz

# Backup Plex preferences (lightweight)
kubectl exec deployment/multi-service-plex -c plex -n multi-service -- \
  cat /config/Library/Application\ Support/Plex\ Media\ Server/Preferences.xml > \
  backups/$(date +%Y%m%d)/plex-preferences-$(date +%H%M).xml
```

### Persistent Volume Snapshots
```bash
# List all PVCs
kubectl get pvc -n multi-service

# Create snapshots via Linode Block Storage
# Note: This requires manual process via Cloud Manager
# 1. Go to Volumes -> Select volume -> Create Snapshot
# 2. Or use Linode CLI:

# Get volume IDs
linode-cli volumes list

# Create snapshot
linode-cli volumes snapshot <volume-id> --label "plex-config-backup-$(date +%Y%m%d)"
```

### Complete Cluster Configuration Export
```bash
# Export all Kubernetes resources
mkdir -p backups/$(date +%Y%m%d)/k8s-resources

# Export by namespace
kubectl get all -n multi-service -o yaml > backups/$(date +%Y%m%d)/k8s-resources/multi-service.yaml
kubectl get configmaps -n multi-service -o yaml > backups/$(date +%Y%m%d)/k8s-resources/configmaps.yaml
kubectl get secrets -n multi-service -o yaml > backups/$(date +%Y%m%d)/k8s-resources/secrets.yaml
kubectl get pvc -n multi-service -o yaml > backups/$(date +%Y%m%d)/k8s-resources/pvc.yaml

# Export Helm values
helm get values multi-service -n multi-service > backups/$(date +%Y%m%d)/helm-values.yaml

# Export ingress and certificates
kubectl get ingress --all-namespaces -o yaml > backups/$(date +%Y%m%d)/k8s-resources/ingress.yaml
kubectl get certificates --all-namespaces -o yaml > backups/$(date +%Y%m%d)/k8s-resources/certificates.yaml
```

### Object Storage Data Management
```bash
# List all files in object storage
kubectl exec deployment/multi-service-plex -c rclone -n multi-service -- \
  rclone ls linode:capuk-media > backups/$(date +%Y%m%d)/object-storage-inventory.txt

# Sync critical data to local backup
kubectl exec deployment/multi-service-plex -c rclone -n multi-service -- \
  rclone sync linode:capuk-media/Movies /backup/movies --progress

# Create object storage backup bucket
kubectl exec deployment/multi-service-plex -c rclone -n multi-service -- \
  rclone sync linode:capuk-media linode:capuk-media-backup-$(date +%Y%m%d) --progress
```

### Automated Backup Script
```bash
#!/bin/bash
# save as: backup-cluster.sh

BACKUP_DIR="backups/$(date +%Y%m%d)"
mkdir -p "$BACKUP_DIR"

echo "Starting cluster backup..."

# Database backups
echo "Backing up databases..."
for site in site1 site2 site3; do
  kubectl exec deployment/multi-service-mysql-$site -n multi-service -- \
    mysqldump -u wordpress -pwordpress wordpress | \
    gzip > "$BACKUP_DIR/wordpress-$site.sql.gz"
done

# Plex configuration
echo "Backing up Plex config..."
kubectl exec deployment/multi-service-plex -c plex -n multi-service -- \
  tar czf - /config > "$BACKUP_DIR/plex-config.tar.gz"

# Kubernetes resources
echo "Backing up K8s resources..."
kubectl get all -n multi-service -o yaml > "$BACKUP_DIR/k8s-all.yaml"
helm get values multi-service -n multi-service > "$BACKUP_DIR/helm-values.yaml"

# Object storage inventory
echo "Creating storage inventory..."
kubectl exec deployment/multi-service-plex -c rclone -n multi-service -- \
  rclone ls linode:capuk-media > "$BACKUP_DIR/storage-inventory.txt"

# Compress final backup
echo "Compressing backup..."
tar czf "cluster-backup-$(date +%Y%m%d-%H%M).tar.gz" "$BACKUP_DIR"

echo "Backup complete: cluster-backup-$(date +%Y%m%d-%H%M).tar.gz"

# Upload to remote storage (optional)
# rclone copy "cluster-backup-$(date +%Y%m%d-%H%M).tar.gz" remote:backups/
```

### Recovery Procedures
```bash
# Restore WordPress database
gunzip -c backups/20250101/wordpress-site1.sql.gz | \
  kubectl exec -i deployment/multi-service-mysql-site1 -n multi-service -- \
  mysql -u wordpress -pwordpress wordpress

# Restore Plex configuration
kubectl exec -i deployment/multi-service-plex -c plex -n multi-service -- \
  tar xzf - -C / < backups/20250101/plex-config.tar.gz

# Restore Kubernetes resources (selective)
kubectl apply -f backups/20250101/k8s-all.yaml

# Restart affected deployments
kubectl rollout restart deployment/multi-service-plex -n multi-service
kubectl rollout restart deployment/multi-service-wordpress-site1 -n multi-service
```

## Monitoring and Alerting

### Set Up Basic Monitoring
```bash
# Install Prometheus and Grafana
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace

# Access Grafana
kubectl port-forward svc/monitoring-grafana 3000:80 -n monitoring
# Default: admin/prom-operator

# Access Prometheus  
kubectl port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090 -n monitoring
```

### Key Metrics to Monitor
```bash
# Node resource usage
kubectl top nodes

# Pod resource usage
kubectl top pods -n multi-service

# Storage usage
kubectl exec deployment/multi-service-plex -c plex -n multi-service -- df -h

# Network connectivity tests
kubectl run --rm -i --tty debug --image=nicolaka/netshoot -- /bin/bash
# Inside pod: nslookup kubernetes.default, ping 8.8.8.8, etc.
```

This maintenance guide provides comprehensive procedures for keeping your cluster healthy and data safe. Run these operations during maintenance windows and always test in a staging environment first when possible.