#!/bin/bash

# GitHub Actions Secret Setup Script
# This script helps you prepare and set secrets for GitHub Actions deployment

set -e

echo "🔐 GitHub Actions Secret Setup for LKE Deployment"
echo "================================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check prerequisites
echo -e "${BLUE}📋 Checking prerequisites...${NC}"

# Check if gh CLI is installed
if ! command -v gh &> /dev/null; then
    echo -e "${RED}❌ GitHub CLI (gh) is not installed${NC}"
    echo "Install it from: https://cli.github.com/"
    exit 1
fi

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}❌ kubectl is not installed${NC}"
    exit 1
fi

# Check if we're in a git repository
if ! git rev-parse --is-inside-work-tree &> /dev/null; then
    echo -e "${RED}❌ Not in a git repository${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Prerequisites checked${NC}"

# Get repository info
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
echo -e "${BLUE}📦 Repository: $REPO${NC}"

# Function to set GitHub secret
set_secret() {
    local secret_name=$1
    local secret_value=$2
    local description=$3
    
    echo -e "${BLUE}Setting secret: $secret_name${NC}"
    echo "Description: $description"
    
    if echo "$secret_value" | gh secret set "$secret_name"; then
        echo -e "${GREEN}✅ Secret $secret_name set successfully${NC}"
    else
        echo -e "${RED}❌ Failed to set secret $secret_name${NC}"
        return 1
    fi
    echo ""
}

# 1. KUBECONFIG
echo -e "${YELLOW}1. Setting up KUBECONFIG secret${NC}"
if [ -f ~/.kube/config ]; then
    KUBECONFIG_B64=$(cat ~/.kube/config | base64 -w 0)
    set_secret "KUBECONFIG" "$KUBECONFIG_B64" "Base64-encoded kubeconfig file for LKE cluster access"
else
    echo -e "${RED}❌ ~/.kube/config not found${NC}"
    echo "Please ensure your kubeconfig is set up for LKE cluster"
    exit 1
fi

# 2. Generate MySQL passwords
echo -e "${YELLOW}2. Generating MySQL passwords${NC}"
MYSQL_ROOT_PASSWORD=$(openssl rand -base64 32)
MYSQL_PASSWORD=$(openssl rand -base64 32)

set_secret "MYSQL_ROOT_PASSWORD" "$MYSQL_ROOT_PASSWORD" "MySQL root password for WordPress databases"
set_secret "MYSQL_PASSWORD" "$MYSQL_PASSWORD" "MySQL password for WordPress applications"

# 3. Plex claim token
echo -e "${YELLOW}3. Plex claim token setup${NC}"
echo "Please visit: https://plex.tv/claim"
echo "Copy the claim token (valid for 4 minutes)"
read -p "Enter Plex claim token: " PLEX_CLAIM_TOKEN

if [ -n "$PLEX_CLAIM_TOKEN" ]; then
    set_secret "PLEX_CLAIM_TOKEN" "$PLEX_CLAIM_TOKEN" "Plex server claim token for initial setup"
else
    echo -e "${RED}❌ Plex claim token is required${NC}"
    exit 1
fi

# 4. Cert-manager email
echo -e "${YELLOW}4. Cert-manager email setup${NC}"
read -p "Enter email for Let's Encrypt certificates: " CERT_EMAIL

if [ -n "$CERT_EMAIL" ]; then
    set_secret "CERT_MANAGER_EMAIL" "$CERT_EMAIL" "Email for Let's Encrypt certificate registration"
else
    echo -e "${RED}❌ Certificate email is required${NC}"
    exit 1
fi

# 5. rclone configuration
echo -e "${YELLOW}5. rclone configuration setup${NC}"
echo "Choose rclone config source:"
echo "1) Use existing ~/.config/rclone/rclone.conf"
echo "2) Enter configuration manually"
read -p "Choice (1 or 2): " RCLONE_CHOICE

