# Troubleshooting Guide

Comprehensive troubleshooting guide for Plex, AudioBookShelf, and WordPress deployments on Linode LKE.

## Quick Fixes

### 🚨 Emergency Deployment Issues
If you're experiencing stuck pods, persistent volume conflicts, or deployment failures:

**Use the automated troubleshooting script:**
```bash
./scripts/troubleshoot.sh
```

This script will automatically:
- Clean up stuck/pending pods
- Scale down problematic replica sets
- Show current status
- Provide next steps

### 🔧 Safe Deployment Method
**Always use the safe deployment script for updates:**
```bash
./scripts/safe-deploy.sh
```

This prevents common deployment issues by:
- Cleaning up stuck pods before deployment
- Using proper Helm upgrade with wait flags
- Validating deployment success
- Handling persistent volume conflicts automatically

### 📋 Manual Troubleshooting
If automated scripts don't resolve the issue, continue with manual diagnostics below.

## General Diagnostics

### Check All Components
```bash
# Check all pods status
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

### View Pod Details
```bash
# Describe a specific pod
kubectl describe pod <pod-name> -n multi-service

# Check pod events
kubectl get events -n multi-service --sort-by='.lastTimestamp'

# Watch pods in real-time
kubectl get pods -n multi-service -w
```

## Volume Attachment and Deployment Issues

### Multiple Pods Stuck in ContainerCreating/Init States
**Problem**: After deployment updates, you see duplicate pods with some stuck in `ContainerCreating` or `Init:0/1` states
**Symptoms**:
```bash
NAME                                             READY   STATUS              RESTARTS   AGE
multi-service-mysql-site1-54bddcf555-7gkzx       0/1     ContainerCreating   0          27m
multi-service-mysql-site1-59d4fc7949-k85df       1/1     Running             0          112m
multi-service-plex-d66f56bd-mjv5q                0/2     Init:0/1            0          27m
multi-service-plex-5dcb4c7c9c-vknlg              2/2     Running             0          112m
```

**Root Cause**: Linode block storage volumes (RWO - ReadWriteOnce) can only be attached to one pod at a time. Multiple deployment revisions create new ReplicaSets that try to use the same PVCs.

**Diagnosis**:
```bash
# Check for volume attachment errors
kubectl describe pod <stuck-pod-name> -n multi-service

# Look for this error in events:
# Multi-Attach error for volume "pvc-xxxxx" Volume is already used by pod(s) <existing-pod>

# Check ReplicaSets - you'll see multiple with same PVC references
kubectl get rs -n multi-service -o wide

# Check PVC status
kubectl get pvc -n multi-service
```

**Solution**:

**Automated Fix (Recommended):**
```bash
# Use the troubleshooting script for automatic cleanup
./scripts/troubleshoot.sh
```

**Manual Fix (if needed):**
```bash
# Step 1: Delete stuck pods
kubectl delete pod <stuck-pod-name> -n multi-service --force

# Step 2: Scale down problematic ReplicaSets
kubectl scale rs <problematic-replicaset> --replicas=0 -n multi-service

# Step 3: Clean up unused ReplicaSets
kubectl delete rs $(kubectl get rs -n multi-service -o jsonpath='{.items[?(@.status.replicas==0)].metadata.name}') -n multi-service

# Step 4: Roll back deployments to working versions if needed
kubectl rollout undo deployment/<deployment-name> -n multi-service

# Step 5: Verify all pods are running
kubectl get pods -n multi-service
```

**Prevention**:
- **Always use `./scripts/safe-deploy.sh` for deployments** instead of direct `helm upgrade`
- All deployments now use `strategy: type: Recreate` to prevent volume conflicts
- Use `kubectl rollout status deployment/<name> -n multi-service` to monitor deployments
- Check `kubectl get pods -n multi-service` before deploying updates

## Plex Troubleshooting

### Common Plex Issues

#### Plex Pod Stuck in Pending
```bash
# Check node resources
kubectl describe nodes

# Check if PVC is bound
kubectl get pvc multi-service-plex-config multi-service-plex-media -n multi-service

