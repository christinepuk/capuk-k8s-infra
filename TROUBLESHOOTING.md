# Troubleshooting Guide

Comprehensive troubleshooting guide for Plex and WordPress deployments on Linode LKE.

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
```bash
# Check MySQL logs
kubectl logs <mysql-pod-name> -n multi-service

# Test database connection
kubectl exec -it <wordpress-pod-name> -n multi-service -- wp db check
```

**Solutions:**
- **Wrong Credentials**: Verify MySQL auth settings in values file
- **Database Not Created**: Check if database initialization completed
- **Host Resolution**: Verify MySQL service name and port

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