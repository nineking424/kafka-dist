#!/bin/bash

# Kafka Kubernetes Deployment Test Script
# This script validates all aspects of the Kafka deployment configurations

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
        kubectl version --short
    else
        print_color "$YELLOW" "⚠️  Warning: Not connected to a Kubernetes cluster. Some tests will be limited."
    fi
}

# Test 1: Validate YAML Syntax
test_yaml_syntax() {
    print_test_header "Test 1: YAML Syntax Validation"
    
    local all_valid=true
    local failed_files=""
    
    # Find all YAML files
    while IFS= read -r -d '' file; do
        if kubectl apply --dry-run=client -f "$file" &> /dev/null; then
            print_color "$GREEN" "  ✓ $file"
        else
            all_valid=false
            failed_files="$failed_files $file"
            print_color "$RED" "  ✗ $file"
        fi
    done < <(find . -name "*.yaml" -type f -print0)
    
    if [ "$all_valid" = true ]; then
        record_test "YAML Syntax Validation" "PASS" "All YAML files are valid"
    else
        record_test "YAML Syntax Validation" "FAIL" "Invalid files:$failed_files"
    fi
}

# Test 2: Single-Node Deployment Validation
test_single_node_deployment() {
    print_test_header "Test 2: Single-Node Deployment Validation"
    
    local resources_expected=6  # namespace + statefulset + 2 services + ingress + configmap
    local resources_found=0
    
    # Count resources that would be created
    resources_found=$(kubectl apply --dry-run=client -f 00-namespace.yaml -f single/ 2>&1 | grep -c "created (dry run)" || true)
    
    echo "Expected resources: $resources_expected"
    echo "Found resources: $resources_found"
    
    # List resources
    kubectl apply --dry-run=client -f 00-namespace.yaml -f single/ 2>&1 | grep "created (dry run)" | sed 's/^/  /'
    
    if [ "$resources_found" -eq "$resources_expected" ]; then
        record_test "Single-Node Deployment Structure" "PASS" "$resources_found resources validated"
    else
        record_test "Single-Node Deployment Structure" "FAIL" "Expected $resources_expected resources, found $resources_found"
    fi
}

# Test 3: Cluster Deployment Validation
test_cluster_deployment() {
    print_test_header "Test 3: Cluster Deployment Validation"
    
    local resources_expected=11  # namespace + 2 statefulsets + 6 services + ingress + configmap
    local resources_found=0
    
    # Count resources that would be created
    resources_found=$(kubectl apply --dry-run=client -f 00-namespace.yaml -f cluster/ 2>&1 | grep -c "created (dry run)" || true)
    
    echo "Expected resources: $resources_expected"
    echo "Found resources: $resources_found"
    
    # List resources
    kubectl apply --dry-run=client -f 00-namespace.yaml -f cluster/ 2>&1 | grep "created (dry run)" | sed 's/^/  /'
    
    if [ "$resources_found" -eq "$resources_expected" ]; then
        record_test "Cluster Deployment Structure" "PASS" "$resources_found resources validated"
    else
        record_test "Cluster Deployment Structure" "FAIL" "Expected $resources_expected resources, found $resources_found"
    fi
}

