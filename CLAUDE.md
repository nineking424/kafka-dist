# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository contains Kubernetes manifests for deploying Apache Kafka (version 4.0.1-rc0) in both single-node and cluster configurations.

**Key Details:**
- **Namespace**: `kafka`
- **Host Address**: `kafka.nks.stjeong.com`
- **Docker Image**: `apache/kafka:4.0.1-rc0`
- **Deployment Modes**: Single-node and cluster versions

## Common Development Tasks

### Creating Kubernetes Resources

When creating new Kubernetes manifests:
1. Place single-node configurations in a `single/` directory
2. Place cluster configurations in a `cluster/` directory
3. Use the `kafka` namespace for all resources
4. Follow standard Kubernetes YAML formatting

### Applying Manifests

```bash
# Create namespace
kubectl create namespace kafka

# Apply single-node deployment
kubectl apply -f single/ -n kafka

# Apply cluster deployment
kubectl apply -f cluster/ -n kafka
```

### Validation and Testing

```bash
# Check deployment status
kubectl get all -n kafka

# Verify Kafka is running
kubectl logs -n kafka deployment/kafka

# Test Kafka connectivity
kubectl run -it --rm kafka-test --image=apache/kafka:4.0.1-rc0 --restart=Never -n kafka -- kafka-topics.sh --bootstrap-server kafka:9092 --list
```

## Architecture Guidelines

### Resource Structure

The project should maintain clear separation between deployment modes:
- **Single-node**: Simplified deployment for development/testing
- **Cluster**: Production-ready multi-node deployment with proper replication

### Key Components to Include

1. **StatefulSet/Deployment**: Main Kafka broker(s)
2. **Service**: 
   - ClusterIP service for internal communication (port 9092)
   - Ingress or LoadBalancer for external access to `kafka.nks.stjeong.com`
3. **ConfigMap**: Kafka broker configuration
4. **PersistentVolumeClaim**: Data persistence
5. **NetworkPolicy** (optional): Security constraints

### Configuration Considerations

- Use environment variables or ConfigMaps for dynamic configuration
- Ensure proper resource limits and requests are set
- Configure appropriate storage classes for PVCs
- Set up proper liveness and readiness probes

### Kafka 4.0.1 Specific Notes

Apache Kafka 4.0.1-rc0 uses KRaft (Kafka Raft) mode for cluster management, eliminating the need for ZooKeeper.

## Reference Docker Compose Configurations

The Kubernetes manifests should be based on the official Apache Kafka Docker Compose examples:
- **Single-node**: https://github.com/apache/kafka/blob/4.0.1-rc0/docker/examples/docker-compose-files/single-node/plaintext/docker-compose.yml
- **Cluster**: https://github.com/apache/kafka/blob/4.0.1-rc0/docker/examples/docker-compose-files/cluster/isolated/plaintext/docker-compose.yml

### Single-Node Configuration

Key environment variables for single-node deployment:
```yaml
KAFKA_NODE_ID: 1
KAFKA_PROCESS_ROLES: 'broker,controller'
KAFKA_CONTROLLER_QUORUM_VOTERS: '1@kafka-0:29093'
KAFKA_LISTENERS: 'CONTROLLER://:29093,PLAINTEXT_HOST://:9092,PLAINTEXT://:19092'
KAFKA_ADVERTISED_LISTENERS: 'PLAINTEXT_HOST://kafka.nks.stjeong.com:9092,PLAINTEXT://kafka-0:19092'
KAFKA_LISTENER_SECURITY_PROTOCOL_MAP: 'CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT,PLAINTEXT_HOST:PLAINTEXT'
KAFKA_INTER_BROKER_LISTENER_NAME: 'PLAINTEXT'
KAFKA_CONTROLLER_LISTENER_NAMES: 'CONTROLLER'
CLUSTER_ID: '4L6g3nShT-eMCtK--X86sw'
KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 1
KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR: 1
KAFKA_LOG_DIRS: '/var/lib/kafka/data'
```

### Cluster Configuration

For cluster deployment, use:
- **3 Controller nodes** (Node IDs: 1-3)
- **3 Kafka broker nodes** (Node IDs: 4-6)

Key environment variables for cluster deployment:
```yaml
# Controllers (1-3)
KAFKA_NODE_ID: <1|2|3>
KAFKA_PROCESS_ROLES: 'controller'
KAFKA_CONTROLLER_QUORUM_VOTERS: '1@controller-1:29093,2@controller-2:29093,3@controller-3:29093'

# Brokers (4-6)
KAFKA_NODE_ID: <4|5|6>
KAFKA_PROCESS_ROLES: 'broker'
KAFKA_CONTROLLER_QUORUM_VOTERS: '1@controller-1:29093,2@controller-2:29093,3@controller-3:29093'
```

### Important Configuration Notes

1. **KRaft Mode**: All deployments use KRaft mode (no ZooKeeper)
2. **Cluster ID**: Use the same cluster ID across all nodes: `4L6g3nShT-eMCtK--X86sw`
3. **Port Mapping**:
   - Controller port: 29093
   - Inter-broker communication: 19092
   - Client connections: 9092
4. **Storage**: Mount persistent volumes to `/var/lib/kafka/data` (instead of `/tmp/kraft-combined-logs`)
5. **Replication**: Set replication factors to 3 for cluster deployments