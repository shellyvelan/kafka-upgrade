#!/bin/bash
set -e

echo "Running Kafka storage format (init)..."

docker volume create kafka-controller-data

docker run --rm \
  -v kafka-controller-data:/var/lib/kafka/data \
  -v "$(pwd)/configs/kraft-controller.properties:/etc/kafka/kraft-server.properties:ro" \
  -v "$(pwd)/certs:/etc/kafka/secrets:ro" \
  confluentinc/cp-kafka:7.9.0 \
  kafka-storage format \
  --config /etc/kafka/kraft-server.properties \
  --cluster-id Rv_mOiSXQMSkcOpL_jZ01Q \
  --add-scram 'SCRAM-SHA-512=[name=admin,password=admin-secret]' \
  --add-scram 'SCRAM-SHA-512=[name=ninja,password=hi]' \
  --add-scram 'SCRAM-SHA-512=[name=akhq-user,password=akhq-password]' \
  --ignore-formatted | tee output.log

sleep 7

echo "Kafka storage formatted successfully."

echo "Deploying Kafka stack to Docker Swarm..."

docker stack deploy -c docker-swarm.yml kafka-stack

echo "Deployment finished."
