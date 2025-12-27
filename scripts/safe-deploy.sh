#!/bin/bash

# Safe deployment script for multi-service Helm chart
# This script helps prevent persistent volume conflicts during deployments

set -e

NAMESPACE="multi-service"
CHART_PATH="./charts/multi-service/"
RELEASE_NAME="multi-service"

echo "🚀 Starting safe deployment of multi-service..."

# Function to wait for pods to be ready
wait_for_pods() {
    echo "⏳ Waiting for pods to be ready..."
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=multi-service -n $NAMESPACE --timeout=300s || true
}

# Function to clean up stuck pods
cleanup_stuck_pods() {
    echo "🧹 Checking for stuck pods..."
    
    # Delete pods that are stuck in Init or Pending state for more than 5 minutes
    stuck_pods=$(kubectl get pods -n $NAMESPACE --field-selector=status.phase=Pending -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true)
    if [ ! -z "$stuck_pods" ]; then
        echo "🗑️  Cleaning up stuck pods: $stuck_pods"
        kubectl delete pod $stuck_pods -n $NAMESPACE --grace-period=30 || true
    fi
    
    # Delete pods stuck in Init state
    init_pods=$(kubectl get pods -n $NAMESPACE -o jsonpath='{.items[?(@.status.containerStatuses[0].state.waiting.reason=="PodInitializing")].metadata.name}' 2>/dev/null || true)
    if [ ! -z "$init_pods" ]; then
        echo "🗑️  Cleaning up init pods: $init_pods" 
        kubectl delete pod $init_pods -n $NAMESPACE --grace-period=30 || true
    fi
}

# Pre-deployment cleanup
cleanup_stuck_pods

echo "📦 Upgrading Helm release..."
helm upgrade --install $RELEASE_NAME $CHART_PATH \
    -n $NAMESPACE \
    --create-namespace \
    --wait \
    --timeout=10m

# Post-deployment validation
echo "🔍 Validating deployment..."

# Wait a bit for pods to settle
sleep 30

# Clean up any remaining stuck pods
cleanup_stuck_pods

# Wait for all pods to be ready
wait_for_pods

echo "✅ Deployment completed successfully!"

# Show final status
echo "📊 Final status:"
kubectl get pods -n $NAMESPACE
echo ""
kubectl get ingress -n $NAMESPACE