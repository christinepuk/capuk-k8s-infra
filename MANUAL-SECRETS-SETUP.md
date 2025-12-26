# Manual GitHub Secrets Setup Guide

Since the GitHub CLI is having authentication issues, here's how to set up the secrets manually through the GitHub web interface.

## Step 1: Generate Required Values

First, let's generate the values you'll need:

### 1. Get your kubeconfig (base64 encoded)
```bash
cat ~/.kube/config | base64 -w 0
```
Copy the output - this will be your `KUBECONFIG` secret.

### 2. Generate MySQL passwords
```bash
# Generate MySQL root password
openssl rand -base64 32

# Generate WordPress database password  
openssl rand -base64 32
```

### 3. Get your rclone config
```bash
# If you have existing rclone config
cat ~/.config/rclone/rclone.conf

# Or use the working config from your deployment
kubectl get secret rclone-secret -o jsonpath='{.data.rclone\.conf}' -n multi-service | base64 -d
```

### 4. Get Plex claim token
Visit: https://plex.tv/claim and copy the token (valid for 4 minutes)

## Step 2: Set Secrets in GitHub

Go to your GitHub repository:
1. Click **Settings** tab
2. Click **Secrets and variables** → **Actions**
3. Click **New repository secret** for each secret below

## Required Secrets

| Secret Name | Value | Description |
|-------------|-------|-------------|
| `KUBECONFIG` | Base64-encoded kubeconfig | Output from step 1.1 |
| `MYSQL_ROOT_PASSWORD` | Generated password | Output from step 1.2 (first command) |
| `MYSQL_PASSWORD` | Generated password | Output from step 1.2 (second command) |
| `PLEX_CLAIM_TOKEN` | claim-xxxxxxxxxxxx | From https://plex.tv/claim |
| `CERT_MANAGER_EMAIL` | your-email@domain.com | Your email for Let's Encrypt |
| `RCLONE_CONFIG` | rclone configuration | Output from step 1.3 |

## Optional Secrets

| Secret Name | Value | Description |
|-------------|-------|-------------|
| `LINODE_TOKEN` | linode_api_token | For advanced automation |
| `SLACK_WEBHOOK` | webhook_url | For deployment notifications |

## Step 3: Verify Setup

Once all secrets are set, you can:

1. **Test the workflow manually:**
   - Go to **Actions** tab
   - Click **Deploy to LKE**
   - Click **Run workflow**
   - Select `production` environment

2. **Or push to main branch** to trigger automatic deployment

## Example Values

Here are example formats for the key secrets:

### KUBECONFIG (base64 encoded)
```
YXBpVmVyc2lvbjogdjEKY2x1c3RlcnM6Ci0gY2x1c3RlcjoKICAgIGNlcnRpZmljYXRlLWF1dG...
```

### RCLONE_CONFIG
```
[linode]
type = s3
access_key_id = TF2U8G95K96J7MILAHPC
endpoint = us-iad-1.linodeobjects.com
env_auth = false
provider = Other
region = us-iad-1
secret_access_key = L6qMNPDTnWKtipjq8wMHFo5kUoVjI5R57PQ379Y3
```

### PLEX_CLAIM_TOKEN
```
claim-H3pzabkzUuf19sVKchfD
```

## Troubleshooting

### If deployment fails:
1. Check the **Actions** tab for error logs
2. Verify all secrets are set correctly
3. Ensure your kubeconfig is valid: `kubectl get nodes`
4. Check that Plex claim token hasn't expired (get a new one)

### If secrets need updating:
1. Go back to **Settings** → **Secrets and variables** → **Actions**
2. Click the pencil icon next to the secret name
3. Update the value
4. Re-run the workflow

This manual approach gives you the same result as the automated script, just requires a bit more manual work through the GitHub interface.