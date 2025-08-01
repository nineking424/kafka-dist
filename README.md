# Kafka Kubernetes Distribution

A production-ready Kubernetes deployment for Apache Kafka 4.0.1 using KRaft mode (no ZooKeeper required). This repository provides both single-node and multi-node cluster configurations optimized for Kubernetes environments.

## Features

- **KRaft Mode**: Modern Kafka deployment without ZooKeeper dependency
- **Dual Deployment Modes**: Single-node for development, multi-node cluster for production
- **Kubernetes Native**: StatefulSets, persistent storage, and service discovery
- **External Access**: Ingress configuration for external client connections
- **Production Ready**: Health checks, resource management, and data persistence
- **Comprehensive Testing**: Automated validation scripts with detailed reporting
- **Easy Management**: Makefile for common operations and deployment tasks

## Quick Start

```bash
# Create namespace
kubectl apply -f 00-namespace.yaml

# Deploy single-node Kafka (development)
kubectl apply -f single/

# OR deploy multi-node cluster (production)
kubectl apply -f cluster/
```

## Project Structure

```
kafka-dist/
├── 00-namespace.yaml          # Kafka namespace definition
├── single/                    # Single-node deployment
│   ├── statefulset.yaml      # Kafka broker/controller StatefulSet
│   ├── service.yaml          # Headless and ClusterIP services
│   └── ingress.yaml          # Ingress for external access
├── cluster/                   # Multi-node cluster deployment
│   ├── controller-statefulset.yaml  # KRaft controllers (3 replicas)
│   ├── broker-statefulset.yaml      # Kafka brokers (3 replicas)
│   ├── services.yaml               # All required services
│   └── ingress.yaml                # Ingress configuration
├── test/                      # Testing framework
│   ├── test-deployment.sh    # Comprehensive test suite
│   ├── quick-test.sh         # Quick validation script
│   ├── TEST_REPORT.md        # Sample test report
│   └── README.md             # Testing documentation
├── Makefile                   # Automation commands
├── README.md                  # This file
└── CLAUDE.md                  # AI-assisted development guide
```

## Prerequisites

- Kubernetes cluster (v1.21+)
- kubectl CLI tool configured
- Storage class for persistent volumes
- Ingress controller (for external access)

## Architecture

### Single-Node Deployment

The single-node deployment (`single/` directory) is designed for development and testing:

- **Combined Roles**: Single Kafka instance acts as both broker and controller
- **Minimal Resources**: Reduced resource requirements for development environments
- **Simple Configuration**: All-in-one deployment with single StatefulSet
- **Components**:
  - 1x Kafka StatefulSet (broker + controller)
  - 1x Headless Service for internal communication
  - 1x Ingress for external access
  - 10Gi persistent volume for data

### Multi-Node Cluster Deployment

The cluster deployment (`cluster/` directory) is designed for production use:

- **Separated Roles**: Dedicated controller and broker nodes for better scalability
- **High Availability**: 3 controllers and 3 brokers for fault tolerance
- **Production Configuration**: Optimized for reliability and performance
- **Components**:
  - 3x Controller StatefulSet (KRaft consensus)
  - 3x Broker StatefulSet (data storage and client serving)
  - Multiple services for internal and external communication
  - Ingress configuration for external access
  - Persistent storage for each node

## Deployment Guide

### Single-Node Deployment

1. **Create the namespace**:
   ```bash
   kubectl apply -f 00-namespace.yaml
   ```

2. **Deploy Kafka**:
   ```bash
   kubectl apply -f single/
   ```

3. **Verify deployment**:
   ```bash
   # Check pod status
   kubectl get pods -n kafka
   
   # Check services
   kubectl get svc -n kafka
   
   # View logs
   kubectl logs -n kafka kafka-0
   ```

4. **Test connectivity**:
   ```bash
   # Create a test pod
   kubectl run -it --rm kafka-test \
     --image=apache/kafka:4.0.1-rc0 \
     --restart=Never -n kafka -- \
     kafka-topics.sh --bootstrap-server kafka-headless:9092 --list
   ```

### Multi-Node Cluster Deployment

1. **Create the namespace**:
   ```bash
   kubectl apply -f 00-namespace.yaml
   ```

2. **Deploy the cluster**:
   ```bash
   kubectl apply -f cluster/
   ```