# Check pod events
kubectl describe pod <plex-pod-name> -n multi-service
```

#### Plex Storage Access Mode Issues (LKE-Specific)
**Problem**: Plex PVCs fail to bind with "ReadWriteMany not supported"
**Solution**: Change all Plex storage to ReadWriteOnce:
```yaml
# In plex deployment template
spec:
  accessModes:
    - ReadWriteOnce  # Not ReadWriteMany
  storageClassName: linode-block-storage-retain
```

#### Plex Permission/Security Context Issues  
**Problem**: Plex container crashes with permission errors
**Solution**: Remove restrictive security contexts:
```yaml
# Remove or comment out in plex deployment:
# securityContext:
#   runAsNonRoot: true
#   runAsUser: 1001
#   fsGroup: 1001
```

#### 502 Bad Gateway for Plex
**Problem**: NGINX returns 502 when accessing tv.christinepuk.net
**Diagnosis**: 
```bash
# Check if Plex pod is running
kubectl get pods -n multi-service | grep plex

# Check Plex logs
kubectl logs <plex-pod-name> -n multi-service

# Test direct pod connection
kubectl port-forward <plex-pod-name> 32400:32400 -n multi-service
# Then test: curl -k https://localhost:32400/web

# Check service endpoints
kubectl get endpoints -n multi-service | grep plex
```

**Solutions**:
1. **If pod is not running**: Check logs for startup errors
2. **If pod is running but service unreachable**: Verify service selector matches pod labels
3. **If service works but ingress fails**: Check ingress configuration and SSL setup
4. **If getting 401 Unauthorized**: This is normal - Plex needs initial setup via web UI

## LKE-Specific Issues

### Resource Constraints on Small Clusters
**Problem**: Pods stuck in pending with "Insufficient CPU" errors
**Solution**: Reduce resource requests in lke-values.yaml:
```yaml
plex:
  resources:
    requests:
      cpu: 250m      # Reduced from 500m
      memory: 512Mi  # Reduced from 1Gi

wordpress:
  resources:
    requests:
      cpu: 100m      # Reduced from 200m  
      memory: 128Mi  # Reduced from 256Mi
```

### High-Resource Pod Scheduling Issues
**Problem**: Pod stuck pending with "0/4 nodes available: Insufficient cpu, memory" despite autoscaling
**Real Example**: Plex pod requesting 2 CPU cores on LKE nodes with only 1 CPU each
```bash
# Diagnosis commands
kubectl describe pod <pending-pod-name> -n multi-service | grep -A 5 Events
kubectl describe nodes | grep -A 5 "Allocatable\|Allocated resources"
```

**Root Cause**: Each LKE node only has 1 CPU core allocatable, but pod requested 2000m (2 cores)
**Solution**: Adjust resource requests to fit node capacity:
```yaml
# In lke-values.yaml
plex:
  resources:
    requests:
      memory: 1Gi                            # Reasonable for cluster capacity
      cpu: 300m                              # Fits within node capacity  
    limits:
      memory: 2Gi                            # Still plenty for Plex
      cpu: 800m                              # Max we can get on 1-core nodes
```

### PVC Storage Size Conflicts During Upgrades
**Problem**: Helm upgrade fails with "field is immutable" for PVC storage size
**Real Example**: 
```
Error: UPGRADE FAILED: cannot patch "multi-service-plex-media" with kind PersistentVolumeClaim: 
PersistentVolumeClaim "multi-service-plex-media" is invalid: spec: Forbidden: 
spec is immutable after creation except resources.requests for bound claims
```

**Solution**: Delete the conflicting PVC before upgrading:
```bash
# Check current PVCs
kubectl get pvc -n multi-service

# Delete the conflicting PVC (data will be preserved on PV)
kubectl delete pvc multi-service-plex-media -n multi-service

# Then run the helm upgrade
helm upgrade multi-service ./charts/multi-service -f lke-values.yaml -n multi-service
```

### Autoscaling Success But Pod Still Pending
**Problem**: Cluster autoscaler adds nodes but high-resource pod remains pending
**Real Example**: Pod requiring 2 CPU + 4Gi memory across 4 nodes with existing workloads
```bash
# Check total cluster capacity vs. requests
kubectl describe nodes | grep -E "(Allocatable|Allocated resources)" -A 3

