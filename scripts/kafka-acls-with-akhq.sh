#!/bin/bash

# Define variables
COMMAND_CONFIG="/etc/kafka/kafka-acls-admin-cli.properties" # Path *inside* the container
BOOTSTRAP_SERVER="kafka-broker-0:9092" # Internal Docker network hostname (broker listens for admin client requests)
USERNAME="ninja" # Existing user for Kafka Connect and other admin tasks

# AKHQ Specific Variables
AKHQ_USERNAME="akhq-user" # The username AKHQ will use to connect to Kafka
AKHQ_CONSUMER_GROUP="Rv_mOiSXQMSkcOpL_jZ01Q"

# The container to execute the commands in
KAFKA_CONTAINER="b789b33c4f29"

echo "---------------------------------------------------"
echo "Grant Cluster-wide permissions for topic management (for $USERNAME)"
docker exec "$KAFKA_CONTAINER" kafka-acls --bootstrap-server "$BOOTSTRAP_SERVER" \
  --command-config "$COMMAND_CONFIG" \
  --add --allow-principal "User:$USERNAME" \
  --operation Create --operation Alter --operation Describe --operation ClusterAction \
  --cluster

echo "---------------------------------------------------"
echo "Grant permissions on Kafka Connect's internal topics (for $USERNAME)"

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
echo "Grant permissions for Consumer Groups (for offsets and status topics) (for $USERNAME)"
docker exec "$KAFKA_CONTAINER" kafka-acls --bootstrap-server "$BOOTSTRAP_SERVER" \
  --command-config "$COMMAND_CONFIG" \
  --add --allow-principal "User:$USERNAME" \
  --operation Read --group Rv_mOiSXQMSkcOpL_jZ01Q # Assuming this is your Connect group

echo "---------------------------------------------------"
echo "Grant MongoDB Connector topic access for $USERNAME"

docker exec "$KAFKA_CONTAINER" kafka-acls --bootstrap-server "$BOOTSTRAP_SERVER" \
  --command-config "$COMMAND_CONFIG" \
  --add --allow-principal "User:$USERNAME" \
  --operation Write --operation Describe \
  --topic "mongo-.testdb.testcollection"


echo "---------------------------------------------------"
echo "Grant AKHQ specific permissions (for $AKHQ_USERNAME)"

echo "Granting Cluster-wide Describe permission"
docker exec "$KAFKA_CONTAINER" kafka-acls --bootstrap-server "$BOOTSTRAP_SERVER" \
  --command-config "$COMMAND_CONFIG" \
  --add --allow-principal "User:$AKHQ_USERNAME" \
  --operation Describe --cluster

echo "Granting Cluster-wide DescribeConfigs permission"
docker exec "$KAFKA_CONTAINER" kafka-acls --bootstrap-server "$BOOTSTRAP_SERVER" \
  --command-config "$COMMAND_CONFIG" \
  --add --allow-principal "User:$AKHQ_USERNAME" \
  --operation DescribeConfigs --cluster

echo "Granting ACLS describe permission"
docker exec kafka-controller-0 kafka-acls \
  --bootstrap-server kafka-broker-0:9092 \
  --command-config /etc/kafka/kafka-acls-admin-cli.properties \
  --add --allow-principal "User:akhq-user" \
  --operation Describe \
  --cluster
  
# === Topic permissions ===
echo "Granting Read, Describe, DescribeConfigs on all topics"
docker exec "$KAFKA_CONTAINER" kafka-acls --bootstrap-server "$BOOTSTRAP_SERVER" \
  --command-config "$COMMAND_CONFIG" \
  --add --allow-principal "User:$AKHQ_USERNAME" \
  --operation Read \
  --operation Describe \
  --operation DescribeConfigs \
  --topic '*'

# Optional: Internal topics like __consumer_offsets or __transaction_state
echo "Granting access to internal topics"
docker exec "$KAFKA_CONTAINER" kafka-acls --bootstrap-server "$BOOTSTRAP_SERVER" \
  --command-config "$COMMAND_CONFIG" \
  --add --allow-principal "User:$AKHQ_USERNAME" \
  --operation Read \
  --operation Describe \
  --topic '__*'

echo "Granting access to Kafka Connect topics (if used)"
docker exec "$KAFKA_CONTAINER" kafka-acls --bootstrap-server "$BOOTSTRAP_SERVER" \
  --command-config "$COMMAND_CONFIG" \
  --add --allow-principal "User:$AKHQ_USERNAME" \
  --operation Read \
  --operation Describe \
  --topic 'connect-*'

# === Consumer group permissions ===
echo "Granting Read and Describe on all consumer groups"
docker exec "$KAFKA_CONTAINER" kafka-acls --bootstrap-server "$BOOTSTRAP_SERVER" \
  --command-config "$COMMAND_CONFIG" \
  --add --allow-principal "User:$AKHQ_USERNAME" \
  --operation Read \
  --operation Describe \
  --group '*'


echo "---------------------------------------------------"
echo "Finished acls script :)"