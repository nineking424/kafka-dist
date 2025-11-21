# Kafka Kubernetes Distribution

Production-ready Kubernetes deployment for Apache Kafka 4.0.1 using KRaft mode (no ZooKeeper). This repository provides both single-node and multi-node cluster configurations with modern Kubernetes patterns and best practices.

## Features

- **KRaft Mode**: Modern Kafka deployment without ZooKeeper dependency
- **ConfigMap + Init Container Pattern**: Clean separation of configuration management
- **Dual Deployment Modes**: Single-node for development, multi-node cluster for production
- **Kubernetes Native**: StatefulSets with proper service discovery and persistent storage
- **Production Ready**: Health checks, resource management, lock file handling, and data persistence
- **Comprehensive Testing**: Dry-run validation and real deployment testing with automated cleanup
- **Easy Management**: Makefile automation and Kaskade TUI support

## Architecture Overview

### Configuration Management

This project uses the **ConfigMap + Init Container pattern** for configuration management:

1. **ConfigMaps** store base configuration templates
2. **Init Containers** generate dynamic configuration at runtime
3. **Clean separation** between static and dynamic configuration
4. **Automatic lock file cleanup** prevents startup failures

### Service Architecture

Services follow a clear naming convention for better clarity:

- `kafka-broker`: Headless service for broker StatefulSet
- `kafka-client`: Client-facing service for external connections
- `kafka-controller`: Headless service for controller StatefulSet

### Listener Configuration

Clear distinction between internal and external communication:

- **EXTERNAL**: Client connections from outside the cluster
- **INTERNAL**: Inter-broker communication within the cluster
- **CONTROLLER**: KRaft consensus protocol between controllers

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
├── 00-namespace.yaml                    # Kafka namespace definition
├── single/                              # Single-node deployment
│   ├── statefulset.yaml                # Combined broker/controller
│   ├── service.yaml                    # Headless and client services
│   └── configmap.yaml                  # Single-node configuration
├── cluster/                             # Multi-node cluster deployment
│   ├── broker-statefulset.yaml         # Kafka brokers (3 replicas)
│   ├── broker-configmap.yaml           # Broker configuration template
│   ├── broker-service.yaml             # Broker services
│   ├── controller-statefulset.yaml     # KRaft controllers (3 replicas)
│   ├── controller-configmap.yaml       # Controller configuration template
│   └── controller-service.yaml         # Controller service
├── test/                                # Testing framework
│   ├── test-deployment.sh              # Dry-run validation suite
│   ├── test-deployment-real.sh         # Real deployment testing
│   └── quick-test.sh                   # Quick validation
├── Makefile                             # Automation commands
├── README.md                            # This file
└── CLAUDE.md                            # AI-assisted development guide
```

## Prerequisites

- Kubernetes cluster (v1.21+)
- kubectl CLI configured
- Storage class for persistent volumes
- 192.168.3.14 as the external IP for broker access (configurable)

## Deployment Architectures

### Single-Node Deployment

The single-node deployment (`single/` directory) for development and testing:

- **Combined Roles**: Single instance acts as both broker and controller
- **Simplified Configuration**: All-in-one deployment with single StatefulSet
- **ConfigMap**: Base configuration with runtime property generation
- **Resource Requirements**: 1GB memory, 500m CPU
- **Storage**: 10Gi persistent volume

### Multi-Node Cluster Deployment

The cluster deployment (`cluster/` directory) for production use:

#### Controllers (3 replicas)
- **Dedicated Role**: KRaft consensus management only
- **Node IDs**: 0, 1, 2 (automatically assigned from pod ordinal)
- **ConfigMap**: `kafka-controller-config` with base properties
- **Init Container**: Generates node-specific configuration
- **Resource Requirements**: 1GB memory, 500m CPU per controller
- **Storage**: 5Gi persistent volume per controller

#### Brokers (3 replicas)
- **Dedicated Role**: Data storage and client serving
- **Node IDs**: 3, 4, 5 (pod ordinal + 3)
- **ConfigMap**: `kafka-broker-config` with base properties
- **Init Container**: Generates node-specific configuration with advertised listeners
- **Resource Requirements**: 2GB memory, 1 CPU per broker
- **Storage**: 20Gi persistent volume per broker

## Configuration Details

### ConfigMap + Init Container Pattern

Each StatefulSet uses a two-stage configuration process:

1. **ConfigMap** provides base configuration template:
   ```yaml
   data:
     broker-base.properties: |
       # Static configuration
       process.roles=broker
       listener.security.protocol.map=CONTROLLER:PLAINTEXT,INTERNAL:PLAINTEXT,EXTERNAL:PLAINTEXT
   ```

2. **Init Container** generates runtime configuration:
   ```bash
   # Calculate NODE_ID from pod ordinal
   NODE_ID=$((${HOSTNAME##*-} + 3))

   # Generate advertised listeners
   ADVERTISED_LISTENERS="EXTERNAL://192.168.3.14:9092,INTERNAL://${HOSTNAME}.kafka-broker.kafka.svc.cluster.local:19092"

   # Clean up stale lock files
   if [ -f /var/lib/kafka/data/.lock ]; then
     rm -f /var/lib/kafka/data/.lock
   fi
   ```

### Key Configuration Parameters

| Parameter | Controllers | Brokers |
|-----------|------------|---------|
| `node.id` | 0-2 (from pod ordinal) | 3-5 (pod ordinal + 3) |
| `process.roles` | controller | broker |
| `listeners` | CONTROLLER://:29093 | EXTERNAL://:9092,INTERNAL://:19092 |
| `advertised.listeners` | N/A | EXTERNAL://192.168.3.14:9092,INTERNAL://hostname:19092 |
| `controller.quorum.voters` | 0@controller-0:29093,1@controller-1:29093,2@controller-2:29093 | Same |
| `log.dirs` | /var/lib/kafka/data | /var/lib/kafka/data |

### Network Configuration

#### Ports
- **9092**: External client connections (EXTERNAL listener)
- **19092**: Inter-broker communication (INTERNAL listener)
- **29093**: Controller consensus (CONTROLLER listener)

#### Services
- **kafka-broker**: Headless service for broker pod discovery
- **kafka-client**: ClusterIP service for client connections
- **kafka-controller**: Headless service for controller pod discovery

### Storage Management

Each node uses PersistentVolumeClaims with automatic lock file cleanup:

- **Controllers**: 5Gi per controller
- **Brokers**: 20Gi per broker
- **Lock file handling**: Automatic cleanup in init containers prevents startup failures

## Client Connection

### Internal Clients (within Kubernetes)

```bash
# Single-node
bootstrap.servers=kafka-headless.kafka.svc.cluster.local:9092

# Cluster
bootstrap.servers=kafka-client.kafka.svc.cluster.local:9092
```

### External Clients

```bash
# Direct connection (requires network access to 192.168.3.14)
bootstrap.servers=192.168.3.14:9092
```

### Example Usage

```bash
# Create topic
kubectl exec -it kafka-broker-0 -n kafka -- \
  kafka-topics.sh --bootstrap-server localhost:9092 \
  --create --topic test-topic --partitions 3 --replication-factor 3

# Producer
kubectl exec -it kafka-broker-0 -n kafka -- \
  kafka-console-producer.sh \
  --bootstrap-server localhost:9092 \
  --topic test-topic

# Consumer
kubectl exec -it kafka-broker-0 -n kafka -- \
  kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic test-topic --from-beginning
```

## Operations

### Using the Makefile

Common operations are automated via Makefile:

```bash
# Deployment
make namespace           # Create kafka namespace
make deploy-single       # Deploy single-node Kafka
make deploy-cluster      # Deploy Kafka cluster

# Testing
make test               # Run dry-run validation (safe)
make test-real          # Run real deployment tests
make quick-test         # Quick validation check

# Management
make status             # Show Kafka resources
make logs-broker        # View broker logs
make logs-controller    # View controller logs
make shell-broker       # Shell into broker-0
make shell-controller   # Shell into controller-0

# Cleanup
make clean-single       # Remove single-node deployment
make clean-cluster      # Remove cluster deployment
make clean-all          # Remove all Kafka resources
```

### Using Kaskade (Kafka TUI Manager)

Deploy Kaskade for interactive Kafka management:

```bash
# Deploy Kaskade
kubectl run kaskade -n kafka \
  --image=sauljabin/kaskade:latest \
  --rm -it -- \
  kaskade -b kafka-client:9092

# Features available:
# - View brokers and topics
# - Monitor consumer groups
# - Create/delete topics
# - View partition details
# - Monitor real-time metrics
```

### Monitoring and Troubleshooting

#### Check Cluster Health

```bash
# View all resources
kubectl get all -n kafka

# Check pod status
kubectl get pods -n kafka -o wide

# View StatefulSet status
kubectl get sts -n kafka

# Check persistent volumes
kubectl get pvc -n kafka
```

#### View Logs

```bash
# Controller logs
kubectl logs -f kafka-controller-0 -n kafka

# Broker logs
kubectl logs -f kafka-broker-0 -n kafka

# Init container logs (for debugging configuration)
kubectl logs kafka-broker-0 -n kafka -c config-generator
```

#### Common Issues and Solutions

1. **Lock File Issues**
   ```bash
   # Error: "Failed to acquire lock on file .lock"
   # Solution: Automatic cleanup in init containers
   # Manual fix if needed:
   kubectl exec -it kafka-broker-0 -n kafka -- rm /var/lib/kafka/data/.lock
   ```

2. **Pod Stuck in Init**
   ```bash
   # Check init container logs
   kubectl logs <pod-name> -n kafka -c config-generator

   # Verify ConfigMap exists
   kubectl get configmap -n kafka
   ```

3. **Connection Issues**
   ```bash
   # Verify services
   kubectl get svc -n kafka

   # Check advertised listeners
   kubectl exec kafka-broker-0 -n kafka -- cat /shared/broker.properties | grep advertised
   ```

### Scaling Operations

#### Scale Brokers

```bash
# Scale up (ensure node IDs are adjusted)
kubectl scale statefulset kafka-broker -n kafka --replicas=5

# Scale down (ensure proper partition reassignment first)
kubectl scale statefulset kafka-broker -n kafka --replicas=3
```

**Note**: Controllers should remain at 3 replicas for quorum stability.

### Backup and Recovery

```bash
# List topics and configurations
kubectl exec -it kafka-broker-0 -n kafka -- \
  kafka-topics.sh --bootstrap-server localhost:9092 --list

# Describe topic for backup
kubectl exec -it kafka-broker-0 -n kafka -- \
  kafka-topics.sh --bootstrap-server localhost:9092 \
  --describe --topic <topic-name>

# Backup PVC data (platform-specific)
kubectl get pvc -n kafka
```

## Testing Framework

The project includes comprehensive testing capabilities:

### Test Types

1. **Dry-Run Validation** (`make test`)
   - YAML syntax validation
   - Resource dependency checking
   - Configuration compliance
   - No actual resources created

2. **Real Deployment Testing** (`make test-real`)
   - Deploys actual Kafka cluster
   - Validates pod readiness
   - Tests Kafka functionality
   - Automatic cleanup included

3. **Quick Validation** (`make quick-test`)
   - Basic syntax checking
   - Resource count verification

### Running Tests

```bash
# Safe validation (no resources created)
./test/test-deployment.sh

# Real deployment test with cleanup
./test/test-deployment-real.sh

# Keep resources after test
./test/test-deployment-real.sh --no-cleanup

# Custom namespace
./test/test-deployment-real.sh --namespace kafka-test
```

## Security Considerations

### Current Implementation

- **PLAINTEXT** communication (suitable for development)
- **No authentication** configured
- **Basic network isolation** via Kubernetes namespaces

### Production Recommendations

1. **Enable TLS/SSL** for all listeners
2. **Configure SASL/SCRAM** or mTLS authentication
3. **Implement Kafka ACLs** for authorization
4. **Use NetworkPolicies** for traffic restriction
5. **Store secrets in Kubernetes Secrets** (not ConfigMaps)
6. **Enable audit logging** for compliance

## Best Practices Implemented

1. **Configuration Management**
   - ConfigMap + Init Container pattern for clean separation
   - Dynamic configuration generation at runtime
   - No hardcoded values in container commands

2. **Service Naming**
   - Clear, descriptive service names
   - Consistent naming conventions
   - Separation of concerns (broker vs client services)

3. **Resource Management**
   - Proper resource requests and limits
   - Persistent storage for data durability
   - Automatic lock file cleanup

4. **Operational Excellence**
   - Comprehensive health checks
   - Detailed logging at each stage
   - Graceful shutdown handling

5. **Maintainability**
   - Clear directory structure
   - Separated configuration files
   - Comprehensive documentation

## Contributing

1. Fork the repository
2. Create a feature branch
3. Test changes with both dry-run and real deployment tests
4. Ensure ConfigMaps are updated for configuration changes
5. Update documentation as needed
6. Submit a pull request

## License

Apache License 2.0 - See LICENSE file for details

## References

- [Apache Kafka Documentation](https://kafka.apache.org/documentation/)
- [Kafka KRaft Mode](https://kafka.apache.org/documentation/#kraft)
- [Kubernetes StatefulSets](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/)
- [ConfigMaps and Init Containers](https://kubernetes.io/docs/concepts/configuration/configmap/)
- [Kaskade - Kafka TUI](https://github.com/sauljabin/kaskade)