# Output showing issue:
# Node 1: cpu: 950m (95%) memory: 672Mi (35%)  
# Node 2: cpu: 890m (89%) memory: 1158Mi (61%)
# Node 3: cpu: 750m (75%) memory: 768Mi (40%)
# Node 4: cpu: 250m (25%) memory: 0 (0%)
```

**Root Cause**: While cluster expanded, no single node had 2000m CPU available due to existing workload distribution
**Solution**: Reduce resource requests or implement pod affinity to consolidate workloads

### Storage Class Issues
**Problem**: PVCs remain pending with unsupported access modes
**Solution**: Use ReadWriteOnce and linode-block-storage-retain:
```yaml
storageClass: "linode-block-storage-retain"
accessModes:
  - ReadWriteOnce  # LKE only supports this mode
```
- **Insufficient Resources**: Scale down other pods or add more nodes
- **Storage Issues**: Verify storage class and PVC binding
- **Node Affinity**: Check if pod has specific node requirements

#### Plex Container Won't Start
```bash
# Check Plex logs
kubectl logs <plex-pod-name> -n multi-service

# Check if claim token is set
kubectl get deployment multi-service-plex -o yaml -n multi-service | grep -A5 -B5 PLEX_CLAIM
```

**Solutions:**
- **Missing Claim Token**: Add valid token from https://plex.tv/claim
- **Permission Issues**: Check security context and volume mounts
- **Port Conflicts**: Verify no other services using port 32400

#### Plex Remote Access Not Working
```bash
# Check ingress configuration
kubectl describe ingress multi-service-plex -n multi-service

# Test internal connectivity
kubectl exec -it <plex-pod-name> -n multi-service -- curl localhost:32400/web
```

**Solutions:**
- **DNS Issues**: Verify A record for tv.christinepuk.net
- **SSL Certificate**: Check cert-manager logs and certificate status
- **Ingress Configuration**: Verify NGINX ingress annotations

#### Plex Transcoding Issues
```bash
# Check resource limits
kubectl describe pod <plex-pod-name> -n multi-service | grep -A10 -B10 Resources

# Check for GPU availability (if using GPU transcoding)
kubectl describe nodes | grep -A5 -B5 gpu
```

**Solutions:**
- **CPU Limits**: Increase CPU limits in values file
- **Memory Pressure**: Increase memory limits
- **GPU Access**: Verify GPU drivers and device plugin installation

#### rclone Object Storage Authentication Failures
**Problem**: Plex can't access object storage with "SignatureDoesNotMatch" errors
**Real Example**: 
```
ERROR : capuk-media/: error listing: SignatureDoesNotMatch: The request signature we calculated does not match the signature you provided.
```

**Root Cause**: rclone config format incompatible with Linode Object Storage authentication
**Diagnosis Commands**:
```bash
# Check rclone configuration in secret
kubectl get secret rclone-secret -o yaml -n multi-service | base64 -d

# Test rclone connection from pod
kubectl exec -it <plex-pod-name> -c rclone -n multi-service -- rclone ls linode:capuk-media
```

**Solution**: Use flattened config format with explicit auth settings:
```yaml
# In lke-values.yaml - rclone config section
rclone:
  config: |
    [linode]
    type = s3
    access_key_id = YOUR_ACCESS_KEY
    endpoint = us-iad-1.linodeobjects.com
    env_auth = false                    # Critical: disable env auth
    provider = Other
    region = us-iad-1
    secret_access_key = YOUR_SECRET_KEY
```

#### rclone Mount Not Working in Init Container
**Problem**: Init container completes but rclone mount fails to work
**Real Example**: Pod shows "rclone setup complete" but mount directory empty
```bash
# Check rclone sidecar logs
kubectl logs <plex-pod-name> -c rclone -n multi-service