# Test 4: Resource Requirements
test_resource_requirements() {
    print_test_header "Test 4: Resource Requirements Analysis"
    
    local all_good=true
    local issues=""
    
    # Check single-node storage
    print_color "$YELLOW" "Single-Node Storage:"
    single_storage=$(grep -A3 "storage:" single/statefulset.yaml | grep -oE "[0-9]+Gi" | head -1 || echo "Not found")
    echo "  Storage: $single_storage"
    
    # Check cluster storage
    print_color "$YELLOW" "Cluster Controller Storage:"
    controller_storage=$(grep -A3 "storage:" cluster/controller-statefulset.yaml | grep -oE "[0-9]+Gi" | head -1 || echo "Not found")
    echo "  Storage: $controller_storage"
    
    print_color "$YELLOW" "Cluster Broker Storage:"
    broker_storage=$(grep -A3 "storage:" cluster/broker-statefulset.yaml | grep -oE "[0-9]+Gi" | head -1 || echo "Not found")
    echo "  Storage: $broker_storage"
    
    # Check for CPU/Memory limits
    print_color "$YELLOW" "Resource Limits Check:"
    if grep -q "limits:" single/statefulset.yaml cluster/*.yaml 2>/dev/null; then
        echo "  ✓ Resource limits defined"
    else
        echo "  ⚠️  No CPU/Memory limits defined (allows flexible allocation)"
        issues="$issues; No resource limits defined"
    fi
    
    # Validate storage values
    if [[ "$single_storage" == "10Gi" && "$controller_storage" == "5Gi" && "$broker_storage" == "20Gi" ]]; then
        record_test "Storage Configuration" "PASS" "Storage correctly configured"
    else
        all_good=false
        record_test "Storage Configuration" "FAIL" "Unexpected storage values"
    fi
    
    # Overall resource test
    if [ "$all_good" = true ]; then
        record_test "Resource Requirements" "PASS" "All resource configurations valid$issues"
    else
        record_test "Resource Requirements" "FAIL" "Resource configuration issues found"
    fi
}

# Test 5: Health Checks
test_health_checks() {
    print_test_header "Test 5: Health Check Configuration"
    
    local all_good=true
    local missing=""
    
    # Check single-node health checks
    print_color "$YELLOW" "Single-Node Health Checks:"
    if grep -q "livenessProbe:" single/statefulset.yaml && grep -q "readinessProbe:" single/statefulset.yaml; then
        echo "  ✓ Liveness and Readiness probes configured"
        
        # Check probe details
        liveness_port=$(grep -A3 "livenessProbe:" single/statefulset.yaml | grep "port:" | grep -oE "[0-9]+" | head -1)
        readiness_port=$(grep -A3 "readinessProbe:" single/statefulset.yaml | grep "port:" | grep -oE "[0-9]+" | head -1)
        echo "  Liveness port: $liveness_port"
        echo "  Readiness port: $readiness_port"
    else
        all_good=false
        missing="$missing single-node"
    fi
    
    # Check cluster health checks
    print_color "$YELLOW" "Cluster Health Checks:"
    for file in cluster/controller-statefulset.yaml cluster/broker-statefulset.yaml; do
        basename_file=$(basename "$file")
        if grep -q "livenessProbe:" "$file" && grep -q "readinessProbe:" "$file"; then
            echo "  ✓ $basename_file: Probes configured"
        else
            all_good=false
            missing="$missing $basename_file"
        fi
    done
    
    if [ "$all_good" = true ]; then
        record_test "Health Check Configuration" "PASS" "All health checks properly configured"
    else
        record_test "Health Check Configuration" "FAIL" "Missing health checks in:$missing"
    fi
}

# Test 6: Service and Port Configuration
test_service_configuration() {
    print_test_header "Test 6: Service and Port Configuration"
    
    local all_good=true
    local issues=""
    
    # Expected ports
    local expected_ports="9092 19092 29093"
    
    print_color "$YELLOW" "Port Configuration Check:"
    
    # Check single-node services
    echo "Single-Node Services:"
    for port in $expected_ports; do
        if grep -q "port: $port" single/service.yaml single/statefulset.yaml; then
            echo "  ✓ Port $port configured"
        else
            echo "  ✗ Port $port missing"
            all_good=false
            issues="$issues; Port $port missing in single-node"
        fi
    done
    
    # Check cluster services
    echo "Cluster Services:"
    for port in $expected_ports; do
        if grep -q "port: $port" cluster/services.yaml cluster/*.yaml; then
            echo "  ✓ Port $port configured"
        else
            echo "  ✗ Port $port missing"
            all_good=false
            issues="$issues; Port $port missing in cluster"
        fi
    done
    
    if [ "$all_good" = true ]; then
        record_test "Service Port Configuration" "PASS" "All required ports configured"
    else
        record_test "Service Port Configuration" "FAIL" "Port configuration issues:$issues"
    fi
}

# Test 7: Ingress Configuration
test_ingress_configuration() {
    print_test_header "Test 7: Ingress Configuration"
    
    local all_good=true
    local expected_host="kafka.nks.stjeong.com"
    
    # Check single-node ingress
    print_color "$YELLOW" "Single-Node Ingress:"
    if grep -q "$expected_host" single/ingress.yaml; then
        echo "  ✓ Host configured: $expected_host"
    else
        echo "  ✗ Host not properly configured"
        all_good=false
    fi
    
    # Check cluster ingress
    print_color "$YELLOW" "Cluster Ingress:"
    if grep -q "$expected_host" cluster/ingress.yaml; then
        echo "  ✓ Host configured: $expected_host"
    else
        echo "  ✗ Host not properly configured"
        all_good=false
    fi
    
    # Check TCP services ConfigMap
    if grep -q "tcp-services" single/ingress.yaml && grep -q "tcp-services" cluster/ingress.yaml; then
        echo "  ✓ TCP services ConfigMap configured"
    else
        echo "  ✗ TCP services ConfigMap missing"
        all_good=false
    fi
    
    if [ "$all_good" = true ]; then
        record_test "Ingress Configuration" "PASS" "Ingress properly configured for $expected_host"
    else
        record_test "Ingress Configuration" "FAIL" "Ingress configuration issues found"
    fi
}

# Test 8: KRaft Configuration
test_kraft_configuration() {
    print_test_header "Test 8: KRaft Mode Configuration"
    
    local all_good=true
    local cluster_id="4L6g3nShT-eMCtK--X86sw"
    
    # Check for KRaft-specific environment variables
    print_color "$YELLOW" "KRaft Configuration Check:"
    
    # Check CLUSTER_ID
    if grep -q "CLUSTER_ID" single/statefulset.yaml cluster/*.yaml; then
        echo "  ✓ CLUSTER_ID configured"
        
        # Verify cluster ID value
        if grep -q "$cluster_id" single/statefulset.yaml cluster/*.yaml; then
            echo "  ✓ Cluster ID matches expected: $cluster_id"
        else
            echo "  ✗ Cluster ID mismatch"
            all_good=false
        fi
    else
        echo "  ✗ CLUSTER_ID not found"
        all_good=false
    fi
    
    # Check for controller quorum voters
    if grep -q "KAFKA_CONTROLLER_QUORUM_VOTERS" single/statefulset.yaml cluster/*.yaml; then
        echo "  ✓ Controller quorum voters configured"
    else
        echo "  ✗ Controller quorum voters missing"
        all_good=false
    fi
    
    # Check process roles
    if grep -q "KAFKA_PROCESS_ROLES" single/statefulset.yaml cluster/*.yaml; then
        echo "  ✓ Process roles configured"
    else
        echo "  ✗ Process roles missing"
        all_good=false
    fi
    
    if [ "$all_good" = true ]; then
        record_test "KRaft Configuration" "PASS" "KRaft mode properly configured"
    else
        record_test "KRaft Configuration" "FAIL" "KRaft configuration issues found"
    fi
}

# Generate test report
generate_report() {
    print_test_header "Test Summary Report"
    
    local report_file="test-results-$(date +%Y%m%d-%H%M%S).txt"
    
    {
        echo "Kafka Kubernetes Deployment Test Results"
        echo "========================================"
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
    print_color "$BLUE" "Starting Kafka Kubernetes Deployment Tests..."
    
    check_prerequisites
    
    test_yaml_syntax
    test_single_node_deployment
    test_cluster_deployment
    test_resource_requirements
    test_health_checks
    test_service_configuration
    test_ingress_configuration
    test_kraft_configuration
    
    generate_report
}

# Run tests
main "$@"