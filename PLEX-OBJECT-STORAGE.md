# Plex Object Storage Setup with rclone

This guide shows how to configure Plex to use object storage (like Linode Object Storage) via rclone instead of local persistent volumes.

## 🗂️ Prerequisites

1. **Object Storage Bucket**: Create a bucket in your object storage provider OR use an existing bucket
2. **Access Credentials**: Get access key and secret key for your bucket
3. **Media Files**: Upload your media to the bucket (optional - can be done later)

## 📦 Using an Existing Object Storage Bucket

If you already have media files in object storage (like an existing Linode Object Storage bucket), you can connect Plex directly to it.

### Step 0: Verify Your Existing Bucket

First, verify your existing bucket structure and contents:

1. **Check your bucket name and region** in your object storage provider
2. **Verify access credentials** have read/write permissions to the bucket
3. **Review your media organization** - Plex works best with organized folder structures

#### Test Your Existing Bucket Access

Before configuring Plex, test rclone access to your existing bucket:

```bash
# Test with your existing rclone config (if you have one)
rclone ls your-remote:your-bucket-name | head -10

# Example with working configuration:
rclone ls linode:capuk-media | head -10
# Should show:
#  34338622 Books/Audio/1772_Sun Tzu_THE ART OF WAR.mp3
#  76611588 Books/Audio/1887_Henrick Ibsen_A Dolls House.mp3
# 170232911 Books/Audio/1922_Hermann Hesse_SIDDHARTHA.mp3
```

### Recommended Bucket Structure

If your existing bucket isn't organized, consider this structure for optimal Plex experience:

```
your-bucket/
├── Movies/
│   ├── Movie Name (Year)/
│   │   └── Movie Name (Year).mp4
│   └── Another Movie (Year)/
├── TV Shows/
│   ├── Show Name/
│   │   ├── Season 01/
│   │   └── Season 02/
│   └── Another Show/
├── Music/
│   ├── Artist Name/
│   │   └── Album Name/
│   └── Another Artist/
└── Books/
    └── Audio/
```

**✅ Your existing `capuk-media` bucket is already well-organized with:**
- `Books/` - Audiobook collection
- `Film/` - Movies  
- `Music/` - Music library
- `TV/` - TV shows
- `CV/` - Other content

## 🔧 Configuration Steps

### Step 1: Configure Object Storage Credentials

Edit `lke-values.yaml` and update the rclone section to point to your **existing bucket**:

```yaml
plex:
  rclone:
    enabled: true
    remoteName: "linode"                   # Name for your remote
    remotePath: "capuk-media"               # Your bucket name
    type: "s3"                              # Storage type: s3, b2, gcs, etc.
    
    # Configuration parameters (flattened format)
    config:
      provider: "Other"                     # Use "Other" for Linode Object Storage
      env_auth: "false"                     # Disable environment auth
      access_key_id: "YOUR_ACCESS_KEY"      # Your access key
      secret_access_key: "YOUR_SECRET_KEY"  # Your secret key  
      endpoint: "us-iad-1.linodeobjects.com" # Your region endpoint
      region: "us-iad-1"                   # Your region
```

### Step 2: Object Storage Providers

#### Linode Object Storage
```yaml
rclone:
  enabled: true
  remoteName: "linode"
  remotePath: "your-bucket-name"
  type: "s3"
  config:
    provider: "Other"
    env_auth: "false"
    access_key_id: "YOUR_ACCESS_KEY"
    secret_access_key: "YOUR_SECRET_KEY"
    endpoint: "us-iad-1.linodeobjects.com"  # or eu-central-1.linodeobjects.com
    region: "us-iad-1"                      # or eu-central-1
```

#### AWS S3
```yaml
rclone:
  enabled: true
  remoteName: "aws-s3"
  remotePath: "your-bucket-name"
  type: "s3"
  config:
    provider: "AWS"
    env_auth: "false"
    access_key_id: "YOUR_ACCESS_KEY"
    secret_access_key: "YOUR_SECRET_KEY"
    region: "us-east-1"                     # Your AWS region
```

#### Backblaze B2
```yaml
rclone:
  enabled: true
  remoteName: "b2"
  remotePath: "your-bucket-name"
  type: "b2"
  config:
    env_auth: "false"
    account: "YOUR_ACCOUNT_ID"
    key: "YOUR_APPLICATION_KEY"
```

### Step 3: Performance Tuning

Adjust these settings based on your needs:

```yaml
plex:
  rclone:
    # Cache settings for better streaming performance
    vfsCacheMode: "writes"        # Options: off, minimal, writes, full
    vfsCacheMaxSize: "2G"         # Larger = better performance, more disk usage
    vfsCacheMaxAge: "24h"         # How long to cache files
    bufferSize: "128M"            # Buffer size for reading files
    dirCacheTime: "15m"           # Cache directory listings
    
    # Connection settings
    timeout: "10m"                # Timeout for operations
    contimeout: "60s"             # Connection timeout
    
    # Performance tuning
    extraArgs:
      - "--transfers=4"           # Parallel transfers
      - "--checkers=8"            # Parallel file checks  
      - "--use-mmap"              # Memory mapping for performance
      - "--buffer-size=128M"      # Alternative way to set buffer
```

### Step 4: Deploy with rclone

1. **Update your configuration**:
   ```bash
   # Edit lke-values.yaml with your credentials
   nano lke-values.yaml
   ```

2. **Deploy the updated chart**:
   ```bash
   helm upgrade multi-service ./charts/multi-service -f lke-values.yaml -n multi-service
   ```

3. **Check rclone connection**:
   ```bash
   # Check pod logs
   kubectl logs -n multi-service -l app.kubernetes.io/component=plex -c rclone
   
   # Verify existing media is accessible
   kubectl exec -n multi-service deployment/multi-service-plex -c plex -- ls -la /data
   
   # Test access to your existing media files
   kubectl exec -n multi-service deployment/multi-service-plex -c rclone -- rclone ls linode:capuk-media | head -5
   ```

### Step 5: Initial Plex Server Setup

After deployment, you need to run through the initial Plex server setup:

1. **Create port-forward to access Plex setup interface**:
   ```bash
   kubectl port-forward -n multi-service deployment/multi-service-plex 32400:32400
   # Output: Forwarding from 127.0.0.1:32400 -> 32400
   #         Forwarding from [::1]:32400 -> 32400
   ```

2. **Navigate to Plex setup in your browser**:
   ```
   http://localhost:32400/web
   ```

3. **Complete the Plex server setup wizard**:
   - **Sign in** to your Plex account (required for remote access)
   - **Name your server** (e.g., "Kubernetes Plex Server")
   - **Add media libraries** pointing to your object storage directories:
     - Movies: `/data/Film` (for capuk-media structure)
     - TV Shows: `/data/TV`
     - Music: `/data/Music`
     - Audiobooks: `/data/Books/Audio`
   - **Configure remote access** (optional - can be done later)

4. **Verify setup**:
   ```bash
   # Test external access after setup
   curl -I https://tv.christinepuk.net
   # Should return HTTP/2 401 or 200 (not connection refused)
   ```

5. **Stop port-forward** (Ctrl+C) and access via ingress:
   ```
   https://tv.christinepuk.net
   ```

**Important**: The initial setup **must** be done via `localhost:32400` for security reasons. After setup, you can access Plex through the external URL.

## 🔍 Verifying Your Existing Media

Once deployed, verify Plex can access your existing media:

### Check Media Directory Structure

```bash
# List top-level directories (should match your bucket structure)
kubectl exec -n multi-service deployment/multi-service-plex -c plex -- ls -la /data

# Check specific media types
kubectl exec -n multi-service deployment/multi-service-plex -c plex -- ls /data/Movies | head -5
kubectl exec -n multi-service deployment/multi-service-plex -c plex -- ls /data/TV | head -5
kubectl exec -n multi-service deployment/multi-service-plex -c plex -- ls /data/Music | head -5

# For capuk-media bucket structure:
kubectl exec -n multi-service deployment/multi-service-plex -c plex -- ls /data/Film | head -5
kubectl exec -n multi-service deployment/multi-service-plex -c plex -- ls /data/TV | head -5
kubectl exec -n multi-service deployment/multi-service-plex -c plex -- ls /data/Books/Audio | head -5
```

### Test File Access

```bash
# Verify files are readable (test with a known file)
kubectl exec -n multi-service deployment/multi-service-plex -c plex -- \
  head -c 1000 "/data/Books/Audio/1772_Sun Tzu_THE ART OF WAR.mp3" > /dev/null && \
  echo "✅ File access working" || echo "❌ File access failed"
```

## 🎬 Setting Up Plex Libraries with Existing Media

Once your existing media is accessible:

1. **Access Plex** at https://tv.christinepuk.net
2. **Add Libraries** pointing to your existing directory structure:
   - **Movies**: `/data/Film` (or `/data/Movies` if using standard structure)
   - **TV Shows**: `/data/TV`
   - **Music**: `/data/Music`
   - **Audiobooks**: `/data/Books/Audio`
3. **Scan Libraries**: Plex will automatically scan and organize your existing media

### Example Library Paths for capuk-media bucket:
- **Movies**: `/data/Film`
- **TV Shows**: `/data/TV`  
- **Music**: `/data/Music`
- **Audiobooks**: `/data/Books/Audio`
- **Other**: `/data/CV`

## 📁 Directory Structure

Organize your object storage bucket like this:

```
my-bucket/
├── media/
│   ├── Movies/
│   │   ├── Movie1 (2023)/
│   │   │   └── Movie1.mp4
│   │   └── Movie2 (2024)/
│   │       └── Movie2.mkv
│   ├── TV Shows/
│   │   ├── Show1/
│   │   │   ├── Season 1/
│   │   │   │   ├── S01E01.mp4
│   │   │   │   └── S01E02.mp4
│   │   │   └── Season 2/
│   │   └── Show2/
│   └── Music/
│       ├── Artist1/
│       └── Artist2/
```

## 🚀 Performance Optimization

### Cache Settings by Use Case

**Streaming Focus (Default)**:
```yaml
vfsCacheMode: "writes"
vfsCacheMaxSize: "2G"
vfsCacheMaxAge: "24h"
```

**Maximum Performance**:
```yaml
vfsCacheMode: "full"          # Cache everything
vfsCacheMaxSize: "10G"        # Large cache
vfsCacheMaxAge: "168h"        # 7 days
```

**Minimal Storage Usage**:
```yaml
vfsCacheMode: "minimal"       # Minimal caching
vfsCacheMaxSize: "500M"       # Small cache
vfsCacheMaxAge: "1h"          # Short retention
```

### Resource Requirements

Increase Plex resources when using rclone:

```yaml
plex:
  resources:
    requests:
      memory: 1Gi                # Increased for cache
      cpu: 300m                  # Increased for rclone overhead
    limits:
      memory: 3Gi                # Room for transcoding + cache
      cpu: 1000m
```

## 🔍 Troubleshooting

### Check rclone Mount Status
```bash
# Check rclone container logs
kubectl logs -n multi-service deployment/multi-service-plex -c rclone

# Check if files are accessible
kubectl exec -n multi-service deployment/multi-service-plex -c plex -- ls -la /data

# Test rclone connection directly (use your remote name and bucket)
kubectl exec -n multi-service deployment/multi-service-plex -c rclone -- rclone ls linode:capuk-media --max-depth 1
```

### Common Issues

#### Issues with Existing Buckets

1. **Bucket Access Denied**: 
   - Verify credentials have read/write permissions to the existing bucket
   - Check bucket name spelling and region configuration
   - Test access with: `rclone ls your-remote:bucket-name --max-depth 1`

2. **Files Not Visible in Plex**:
   - Check mount is working: `kubectl exec ... -- ls -la /data`
   - Verify file paths match Plex expectations
   - Check file permissions and formats

3. **Authentication Errors with Existing Setup**:
   - Ensure `env_auth: "false"` is set to use explicit credentials
   - Verify access_key_id and secret_access_key are correct
   - Test with known working rclone config first

#### General Issues

1. **Mount fails**: Check credentials and endpoint configuration
2. **Slow streaming**: Increase `bufferSize` and `vfsCacheMaxSize`
3. **High bandwidth usage**: Enable more aggressive caching with `vfsCacheMode: "full"`
4. **Pod fails to start**: Check that privileged containers are allowed in your cluster

### Debug Mode

Enable debug logging:
```yaml
extraArgs:
  - "--log-level=DEBUG"
  - "--log-file=/tmp/rclone.log"
```

Then check logs:
```bash
kubectl exec -n multi-service deployment/multi-service-plex -c rclone -- cat /tmp/rclone.log
```

## 📋 Migration Scenarios

### From Local Storage to Existing Bucket

If you have local media and want to move to an existing object storage bucket:

1. **Upload existing media**:
   ```bash
   # Copy from local PVC to your existing bucket (adjust remote:bucket format)
   kubectl exec -n multi-service deployment/multi-service-plex -c plex -- \
     rclone copy /data linode:capuk-media --progress
   ```

2. **Switch to rclone**:
   ```bash
   # Update configuration to use existing bucket
   helm upgrade multi-service ./charts/multi-service -f lke-values.yaml -n multi-service --set plex.rclone.enabled=true
   ```

3. **Clean up old PVC** (optional):
   ```bash
   kubectl delete pvc multi-service-plex-media -n multi-service
   ```

### From New Installation to Existing Bucket

If you're doing a fresh Plex installation with an existing media bucket:

1. **Configure rclone** with your existing bucket details in `lke-values.yaml`
2. **Deploy Plex** with rclone enabled from the start
3. **Set up libraries** pointing to your existing directory structure
4. **No data migration needed** - Plex will scan existing media

### Maintaining Existing Media Organization

Your existing bucket structure will work with Plex. For example, the `capuk-media` bucket structure:

```
capuk-media/
├── Books/Audio/     → Plex Audiobooks library at /data/Books/Audio
├── Film/           → Plex Movies library at /data/Film  
├── Music/          → Plex Music library at /data/Music
├── TV/             → Plex TV Shows library at /data/TV
└── CV/             → Additional content at /data/CV
```

**✅ No reorganization required** - Plex is flexible with directory structures!