# Check if mount directory accessible
kubectl exec -it <plex-pod-name> -c plex -n multi-service -- ls -la /data
```

**Common Issues**:
1. **FUSE not available**: rclone needs `--allow-other` and privileged mode
2. **Mount directory permissions**: Check if directory is accessible between containers
3. **Shared volume missing**: Ensure emptyDir volume shared between containers

**Solution**: 
```yaml
# In plex deployment template
containers:
- name: rclone
  securityContext:
    privileged: true           # Required for FUSE
  command: ["/bin/sh", "-c"]
  args:
    - |
      echo "Starting rclone mount..."
      rclone mount linode:capuk-media /data \
        --allow-other \
        --allow-non-empty \
        --vfs-cache-mode writes \
        --daemon
  volumeMounts:
  - name: media-data
    mountPath: /data
- name: plex  
  volumeMounts:
  - name: media-data           # Same shared volume
    mountPath: /data
volumes:
- name: media-data
  emptyDir: {}                 # Shared between containers
```

## AudioBookShelf Troubleshooting

### Common AudioBookShelf Issues

#### AudioBookShelf Pod Stuck in Init State
**Problem**: AudioBookShelf pod shows `Init:0/1` and won't progress
**Symptoms**:
```bash
multi-service-audiobookshelf-6687f85f4c-77j6h   0/2     Init:0/1   0          2m
```

**Common Causes**:
1. **Volume attachment conflicts**: Old pods holding PVCs
2. **rclone init container failing**: Object storage connection issues
3. **Security context problems**: FUSE permissions

**Diagnosis**:
```bash
# Check pod events
kubectl describe pod <audiobookshelf-pod> -n multi-service

# Check init container logs
kubectl logs <audiobookshelf-pod> -c rclone-mount -n multi-service

# Check for volume conflicts
kubectl get pods -n multi-service -l app.kubernetes.io/component=audiobookshelf
```

**Solutions**:
```bash
# Remove old conflicting pods
kubectl delete pod <old-pod-name> -n multi-service

# Scale down old replicasets
kubectl scale replicaset <old-replicaset> --replicas=0 -n multi-service
```

#### AudioBookShelf rclone Mount Issues
**Problem**: rclone sidecar container fails to mount object storage
**Real Example**: Container shows "Transport endpoint is not connected"

**Diagnosis**:
```bash
# Check rclone container logs
kubectl logs <audiobookshelf-pod> -c rclone -n multi-service

# Test rclone connection
kubectl exec -it <audiobookshelf-pod> -c rclone -n multi-service -- rclone ls linode:capuk-media/Books
```

**Solutions**:
- Ensure same rclone configuration as Plex
- Verify `/data` mount permissions
- Check security context allows FUSE operations

#### AudioBookShelf Library Not Finding Files
**Problem**: Library scan shows no audiobooks despite files in object storage
**Cause**: Incorrect library paths or file organization

**Solutions**:
1. **Check mount path**: Files should be at `/data/Books/Audio`
2. **Verify file structure**: AudioBookShelf expects author/book folder structure
3. **Check permissions**: Files must be readable by AudioBookShelf user (uid 99)

```bash
# Check files in container
kubectl exec -it <audiobookshelf-pod> -c audiobookshelf -n multi-service -- ls -la /data/Books/Audio
```

## WordPress Troubleshooting

### Common WordPress Issues

#### WordPress Pod Init Container Stuck
```bash
# Check init container logs
kubectl logs <wordpress-pod-name> -c wait-for-mysql -n multi-service

# Check MySQL connectivity
kubectl exec -it <mysql-pod-name> -n multi-service -- mysql -u wordpress -p
```

**Solutions:**
- **MySQL Not Ready**: Wait for MySQL pod to be running
- **Network Policy**: Check if network policies are blocking communication
- **DNS Resolution**: Verify service names resolve correctly

#### WordPress Database Connection Errors
**Problem**: WordPress shows "Error establishing a database connection"
**Symptoms**: All WordPress sites return database connection errors despite MySQL pods running

**Root Cause**: Often caused by missing environment variable substitution in deployment configuration.

**Diagnosis**:
```bash
# Check MySQL logs
kubectl logs <mysql-pod-name> -n multi-service

# Check WordPress environment variables for unresolved placeholders
kubectl describe pod <wordpress-pod-name> -n multi-service | grep -A 8 "Environment:"
# Look for ${MYSQL_PASSWORD} instead of actual password value

# Test database connection
kubectl exec -it <wordpress-pod-name> -n multi-service -- wp db check
```

**Solutions:**
```bash
# 1. Ensure .env file exists and is sourced
source .env

