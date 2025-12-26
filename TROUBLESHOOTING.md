# Troubleshooting Guide

Comprehensive troubleshooting guide for Plex and WordPress deployments on Linode LKE.

## 🔍 General Diagnostics

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

## 🎬 Plex Troubleshooting

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

## 🔧 LKE-Specific Issues

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

## 📝 WordPress Troubleshooting

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

## 🗄️ Storage Troubleshooting

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

## 🌐 Networking Troubleshooting

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

## 🔒 SSL/TLS Troubleshooting

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

## 🔄 LKE-Specific Issues

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

## 🛠️ Emergency Procedures

### Force Pod Restart
```bash
# Delete pod (will be recreated by deployment)
kubectl delete pod <pod-name> -n multi-service

# Restart deployment (rolling restart)
kubectl rollout restart deployment/<deployment-name> -n multi-service
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

## 📞 Getting Help

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