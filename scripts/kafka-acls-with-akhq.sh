#!/bin/bash

# Define variables
COMMAND_CONFIG="/etc/kafka/kafka-acls-admin-cli.properties" # Path *inside* the container
BOOTSTRAP_SERVER="kafka-broker-0:9092" # Internal Docker network hostname (broker listens for admin client requests)
USERNAME="ninja" # Existing user for Kafka Connect and other admin tasks

# AKHQ Specific Variables
AKHQ_USERNAME="akhq_client_user" # The username AKHQ will use to connect to Kafka
AKHQ_CONSUMER_GROUP="Rv_mOiSXQMSkcOpL_jZ01Q"

# The container to execute the commands in
KAFKA_CONTAINER="kafka-controller-0"

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
echo "Grant AKHQ specific permissions (for $AKHQ_USERNAME)"

echo "Grant Cluster-wide Describe permission for AKHQ"
docker exec "$KAFKA_CONTAINER" kafka-acls --bootstrap-server "$BOOTSTRAP_SERVER" \
  --command-config "$COMMAND_CONFIG" \
  --add --allow-principal "User:$AKHQ_USERNAME" \
  --operation Describe --cluster

echo "Grant Read and Describe on all topics for AKHQ"
docker exec "$KAFKA_CONTAINER" kafka-acls --bootstrap-server "$BOOTSTRAP_SERVER" \
  --command-config "$COMMAND_CONFIG" \
  --add --allow-principal "User:$AKHQ_USERNAME" \
  --operation Read --operation Describe \
  --topic '*'

echo "Grant Read and Describe on all consumer groups for AKHQ"
# AKHQ needs to read all consumer groups to list them
docker exec "$KAFKA_CONTAINER" kafka-acls --bootstrap-server "$BOOTSTRAP_SERVER" \
  --command-config "$COMMAND_CONFIG" \
  --add --allow-principal "User:$AKHQ_USERNAME" \
  --operation Read --operation Describe \
  --group '*'

docker exec "$KAFKA_CONTAINER" kafka-acls --bootstrap-server "$BOOTSTRAP_SERVER" \
  --command-config "$COMMAND_CONFIG" \
  --add --allow-principal "User:$AKHQ_USERNAME" \
  --operation DescribeConfigs --cluster

docker exec "$KAFKA_CONTAINER" kafka-acls --bootstrap-server "$BOOTSTRAP_SERVER" \
  --command-config "$COMMAND_CONFIG" \
  --add --allow-principal "User:$AKHQ_USERNAME" \
  --operation Read --operation Describe \
  --topic '__*'

docker exec "$KAFKA_CONTAINER" kafka-acls --bootstrap-server "$BOOTSTRAP_SERVER" \
  --command-config "$COMMAND_CONFIG" \
  --add --allow-principal "User:$AKHQ_USERNAME" \
  --operation Read --operation Describe \
  --topic 'connect-*'
# If AKHQ uses its own consumer group for internal operations (e.g., offset management for the UI itself)
# You might need to grant it write access to that specific grou

echo "---------------------------------------------------"
echo "Finished acls script :)"