# 2. Verify environment variables are set
echo "MySQL Password: $MYSQL_PASSWORD"

# 3. Deploy with proper variable substitution
envsubst < lke-values.yaml | helm upgrade multi-service ./charts/multi-service \\\n  -f - \\\n  --namespace multi-service

# 4. Wait for pods to restart with correct credentials
kubectl rollout status deployment/multi-service-wordpress-site1 -n multi-service
```

- **Wrong Credentials**: Verify MySQL auth settings in values file
- **Missing Variable Substitution**: Always use `envsubst` for files with `${VARIABLE}` placeholders
- **Database Not Created**: Check if database initialization completed
- **Host Resolution**: Verify MySQL service name and port

#### Emergency Database Access
```bash
# Root access to MySQL (for emergency administration)
kubectl exec -it deployment/multi-service-mysql-site1 -n multi-service -- \
  mysql -u root -p"YOUR_ROOT_PASSWORD"

# WordPress database access (for debugging application issues)
kubectl exec -it deployment/multi-service-mysql-site1 -n multi-service -- \
  mysql -u wordpress -p"YOUR_WORDPRESS_PASSWORD" wordpress

# Check database status
kubectl exec -it deployment/multi-service-mysql-site1 -n multi-service -- \
  mysql -u root -p"YOUR_ROOT_PASSWORD" -e "SHOW DATABASES;"

# Backup specific WordPress database
kubectl exec deployment/multi-service-mysql-site1 -n multi-service -- \
  mysqldump -u root -p"YOUR_ROOT_PASSWORD" wordpress > site1-backup.sql

# Restore database from backup
kubectl exec -i deployment/multi-service-mysql-site1 -n multi-service -- \
  mysql -u root -p"YOUR_ROOT_PASSWORD" wordpress < site1-backup.sql
```

**Password Sources:**
- Root password: From `MYSQL_ROOT_PASSWORD` GitHub Secret
- WordPress password: From `MYSQL_PASSWORD` GitHub Secret  
- Local backup: Check `mysql-secrets-backup.txt` (if available)

#### WordPress Database Reset
```bash
# Reset WordPress database (DESTRUCTIVE - backup first!)
kubectl exec -it deployment/multi-service-mysql-site1 -n multi-service -- \
  mysql -u root -p"YOUR_ROOT_PASSWORD" -e "
    DROP DATABASE wordpress;
    CREATE DATABASE wordpress;
    GRANT ALL PRIVILEGES ON wordpress.* TO 'wordpress'@'%';
    FLUSH PRIVILEGES;"

# Restart WordPress pod to reinitialize
kubectl delete pod -l app.kubernetes.io/name=wordpress,app.kubernetes.io/instance=site1 -n multi-service
```

#### WordPress Site Loading Issues
```bash
# Check WordPress logs
kubectl logs <wordpress-pod-name> -n multi-service

# Check ingress status
kubectl describe ingress <wordpress-ingress-name> -n multi-service
```

**Solutions:**
- **PHP Errors**: Check WordPress logs for PHP errors
- **Plugin Issues**: Disable plugins via WordPress CLI in pod
- **Theme Problems**: Switch to default theme to test

### WordPress Performance Issues
```bash
# Check resource usage
kubectl top pods -n multi-service

# Monitor WordPress pod metrics
kubectl exec -it <wordpress-pod-name> -n multi-service -- top
```

**Solutions:**
- **Resource Limits**: Increase CPU/memory limits
- **Plugin Optimization**: Remove unnecessary plugins
- **Caching**: Implement WordPress caching plugins

## Storage Troubleshooting

### PVC Issues
```bash
# Check PVC status
kubectl describe pvc <pvc-name> -n multi-service

# Check storage class
kubectl get storageclass

# Check CSI driver logs
kubectl logs -n kube-system -l app=csi-linode-controller
```

**Common PVC Problems:**
- **Pending PVCs**: Storage class not available or insufficient quota
- **Mount Issues**: Node doesn't have required CSI driver
- **Permission Errors**: Wrong fsGroup or security context

### Storage Performance
```bash
# Test storage performance inside pod
kubectl exec -it <pod-name> -n multi-service -- dd if=/dev/zero of=/tmp/test bs=1M count=1024