3. **Monitor deployment**:
   ```bash
   # Watch controller pods come up
   kubectl get pods -n kafka -l app=kafka-controller -w
   
   # Watch broker pods come up
   kubectl get pods -n kafka -l app=kafka-broker -w
   ```

4. **Verify cluster health**:
   ```bash
   # Check cluster metadata
   kubectl exec -it kafka-broker-0 -n kafka -- \
     kafka-metadata-shell.sh --snapshot /var/lib/kafka/data/__cluster_metadata-0/00000000000000000000.log --print-brokers
   ```

## Configuration

### Environment Variables

Key environment variables used in the deployments:

| Variable | Description | Single-Node | Cluster |
|----------|-------------|-------------|---------|
| `KAFKA_NODE_ID` | Unique broker/controller ID | 1 | Dynamic (0-2 for controllers, 3-5 for brokers) |
| `KAFKA_PROCESS_ROLES` | Node role (broker/controller) | broker,controller | controller OR broker |
| `KAFKA_CONTROLLER_QUORUM_VOTERS` | Controller quorum configuration | 1@kafka-0:29093 | 0@controller-0:29093,1@controller-1:29093,2@controller-2:29093 |
| `CLUSTER_ID` | Kafka cluster identifier | 4L6g3nShT-eMCtK--X86sw | 4L6g3nShT-eMCtK--X86sw |
| `KAFKA_LOG_DIRS` | Data directory path | /var/lib/kafka/data | /var/lib/kafka/data |

### Networking

#### Ports

- **9092**: Client connections (PLAINTEXT)
- **19092**: Inter-broker communication (PLAINTEXT)
- **29093**: Controller communication (KRaft consensus)

#### External Access

External access is configured via Ingress:
- **Host**: kafka.nks.stjeong.com
- **Port**: 9092
- **Protocol**: TCP (requires NGINX Ingress with TCP services support)

### Storage

Each Kafka node uses persistent storage:
- **Single-node**: 10Gi per node
- **Cluster controllers**: 5Gi per controller
- **Cluster brokers**: 20Gi per broker
- **Storage class**: Uses cluster default (configure as needed)

## Client Connection

### Internal Clients (within Kubernetes)

```bash
# Single-node
bootstrap.servers=kafka-headless.kafka.svc.cluster.local:9092

# Cluster
bootstrap.servers=kafka-broker-headless.kafka.svc.cluster.local:9092
```

### External Clients

```bash
# Via Ingress
bootstrap.servers=kafka.nks.stjeong.com:9092
```

### Example Producer/Consumer

```bash
# Producer
kubectl exec -it kafka-0 -n kafka -- \
  kafka-console-producer.sh \
  --bootstrap-server localhost:9092 \
  --topic test-topic

# Consumer
kubectl exec -it kafka-0 -n kafka -- \
  kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic test-topic \
  --from-beginning
```

## Operations

### Quick Commands (Makefile)

A Makefile is provided for common operations:

```bash
# Deployment
make namespace         # Create kafka namespace
make deploy-single     # Deploy single-node Kafka
make deploy-cluster    # Deploy Kafka cluster

# Testing
make test             # Run comprehensive tests
make quick-test       # Run quick validation
make validate         # Validate YAML syntax

# Management
make status           # Show Kafka resources
make logs-single      # View single-node logs
make logs-broker      # View broker logs
make logs-controller  # View controller logs

# Cleanup
make clean-single     # Remove single-node deployment
make clean-cluster    # Remove cluster deployment
make clean-all        # Remove all Kafka resources

# Development
make port-forward-single   # Forward port 9092 (single-node)
make port-forward-cluster  # Forward port 9092 (cluster)
```

### Scaling

#### Single-Node
The single-node deployment is not designed for scaling. For production use, deploy the cluster version.

#### Cluster Scaling

Scale brokers (not controllers):
```bash
# Scale up brokers
kubectl scale statefulset kafka-broker -n kafka --replicas=5

# Scale down brokers (ensure proper partition reassignment first)
kubectl scale statefulset kafka-broker -n kafka --replicas=3
```

### Monitoring

Check cluster health:
```bash
# View logs
kubectl logs -f -n kafka kafka-broker-0

# Check metrics (if JMX is enabled)
kubectl exec -it kafka-broker-0 -n kafka -- \
  kafka-metadata-shell.sh --snapshot /var/lib/kafka/data/__cluster_metadata-0/00000000000000000000.log --print-brokers
```