case $RCLONE_CHOICE in
    1)
        if [ -f ~/.config/rclone/rclone.conf ]; then
            RCLONE_CONFIG=$(cat ~/.config/rclone/rclone.conf)
            set_secret "RCLONE_CONFIG" "$RCLONE_CONFIG" "rclone configuration for object storage access"
        else
            echo -e "${RED}❌ ~/.config/rclone/rclone.conf not found${NC}"
            exit 1
        fi
        ;;
    2)
        echo "Enter rclone configuration for [linode] section:"
        echo "Example format:"
        echo "[linode]"
        echo "type = s3"
        echo "access_key_id = YOUR_KEY"
        echo "endpoint = us-iad-1.linodeobjects.com"
        echo "env_auth = false"
        echo "provider = Other"
        echo "region = us-iad-1"
        echo "secret_access_key = YOUR_SECRET"
        echo ""
        echo "Enter the complete configuration (press Ctrl+D when done):"
        RCLONE_CONFIG=$(cat)
        set_secret "RCLONE_CONFIG" "$RCLONE_CONFIG" "rclone configuration for object storage access"
        ;;
    *)
        echo -e "${RED}❌ Invalid choice${NC}"
        exit 1
        ;;
esac

# 6. Optional: Linode token
echo -e "${YELLOW}6. Optional: Linode API token${NC}"
echo "This is optional but recommended for advanced automation"
read -p "Enter Linode API token (or press Enter to skip): " LINODE_TOKEN

if [ -n "$LINODE_TOKEN" ]; then
    set_secret "LINODE_TOKEN" "$LINODE_TOKEN" "Linode API token for infrastructure automation"
fi

# 7. Optional: Slack webhook
echo -e "${YELLOW}7. Optional: Slack webhook for notifications${NC}"
read -p "Enter Slack webhook URL (or press Enter to skip): " SLACK_WEBHOOK

if [ -n "$SLACK_WEBHOOK" ]; then
    set_secret "SLACK_WEBHOOK" "$SLACK_WEBHOOK" "Slack webhook URL for deployment notifications"
fi

# Summary
echo -e "${GREEN}🎉 Secret setup completed!${NC}"
echo ""
echo -e "${BLUE}📋 Summary of secrets set:${NC}"
echo "✅ KUBECONFIG - Kubernetes cluster access"
echo "✅ MYSQL_ROOT_PASSWORD - MySQL root password" 
echo "✅ MYSQL_PASSWORD - WordPress database password"
echo "✅ PLEX_CLAIM_TOKEN - Plex server claim token"
echo "✅ CERT_MANAGER_EMAIL - Let's Encrypt email"
echo "✅ RCLONE_CONFIG - Object storage configuration"
[ -n "$LINODE_TOKEN" ] && echo "✅ LINODE_TOKEN - Linode API access"
[ -n "$SLACK_WEBHOOK" ] && echo "✅ SLACK_WEBHOOK - Slack notifications"

echo ""
echo -e "${YELLOW}📝 Next steps:${NC}"
echo "1. Commit and push your GitHub Actions workflow files"
echo "2. Go to your repository's Actions tab to monitor deployments"
echo "3. Your first deployment will trigger on push to main branch"
echo ""
echo -e "${BLUE}🔍 View your secrets:${NC}"
echo "GitHub → Repository → Settings → Secrets and variables → Actions"

# Generate environment file for local testing (optional)
echo -e "${YELLOW}💻 Generate .env file for local testing? (y/n)${NC}"
read -p "Choice: " CREATE_ENV

if [ "$CREATE_ENV" = "y" ]; then
    cat > .env.local << EOF
# Local environment variables for testing
# DO NOT COMMIT THIS FILE TO GIT!

MYSQL_ROOT_PASSWORD=$MYSQL_ROOT_PASSWORD
MYSQL_PASSWORD=$MYSQL_PASSWORD
PLEX_CLAIM_TOKEN=$PLEX_CLAIM_TOKEN
CERT_MANAGER_EMAIL=$CERT_EMAIL
$([ -n "$LINODE_TOKEN" ] && echo "LINODE_TOKEN=$LINODE_TOKEN")
$([ -n "$SLACK_WEBHOOK" ] && echo "SLACK_WEBHOOK=$SLACK_WEBHOOK")

# rclone config (create rclone.conf file separately)
EOF

    echo "$RCLONE_CONFIG" > rclone.conf.local
    
    echo -e "${GREEN}✅ Created .env.local and rclone.conf.local for testing${NC}"
    echo -e "${RED}⚠️  DO NOT COMMIT THESE FILES TO GIT!${NC}"
    
    # Add to .gitignore if not already present
    if ! grep -q ".env.local" .gitignore 2>/dev/null; then
        echo ".env.local" >> .gitignore
        echo "rclone.conf.local" >> .gitignore
        echo -e "${GREEN}✅ Added local files to .gitignore${NC}"
    fi
fi

echo ""
echo -e "${GREEN}🚀 GitHub Actions setup is complete!${NC}"