# Check storage usage
kubectl exec -it <pod-name> -n multi-service -- df -h
```

## Networking Troubleshooting

### Ingress Issues
```bash
# Check ingress controller status
kubectl get pods -n ingress-nginx

# Check ingress controller logs
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller

# Test ingress backend
kubectl get endpoints -n multi-service
```

**Common Ingress Problems:**
- **502/503 Errors**: Backend pods not ready or service misconfiguration
- **404 Errors**: Ingress path not matching or wrong service name
- **SSL Issues**: Certificate not issued or wrong domain

### DNS Issues
```bash
# Test DNS resolution from pod
kubectl exec -it <pod-name> -n multi-service -- nslookup tv.christinepuk.net

# Check external DNS
dig tv.christinepuk.net
```

**Solutions:**
- **A Record Missing**: Add DNS A record pointing to LoadBalancer IP
- **DNS Propagation**: Wait up to 48 hours for DNS changes
- **Wrong IP**: Verify LoadBalancer IP is correct

## SSL/TLS Troubleshooting

### Certificate Issues
```bash
# Check certificate status
kubectl get certificates -n multi-service

# Check cert-manager logs
kubectl logs -n cert-manager deployment/cert-manager

# Check certificate details
kubectl describe certificate <cert-name> -n multi-service
```

**Common Certificate Problems:**
- **HTTP-01 Challenge Failed**: Ingress not routing correctly to cert-manager
- **Rate Limiting**: Too many certificate requests to Let's Encrypt
- **Domain Validation**: DNS not pointing to correct LoadBalancer IP

### HTTPS Redirect Issues
```bash
# Test HTTP vs HTTPS
curl -I http://blog.christinepuk.net
curl -I https://blog.christinepuk.net

# Check ingress annotations
kubectl get ingress <ingress-name> -o yaml -n multi-service
```

## ⚡ Performance Troubleshooting

### Resource Constraints
```bash
# Check node resource usage
kubectl top nodes

# Check pod resource usage
kubectl top pods -n multi-service

# Check cluster autoscaler logs
kubectl logs -n kube-system deployment/cluster-autoscaler
```

### Memory Issues
```bash
# Check for OOMKilled pods
kubectl get pods -n multi-service | grep -E "(OOMKilled|Evicted)"

# Check memory usage in pod
kubectl exec -it <pod-name> -n multi-service -- free -h
```

**Solutions:**
- **Increase Memory Limits**: Update values file with higher limits
- **Optimize Applications**: Reduce memory usage in applications
- **Scale Horizontally**: Add more replicas instead of increasing resources

## LKE-Specific Issues

### LoadBalancer Not Getting External IP
```bash
# Check LoadBalancer service
kubectl get svc -n ingress-nginx ingress-nginx-controller

# Check NodeBalancer in Linode Cloud Manager
# Go to Cloud Manager -> NodeBalancers
```

**Solutions:**
- **Service Type**: Ensure service type is LoadBalancer
- **LKE Limits**: Check account limits for NodeBalancers
- **Region Issues**: Verify LKE cluster region supports NodeBalancers

### Node Issues
```bash
# Check node status
kubectl get nodes -o wide

# Check node conditions
kubectl describe node <node-name>

# Check kubelet logs
kubectl logs <node-name> -n kube-system
```

### Cluster Autoscaler Issues
```bash
# Check autoscaler status
kubectl get deployment cluster-autoscaler -n kube-system

# Check autoscaler logs
kubectl logs deployment/cluster-autoscaler -n kube-system
```

## Emergency Procedures

### Force Pod Restart
```bash
# Delete pod (will be recreated by deployment)
kubectl delete pod <pod-name> -n multi-service

# Restart deployment (rolling restart)
kubectl rollout restart deployment/<deployment-name> -n multi-service
```

### Multiple Failed/Completed Pods Cluttering Namespace
**Problem**: Many old completed pods remain after multiple deployment attempts
**Real Example**:
```bash
kubectl get pods -n multi-service | grep plex
# Shows multiple Completed pods: multi-service-plex-587d5cfdd5-xxxxx (0/2 Completed)
```

**Cleanup Commands**:
```bash
# Remove all completed pods
kubectl delete pods --field-selector=status.phase=Succeeded -n multi-service

