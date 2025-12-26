#!/bin/bash

# Script to check for hardcoded secrets in the repository
# Run this before committing to ensure no secrets are exposed

echo "🔍 Scanning for potential secrets in repository..."
echo "================================================="

# Define patterns to search for
PATTERNS=(
    "claim-[A-Za-z0-9]+"
    "password.*=.*\"[^\"]*\""
    "token.*=.*\"[^\"]*\""
    "key.*=.*\"[A-Za-z0-9/+=]{20,}\""
    "secret.*=.*\"[^\"]*\""
    "TF2U8G"  # Part of your access key
    "L6qMNPD"  # Part of your secret key
    "Unmiry3"  # Part of your MySQL password
    "Lies54"   # Part of your other password
)

FOUND_SECRETS=false

# Check each pattern
for pattern in "${PATTERNS[@]}"; do
    echo "Checking for pattern: $pattern"
    
    # Search in files, excluding .git directory and this script itself
    matches=$(grep -r -E "$pattern" . \
        --exclude-dir=.git \
        --exclude="check-secrets.sh" \
        --exclude="*.md" \
        --exclude-dir=node_modules 2>/dev/null || true)
    
    if [ -n "$matches" ]; then
        echo "⚠️  FOUND POTENTIAL SECRET:"
        echo "$matches"
        echo ""
        FOUND_SECRETS=true
    fi
done

# Additional checks for specific file types
echo "Checking YAML files for suspicious content..."
find . -name "*.yaml" -o -name "*.yml" | grep -v .git | while read file; do
    if grep -E "(password|token|key|secret).*:" "$file" | grep -v -E "(# |secretName|existingSecret|Will be|injected|sourced)" >/dev/null 2>&1; then
        echo "⚠️  Suspicious content in $file:"
        grep -E "(password|token|key|secret).*:" "$file" | grep -v -E "(# |secretName|existingSecret|Will be|injected|sourced)"
        FOUND_SECRETS=true
    fi
done

# Check for base64 encoded content (might be secrets)
echo "Checking for potential base64 encoded secrets..."
find . -name "*.yaml" -o -name "*.yml" | grep -v .git | while read file; do
    if grep -E "[A-Za-z0-9/+=]{40,}" "$file" >/dev/null 2>&1; then
        echo "⚠️  Potential base64 content in $file (check if it's a secret):"
        grep -E "[A-Za-z0-9/+=]{40,}" "$file" | head -3
    fi
done

echo ""
if [ "$FOUND_SECRETS" = true ]; then
    echo "❌ POTENTIAL SECRETS FOUND!"
    echo "Please review the flagged content above."
    echo "Remove any hardcoded secrets before committing."
    exit 1
else
    echo "✅ No obvious secrets found in repository."
    echo "Safe to commit!"
fi