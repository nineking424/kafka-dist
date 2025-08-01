# Kafka Kubernetes Deployment Tests

This directory contains all testing scripts and reports for the Kafka Kubernetes deployment configurations.

## Test Scripts

### 1. `test-deployment.sh`
Comprehensive test suite that validates all aspects of the Kafka deployments:
- YAML syntax validation
- Deployment structure verification
- Resource requirements analysis
- Health check configuration
- Service and port configuration
- Ingress configuration
- KRaft mode validation

**Usage:**
```bash
./test/test-deployment.sh
```

### 2. `quick-test.sh`
Lightweight validation script for rapid testing during development:
- Basic YAML validation
- Resource count verification
- Quick health summary

**Usage:**
```bash
./test/quick-test.sh
```

## Test Reports

- `TEST_REPORT.md` - Sample comprehensive test report
- `test-results-*.txt` - Generated test results with timestamps

## Running Tests

### Using Makefile (Recommended)
From the project root directory:
```bash
make test        # Run comprehensive tests
make quick-test  # Run quick validation
make validate    # Validate YAML syntax only
```

### Direct Execution
From the project root directory:
```bash
./test/test-deployment.sh  # Comprehensive tests
./test/quick-test.sh       # Quick tests
```

## Test Coverage

The test suite covers:
1. **Syntax Validation** - All YAML files are valid Kubernetes manifests
2. **Resource Validation** - Correct number and types of resources
3. **Configuration Validation** - Ports, storage, health checks
4. **KRaft Mode** - Proper KRaft configuration without ZooKeeper
5. **Deployment Modes** - Both single-node and cluster configurations

## Exit Codes

- `0` - All tests passed
- `1` - One or more tests failed

## Requirements

- `kubectl` CLI tool must be installed
- Connection to a Kubernetes cluster is optional but provides more thorough testing