# Remove all failed pods  
kubectl delete pods --field-selector=status.phase=Failed -n multi-service

# Force cleanup of multiple old replica sets
kubectl get replicasets -n multi-service | grep "plex.*0.*0.*0" | awk '{print $1}' | xargs kubectl delete rs -n multi-service
```

### Pod Stuck in Init Phase During Resource Changes
**Problem**: New pod created during resource scaling stuck in "Init:0/1" state
**Real Example**: Pod scheduled to node but init container not progressing
```bash
# Check pod scheduling
kubectl describe pod <pod-name> -n multi-service | grep -A 5 Events

# Expected output for successful scheduling:
# Normal  Scheduled  25s   default-scheduler  Successfully assigned multi-service/multi-service-plex-xxx to lke549969-799077-xxx

# Check init container logs
kubectl logs <pod-name> -c <init-container-name> -n multi-service
```

**Solutions**:
1. **Wait for Init Container**: rclone setup can take 30-60 seconds
2. **Check Resource Availability**: Ensure node has sufficient resources for init + main containers
3. **Verify Init Logic**: Check if init container is actually progressing through steps

### Successful Resource Scaling Verification
**Problem**: How to confirm resource scaling worked correctly
**Real Example Process**:
```bash
# 1. Check pod transition from pending to running
kubectl get pods -n multi-service | grep plex | grep -v Completed

# Expected progression:
# multi-service-plex-xxx  0/2  Pending     0  30s  (old high-resource pod)
# multi-service-plex-yyy  0/2  Init:0/1    0  10s  (new pod with correct resources)  
# multi-service-plex-yyy  2/2  Running     0  45s  (fully started)

# 2. Verify resource allocation
kubectl describe pod <running-pod-name> -n multi-service | grep -A 5 -B 5 "Requests\|Limits"

# 3. Confirm both containers running
kubectl get pods <pod-name> -o jsonpath='{.status.containerStatuses[*].name}' -n multi-service
# Should show: plex rclone

# 4. Test functionality
kubectl logs <pod-name> -c rclone -n multi-service | tail -5
kubectl port-forward svc/multi-service-plex 32400:32400 -n multi-service
```

### Emergency Rollback
```bash
# Check rollout history
kubectl rollout history deployment/<deployment-name> -n multi-service

# Rollback to previous version
kubectl rollout undo deployment/<deployment-name> -n multi-service
```

### Clean Up Failed Deployments
```bash
# Delete failed pods
kubectl delete pods --field-selector=status.phase=Failed -n multi-service

# Force delete stuck resources
kubectl patch pod <pod-name> -p '{"metadata":{"finalizers":null}}' -n multi-service
```

## Getting Help

### Useful Commands for Support
```bash
# Generate cluster info dump
kubectl cluster-info dump --output-directory=/tmp/cluster-dump

# Get all resources in namespace
kubectl get all -n multi-service

# Export current configuration
helm get values multi-service -n multi-service > current-values.yaml
```

### Log Collection
```bash
#!/bin/bash
# Collect logs script
mkdir -p troubleshooting-logs/$(date +%Y%m%d)
cd troubleshooting-logs/$(date +%Y%m%d)

# Pod logs
kubectl logs -l app.kubernetes.io/instance=multi-service -n multi-service > pod-logs.txt

# Events
kubectl get events -n multi-service --sort-by='.lastTimestamp' > events.txt

# Resource status
kubectl get all -n multi-service -o wide > resources.txt

# PVC status
kubectl describe pvc -n multi-service > pvc-status.txt

echo "Logs collected in troubleshooting-logs/$(date +%Y%m%d)/"
```

### External Resources
- **LKE Documentation**: https://www.linode.com/docs/kubernetes/
- **Plex Docker Issues**: https://github.com/plexinc/pms-docker/issues
- **WordPress Docker Issues**: https://github.com/docker-library/wordpress/issues
- **Kubernetes Troubleshooting**: https://kubernetes.io/docs/tasks/debug-application-cluster/