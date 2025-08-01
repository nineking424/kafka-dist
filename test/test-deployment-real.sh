#!/bin/bash

# Kafka Kubernetes Deployment REAL Test Script
# This script performs ACTUAL deployments and tests in your Kubernetes cluster
# WARNING: This will create and delete real resources in your cluster!

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# Test result tracking
declare -a TEST_RESULTS

# Cleanup flag
CLEANUP_ON_EXIT=true
NAMESPACE="kafka"

# Function to print colored output
print_color() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to print test header
print_test_header() {
    echo
    print_color "$BLUE" "=========================================="
    print_color "$BLUE" "$1"
    print_color "$BLUE" "=========================================="
}

# Function to record test result
record_test() {
    local test_name=$1
    local result=$2
    local details=$3
    
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    
    if [ "$result" == "PASS" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        print_color "$GREEN" "✅ PASS: $test_name"
        TEST_RESULTS+=("✅ $test_name: PASSED")
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        print_color "$RED" "❌ FAIL: $test_name"
        print_color "$RED" "   Details: $details"
        TEST_RESULTS+=("❌ $test_name: FAILED - $details")
    fi
}

# Cleanup function
cleanup() {
    if [ "$CLEANUP_ON_EXIT" = true ]; then
        print_test_header "Cleaning up test resources"
        
        # Delete deployments
        kubectl delete -f single/ --ignore-not-found=true -n $NAMESPACE 2>/dev/null || true
        kubectl delete -f cluster/ --ignore-not-found=true -n $NAMESPACE 2>/dev/null || true
        
        # Delete namespace
        kubectl delete namespace $NAMESPACE --ignore-not-found=true 2>/dev/null || true
        
        print_color "$GREEN" "Cleanup completed"
    else
        print_color "$YELLOW" "Skipping cleanup (CLEANUP_ON_EXIT=false)"
    fi
}

# Set trap for cleanup on exit
trap cleanup EXIT

# Function to wait for pods
wait_for_pods() {
    local namespace=$1
    local label_selector=$2
    local expected_count=$3
    local timeout=${4:-120}
    
    print_color "$YELLOW" "Waiting for pods with selector '$label_selector' to be ready..."
    
    local count=0
    while [ $count -lt $timeout ]; do
        local ready_pods=$(kubectl get pods -n $namespace -l "$label_selector" -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' | grep -o "True" | wc -l | tr -d '[:space:]' || echo "0")
        
        if [ "$ready_pods" -eq "$expected_count" ]; then
            print_color "$GREEN" "All $expected_count pods are ready!"
            return 0
        fi
        
        echo -ne "\rWaiting... $count/$timeout seconds (Ready: $ready_pods/$expected_count)"
        sleep 1
        count=$((count + 1))
    done
    
    echo
    print_color "$RED" "Timeout waiting for pods (Ready: $ready_pods/$expected_count)"
    return 1
}

# Function to check if kubectl is available
check_prerequisites() {
    print_test_header "Checking Prerequisites"
    
    if ! command -v kubectl &> /dev/null; then
        print_color "$RED" "kubectl command not found. Please install kubectl to run tests."
        exit 1
    fi
    
    print_color "$GREEN" "✅ kubectl is available"
    
    # Check if connected to a cluster
    if kubectl cluster-info &> /dev/null; then
        print_color "$GREEN" "✅ Connected to Kubernetes cluster"
        kubectl version --client=true -o yaml | grep -E "gitVersion" | head -1 || echo "kubectl version: $(kubectl version --client=true -o json | grep gitVersion | cut -d'"' -f4 | head -1)"
    else
        print_color "$RED" "❌ Not connected to a Kubernetes cluster. Real tests require cluster access."
        exit 1
    fi
    
    # Warning about real deployment
    print_color "$YELLOW" "⚠️  WARNING: This script will create REAL resources in your cluster!"
    print_color "$YELLOW" "⚠️  Namespace '$NAMESPACE' will be created and deleted during tests."
    echo
    read -p "Do you want to continue? (yes/no): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_color "$RED" "Test cancelled by user"
        exit 0
    fi
}

# Test 1: Namespace Creation
test_namespace_creation() {
    print_test_header "Test 1: Namespace Creation"
    
    # Delete namespace if it exists
    kubectl delete namespace $NAMESPACE --ignore-not-found=true 2>/dev/null || true
    
    # Create namespace
    if kubectl apply -f 00-namespace.yaml; then
        # Verify namespace exists
        if kubectl get namespace $NAMESPACE &> /dev/null; then
            record_test "Namespace Creation" "PASS" "Namespace '$NAMESPACE' created successfully"
        else
            record_test "Namespace Creation" "FAIL" "Namespace '$NAMESPACE' not found after creation"
        fi
    else
        record_test "Namespace Creation" "FAIL" "Failed to create namespace"
    fi
}

# Test 2: Single-Node Deployment
test_single_node_deployment() {
    print_test_header "Test 2: Single-Node Deployment (REAL)"
    
    # Clean up any existing resources
    kubectl delete -f single/ --ignore-not-found=true -n $NAMESPACE 2>/dev/null || true
    sleep 5
    
    # Deploy single-node Kafka
    print_color "$YELLOW" "Deploying single-node Kafka..."
    if kubectl apply -f single/ -n $NAMESPACE; then
        # Wait for pod to be ready
        if wait_for_pods $NAMESPACE "app=kafka" 1 120; then
            # Check if pod is actually running
            local pod_status=$(kubectl get pods -n $NAMESPACE -l app=kafka -o jsonpath='{.items[0].status.phase}')
            if [ "$pod_status" == "Running" ]; then
                # Test Kafka functionality
                print_color "$YELLOW" "Testing Kafka broker connectivity..."
                
                # Create a test topic
                if kubectl exec -n $NAMESPACE kafka-0 -- /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --create --topic test-topic --partitions 1 --replication-factor 1 2>/dev/null; then
                    print_color "$GREEN" "✓ Successfully created test topic"
                    
                    # List topics
                    if kubectl exec -n $NAMESPACE kafka-0 -- /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --list | grep -q "test-topic"; then
                        print_color "$GREEN" "✓ Topic listing works"
                        record_test "Single-Node Deployment" "PASS" "Kafka is running and functional"
                    else
                        record_test "Single-Node Deployment" "FAIL" "Could not list topics"
                    fi
                else
                    record_test "Single-Node Deployment" "FAIL" "Could not create test topic"
                fi
            else
                record_test "Single-Node Deployment" "FAIL" "Pod status is $pod_status, not Running"
            fi
        else
            record_test "Single-Node Deployment" "FAIL" "Pod did not become ready in time"
        fi
    else
        record_test "Single-Node Deployment" "FAIL" "Failed to deploy single-node Kafka"
    fi
    
    # Show pod status for debugging
    echo
    print_color "$BLUE" "Pod Status:"
    kubectl get pods -n $NAMESPACE
    
    # Clean up single-node deployment
    print_color "$YELLOW" "Cleaning up single-node deployment..."
    kubectl delete -f single/ --ignore-not-found=true -n $NAMESPACE
    
    # Wait for cleanup
    local count=0
    while kubectl get pods -n $NAMESPACE -l app=kafka 2>/dev/null | grep -q kafka; do
        echo -ne "\rWaiting for cleanup... $count seconds"
        sleep 1
        count=$((count + 1))
        if [ $count -gt 60 ]; then
            print_color "$YELLOW" "\nForce deleting pods..."
            kubectl delete pods -n $NAMESPACE -l app=kafka --force --grace-period=0 2>/dev/null || true
            break
        fi
    done
    echo
}

# Test 3: Cluster Deployment
test_cluster_deployment() {
    print_test_header "Test 3: Multi-Node Cluster Deployment (REAL)"
    
    # Deploy cluster
    print_color "$YELLOW" "Deploying Kafka cluster..."
    if kubectl apply -f cluster/ -n $NAMESPACE; then
        # Wait for controller pods
        print_color "$YELLOW" "Waiting for controller pods..."
        if wait_for_pods $NAMESPACE "app=kafka-controller" 3 180; then
            print_color "$GREEN" "✓ Controllers are ready"
            
            # Wait for broker pods
            print_color "$YELLOW" "Waiting for broker pods..."
            if wait_for_pods $NAMESPACE "app=kafka-broker" 3 180; then
                print_color "$GREEN" "✓ Brokers are ready"
                
                # Test cluster functionality
                print_color "$YELLOW" "Testing Kafka cluster functionality..."
                
                # Wait a bit for cluster to stabilize
                sleep 10
                
                # Create test topic with replication
                if kubectl exec -n $NAMESPACE kafka-broker-0 -- /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --create --topic cluster-test --partitions 3 --replication-factor 3 2>/dev/null; then
                    print_color "$GREEN" "✓ Created replicated topic"
                    
                    # Describe topic to verify replication
                    if kubectl exec -n $NAMESPACE kafka-broker-0 -- /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --describe --topic cluster-test | grep -q "ReplicationFactor: 3"; then
                        print_color "$GREEN" "✓ Topic replication verified"
                        
                        # Check cluster metadata
                        if kubectl exec -n $NAMESPACE kafka-broker-0 -- /opt/kafka/bin/kafka-metadata-shell.sh --snapshot /var/lib/kafka/data/__cluster_metadata-0/00000000000000000000.log --print-brokers 2>/dev/null | grep -q "BROKER"; then
                            print_color "$GREEN" "✓ Cluster metadata accessible"
                            record_test "Cluster Deployment" "PASS" "Kafka cluster is running with proper replication"
                        else
                            record_test "Cluster Deployment" "FAIL" "Could not access cluster metadata"
                        fi
                    else
                        record_test "Cluster Deployment" "FAIL" "Topic replication not working"
                    fi
                else
                    record_test "Cluster Deployment" "FAIL" "Could not create replicated topic"
                fi
            else
                record_test "Cluster Deployment" "FAIL" "Broker pods did not become ready"
            fi
        else
            record_test "Cluster Deployment" "FAIL" "Controller pods did not become ready"
        fi
    else
        record_test "Cluster Deployment" "FAIL" "Failed to deploy cluster"
    fi
    
    # Show cluster status
    echo
    print_color "$BLUE" "Cluster Status:"
    kubectl get pods -n $NAMESPACE
    echo
    kubectl get svc -n $NAMESPACE
}

# Test 4: Service Connectivity
test_service_connectivity() {
    print_test_header "Test 4: Service Connectivity"
    
    # Check if services exist
    local services=$(kubectl get svc -n $NAMESPACE --no-headers | wc -l)
    if [ "$services" -gt 0 ]; then
        print_color "$GREEN" "✓ Found $services services"
        
        # Test internal connectivity using a test pod
        print_color "$YELLOW" "Testing internal service connectivity..."
        
        # Run a test pod and check connectivity
        if kubectl run -n $NAMESPACE connectivity-test --image=busybox --restart=Never --rm -i -- \
            sh -c "nc -zv kafka-broker-headless 9092" 2>&1 | grep -q "succeeded"; then
            print_color "$GREEN" "✓ Internal service connectivity works"
            record_test "Service Connectivity" "PASS" "Services are accessible internally"
        else
            record_test "Service Connectivity" "FAIL" "Could not connect to internal services"
        fi
    else
        record_test "Service Connectivity" "FAIL" "No services found"
    fi
}

# Test 5: Persistent Storage
test_persistent_storage() {
    print_test_header "Test 5: Persistent Storage"
    
    # Check PVCs
    local pvcs=$(kubectl get pvc -n $NAMESPACE --no-headers | wc -l)
    if [ "$pvcs" -gt 0 ]; then
        print_color "$GREEN" "✓ Found $pvcs PVCs"
        
        # Check if all PVCs are bound
        local bound_pvcs=$(kubectl get pvc -n $NAMESPACE -o jsonpath='{.items[*].status.phase}' | grep -o "Bound" | wc -l)
        
        if [ "$bound_pvcs" -eq "$pvcs" ]; then
            print_color "$GREEN" "✓ All PVCs are bound"
            
            # Test data persistence
            print_color "$YELLOW" "Testing data persistence..."
            
            # Create a test message
            echo "test-message-$(date +%s)" | kubectl exec -i -n $NAMESPACE kafka-broker-0 -- \
                /opt/kafka/bin/kafka-console-producer.sh --bootstrap-server localhost:9092 --topic cluster-test 2>/dev/null
            
            # Read it back
            if kubectl exec -n $NAMESPACE kafka-broker-0 -- \
                /opt/kafka/bin/kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic cluster-test \
                --from-beginning --max-messages 1 --timeout-ms 5000 2>/dev/null | grep -q "test-message"; then
                print_color "$GREEN" "✓ Data persistence verified"
                record_test "Persistent Storage" "PASS" "Storage is working correctly"
            else
                record_test "Persistent Storage" "FAIL" "Could not verify data persistence"
            fi
        else
            record_test "Persistent Storage" "FAIL" "Not all PVCs are bound ($bound_pvcs/$pvcs)"
        fi
    else
        record_test "Persistent Storage" "FAIL" "No PVCs found"
    fi
    
    # Show PVC status
    echo
    print_color "$BLUE" "PVC Status:"
    kubectl get pvc -n $NAMESPACE
}

# Test 6: Ingress Configuration
test_ingress_configuration() {
    print_test_header "Test 6: Ingress Configuration"
    
    # Check if ingress exists
    if kubectl get ingress -n $NAMESPACE kafka-ingress &> /dev/null; then
        print_color "$GREEN" "✓ Ingress exists"
        
        # Check ingress configuration
        local host=$(kubectl get ingress -n $NAMESPACE kafka-ingress -o jsonpath='{.spec.rules[0].host}')
        if [ "$host" == "kafka.nks.stjeong.com" ]; then
            print_color "$GREEN" "✓ Correct host configured: $host"
            record_test "Ingress Configuration" "PASS" "Ingress is properly configured"
        else
            record_test "Ingress Configuration" "FAIL" "Incorrect host: $host"
        fi
        
        # Show ingress details
        echo
        kubectl get ingress -n $NAMESPACE
    else
        record_test "Ingress Configuration" "FAIL" "Ingress not found"
    fi
}

# Generate test report
generate_report() {
    print_test_header "Test Summary Report"
    
    local report_file="test-results-real-$(date +%Y%m%d-%H%M%S).txt"
    
    {
        echo "Kafka Kubernetes Deployment REAL Test Results"
        echo "============================================"
        echo "Date: $(date)"
        echo "Total Tests: $TESTS_TOTAL"
        echo "Passed: $TESTS_PASSED"
        echo "Failed: $TESTS_FAILED"
        echo ""
        echo "Test Results:"
        echo "-------------"
        for result in "${TEST_RESULTS[@]}"; do
            echo "$result"
        done
        echo ""
        
        if [ "$TESTS_FAILED" -eq 0 ]; then
            echo "Status: ✅ ALL TESTS PASSED"
        else
            echo "Status: ❌ SOME TESTS FAILED"
        fi
    } | tee "$report_file"
    
    echo
    print_color "$BLUE" "Test report saved to: $report_file"
    
    # Exit with appropriate code
    if [ "$TESTS_FAILED" -gt 0 ]; then
        exit 1
    fi
}

# Main execution
main() {
    print_color "$BLUE" "Starting Kafka Kubernetes Deployment REAL Tests..."
    print_color "$YELLOW" "This will create and test actual resources in your cluster!"
    
    check_prerequisites
    
    test_namespace_creation
    test_single_node_deployment
    test_cluster_deployment
    test_service_connectivity
    test_persistent_storage
    test_ingress_configuration
    
    generate_report
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --no-cleanup)
            CLEANUP_ON_EXIT=false
            shift
            ;;
        --namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--no-cleanup] [--namespace <name>]"
            exit 1
            ;;
    esac
done

# Run tests
main "$@"