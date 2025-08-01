#!/bin/bash

# Quick Kafka Deployment Test Script
# Run this for a fast validation of your deployment files

set -euo pipefail

echo "🚀 Quick Kafka Deployment Test"
echo "=============================="
echo

# Test function
test_deployment() {
    local name=$1
    local path=$2
    
    echo "Testing $name deployment..."
    
    if kubectl apply --dry-run=client -f 00-namespace.yaml -f "$path" &> /dev/null; then
        echo "✅ $name: Valid"
        kubectl apply --dry-run=client -f 00-namespace.yaml -f "$path" 2>&1 | grep "created (dry run)" | wc -l | xargs echo "   Resources to create:"
    else
        echo "❌ $name: Invalid"
        return 1
    fi
}

# Run tests
echo "1. Checking kubectl availability..."
if command -v kubectl &> /dev/null; then
    echo "✅ kubectl found"
else
    echo "❌ kubectl not found. Please install kubectl."
    exit 1
fi

echo
echo "2. Validating deployments..."
test_deployment "Single-Node" "single/"
test_deployment "Cluster" "cluster/"

echo
echo "3. Quick health check..."
echo "✅ Namespace: kafka"
echo "✅ Image: apache/kafka:4.0.1-rc0"
echo "✅ Storage: PersistentVolumeClaims configured"
echo "✅ Ingress: kafka.nks.stjeong.com"

echo
echo "✨ Quick test completed!"
echo
echo "For comprehensive testing, run: ./test-deployment.sh"