### Backup and Recovery

1. **Backup data**:
   ```bash
   # Create snapshot of PVCs
   kubectl get pvc -n kafka
   ```

2. **Topic backup**:
   ```bash
   # List topics
   kubectl exec -it kafka-broker-0 -n kafka -- \
     kafka-topics.sh --bootstrap-server localhost:9092 --list
   
   # Describe topic
   kubectl exec -it kafka-broker-0 -n kafka -- \
     kafka-topics.sh --bootstrap-server localhost:9092 --describe --topic <topic-name>
   ```

## Troubleshooting

### Common Issues

1. **Pods not starting**:
   ```bash
   # Check pod events
   kubectl describe pod <pod-name> -n kafka
   
   # Check logs
   kubectl logs <pod-name> -n kafka
   ```

2. **Connection refused**:
   - Verify services are running: `kubectl get svc -n kafka`
   - Check ingress configuration: `kubectl get ingress -n kafka`
   - Ensure advertised listeners are correctly configured

3. **Storage issues**:
   ```bash
   # Check PVC status
   kubectl get pvc -n kafka
   
   # Check available storage classes
   kubectl get storageclass
   ```

### Useful Commands

```bash
# Get all Kafka resources
kubectl get all -n kafka

# Describe StatefulSets
kubectl describe statefulset -n kafka

# Check resource usage
kubectl top pods -n kafka

# Delete and recreate (CAUTION: Data loss)
kubectl delete -f single/  # or cluster/
kubectl apply -f single/   # or cluster/
```

## Security Considerations

1. **Network Policies**: Consider implementing network policies to restrict traffic
2. **TLS/SSL**: For production, enable SSL for all listeners
3. **Authentication**: Configure SASL/SCRAM or mTLS for client authentication
4. **Authorization**: Enable Kafka ACLs for fine-grained access control
5. **Secrets Management**: Use Kubernetes secrets for sensitive configurations

## Testing

This project includes a comprehensive testing framework to validate all deployment configurations before applying them to your Kubernetes cluster.

### Test Suite Overview

The `test/` directory contains automated test scripts that validate:
- ✅ YAML syntax for all Kubernetes manifests
- ✅ Resource creation and dependencies
- ✅ Configuration parameters and environment variables
- ✅ Health check and probe configurations
- ✅ Service and ingress port mappings
- ✅ KRaft mode configuration (no ZooKeeper)
- ✅ Storage requirements and persistent volume claims

### Running Tests

#### Using Makefile (Recommended)
```bash
# Run comprehensive test suite (8 test categories)
make test

# Run quick validation tests
make quick-test

# Validate YAML syntax only
make validate
```

#### Direct Script Execution
```bash
# Comprehensive testing with detailed reports
./test/test-deployment.sh

# Quick validation for development
./test/quick-test.sh
```

### Test Scripts

1. **`test-deployment.sh`** - Full test suite that performs:
   - Kubernetes manifest validation
   - Deployment structure verification
   - Resource requirement analysis
   - Configuration compliance checks
   - Generates timestamped test reports

2. **`quick-test.sh`** - Lightweight validation for rapid feedback:
   - Basic YAML syntax checking
   - Resource count verification
   - Quick health summary

### Test Output

Tests provide colored output for easy reading:
- 🟢 **Green**: Test passed
- 🔴 **Red**: Test failed
- 🟡 **Yellow**: Warnings or info
- 🔵 **Blue**: Test headers

Test results are saved to timestamped files: `test/test-results-YYYYMMDD-HHMMSS.txt`

### CI/CD Integration

The test scripts return appropriate exit codes:
- `0` - All tests passed
- `1` - One or more tests failed

This makes them suitable for CI/CD pipeline integration:
```yaml
# Example GitHub Actions
- name: Validate Kafka Deployment
  run: make test
```

See [test/README.md](test/README.md) for detailed testing documentation and examples.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly in both single and cluster modes
5. Submit a pull request

## License

This project is licensed under the Apache License 2.0 - see the LICENSE file for details.

## References

- [Apache Kafka Documentation](https://kafka.apache.org/documentation/)
- [Kafka KRaft Mode](https://kafka.apache.org/documentation/#kraft)
- [Kubernetes StatefulSets](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/)
- [NGINX Ingress TCP Services](https://kubernetes.github.io/ingress-nginx/user-guide/exposing-tcp-udp-services/)