# Kafka Kubernetes Deployment Makefile

.PHONY: help test quick-test validate deploy-single deploy-cluster clean namespace

# Default target
help:
	@echo "Kafka Kubernetes Deployment Commands:"
	@echo ""
	@echo "Testing Commands:"
	@echo "  make test                - Run dry-run validation tests (safe)"
	@echo "  make test-real           - Run REAL deployment tests (creates resources)"
	@echo "  make test-real-no-cleanup- Run REAL tests but keep resources after"
	@echo "  make quick-test          - Run quick validation tests"
	@echo "  make validate            - Validate all YAML files"
	@echo ""
	@echo "Deployment Commands:"
	@echo "  make namespace           - Create kafka namespace"
	@echo "  make deploy-single       - Deploy single-node Kafka"
	@echo "  make deploy-cluster      - Deploy Kafka cluster"
	@echo ""
	@echo "Cleanup Commands:"
	@echo "  make clean-single        - Remove single-node deployment"
	@echo "  make clean-cluster       - Remove cluster deployment"
	@echo "  make clean-all           - Remove all Kafka resources"
	@echo ""
	@echo "Management Commands:"
	@echo "  make status              - Show Kafka resources"
	@echo "  make logs-single         - View single-node logs"
	@echo "  make logs-broker         - View broker logs"
	@echo "  make logs-controller     - View controller logs"
	@echo "  make port-forward-single - Forward port 9092 (single-node)"
	@echo "  make port-forward-cluster- Forward port 9092 (cluster)"

# Testing targets
test:
	@echo "Running comprehensive tests..."
	@./test/test-deployment.sh

test-real:
	@echo "Running REAL deployment tests (creates actual resources)..."
	@./test/test-deployment-real.sh

test-real-no-cleanup:
	@echo "Running REAL deployment tests (keeps resources after test)..."
	@./test/test-deployment-real.sh --no-cleanup

quick-test:
	@echo "Running quick tests..."
	@./test/quick-test.sh

validate:
	@echo "Validating YAML syntax..."
	@find . -name "*.yaml" -type f -exec echo "Checking {}" \; -exec kubectl apply --dry-run=client -f {} \; | grep -E "(Checking|created)"

# Deployment targets
namespace:
	kubectl apply -f 00-namespace.yaml

deploy-single: namespace
	@echo "Deploying single-node Kafka..."
	kubectl apply -f single/
	@echo "Deployment complete. Check status with: kubectl get all -n kafka"

deploy-cluster: namespace
	@echo "Deploying Kafka cluster..."
	kubectl apply -f cluster/
	@echo "Deployment complete. Check status with: kubectl get all -n kafka"

# Cleanup targets
clean-single:
	@echo "Removing single-node deployment..."
	kubectl delete -f single/ --ignore-not-found=true

clean-cluster:
	@echo "Removing cluster deployment..."
	kubectl delete -f cluster/ --ignore-not-found=true

clean-all:
	@echo "Removing all Kafka resources..."
	kubectl delete -f single/ --ignore-not-found=true
	kubectl delete -f cluster/ --ignore-not-found=true
	kubectl delete -f 00-namespace.yaml --ignore-not-found=true

# Status and debugging
status:
	@echo "Kafka namespace resources:"
	kubectl get all -n kafka

logs-single:
	kubectl logs -n kafka kafka-0 --tail=50

logs-broker:
	kubectl logs -n kafka kafka-broker-0 --tail=50

logs-controller:
	kubectl logs -n kafka kafka-controller-0 --tail=50

# Port forwarding for testing
port-forward-single:
	@echo "Port forwarding kafka-0 to localhost:9092..."
	kubectl port-forward -n kafka kafka-0 9092:9092

port-forward-cluster:
	@echo "Port forwarding kafka-broker-0 to localhost:9092..."
	kubectl port-forward -n kafka kafka-broker-0 9092:9092