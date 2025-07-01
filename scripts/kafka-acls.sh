#!/bin/bash

# Define variables
COMMAND_CONFIG="/etc/kafka/kafka-acls-admin-cli.properties" # Path *inside* the container
BOOTSTRAP_SERVER="kafka-broker-0:9092" # Internal Docker network hostname (broker listens for admin client requests)
USERNAME="ninja"

# The container to execute the commands in
KAFKA_CONTAINER="kafka-controller-0" 

echo "Grant Cluster-wide permissions for topic management"
docker exec "$KAFKA_CONTAINER" kafka-acls --bootstrap-server "$BOOTSTRAP_SERVER" \
  --command-config "$COMMAND_CONFIG" \
  --add --allow-principal "User:$USERNAME" \
  --operation Create --operation Alter --operation Describe --operation ClusterAction \
  --cluster

echo "---------------------------------------------------"
echo "Grant permissions on Kafka Connect's internal topics"

echo "connect-configs topic"
docker exec "$KAFKA_CONTAINER" kafka-acls --bootstrap-server "$BOOTSTRAP_SERVER" \
  --command-config "$COMMAND_CONFIG" \
  --add --allow-principal "User:$USERNAME" \
  --operation Read --operation Write --operation Describe \
  --topic connect-configs

echo "connect-offsets topic"
docker exec "$KAFKA_CONTAINER" kafka-acls --bootstrap-server "$BOOTSTRAP_SERVER" \
  --command-config "$COMMAND_CONFIG" \
  --add --allow-principal "User:$USERNAME" \
  --operation Read --operation Write --operation Describe \
  --topic connect-offsets

echo "connect-status topic"
docker exec "$KAFKA_CONTAINER" kafka-acls --bootstrap-server "$BOOTSTRAP_SERVER" \
  --command-config "$COMMAND_CONFIG" \
  --add --allow-principal "User:$USERNAME" \
  --operation Read --operation Write --operation Describe \
  --topic connect-status

echo "---------------------------------------------------"
echo "Grant permissions for Consumer Groups (for offsets and status topics)"
docker exec "$KAFKA_CONTAINER" kafka-acls --bootstrap-server "$BOOTSTRAP_SERVER" \
  --command-config "$COMMAND_CONFIG" \
  --add --allow-principal "User:$USERNAME" \
  --operation Read \
  --group Rv_mOiSXQMSkcOpL_jZ01Q

echo "---------------------------------------------------"
echo "Finished acls script :)"