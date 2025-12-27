#!/bin/bash

# Troubleshooting script for multi-service deployment issues
# Run this when you have stuck pods or deployment problems

NAMESPACE="multi-service"

echo "🔧 Multi-service troubleshooting script"
echo "======================================="

echo "📊 Current pod status:"
kubectl get pods -n $NAMESPACE

echo ""
echo "🔍 Checking for problematic pods..."

# Find and delete stuck pods
echo "🗑️  Cleaning up stuck/pending pods..."
kubectl get pods -n $NAMESPACE --field-selector=status.phase=Pending -o name | xargs -r kubectl delete -n $NAMESPACE --grace-period=0 --force

# Find pods stuck in Init state
kubectl get pods -n $NAMESPACE | grep -E "(Init:|ContainerCreating|Pending)" | awk '{print $1}' | xargs -r kubectl delete pod -n $NAMESPACE --grace-period=0 --force

echo ""
echo "🔄 Scaling down problematic replica sets..."

# Get all replica sets with 0 desired but pods still running
kubectl get rs -n $NAMESPACE | grep " 0 " | awk '{print $1}' | xargs -r -I {} kubectl scale rs {} --replicas=0 -n $NAMESPACE

echo ""
echo "⏳ Waiting for cleanup to complete..."
sleep 10

echo "📊 Final status after cleanup:"
kubectl get pods -n $NAMESPACE

echo ""
echo "🌐 Ingress status:"
kubectl get ingress -n $NAMESPACE

echo ""
echo "✅ Troubleshooting complete!"
echo "💡 If issues persist, try running: ./scripts/safe-deploy.sh"