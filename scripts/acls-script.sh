#!/bin/bash

COMMAND_CONFIG="/etc/kafka/secrets/client.properties"
BOOTSTRAP_SERVER="kafka-broker-0:9092"

CONNECT_CN="CN=kafka-connect,OU=Confluent,O=TestOrg,L=MountainView,ST=CA,C=US"
AKHQ_CN="CN=kafka-akhq,OU=Confluent,O=TestOrg,L=MountainView,ST=CA,C=US"
AKHQ_CONSUMER_GROUP="Rv_mOiSXQMSkcOpL_jZ01Q"

STACK_NAME=$(docker stack ls --format "{{.Name}}" | grep kafka) # has to have kafka in stack name
if [ -z "$STACK_NAME" ]; then
  echo "❌ Could not determine Kafka stack name."
  exit 1
fi

KAFKA_CONTAINER=$(docker ps --filter "name=${STACK_NAME}_kafka-controller-0" --format "{{.ID}}")
if [ -z "$KAFKA_CONTAINER" ]; then
  echo "❌ Kafka controller container not found for stack: $STACK_NAME"
  exit 1
fi


echo "---------------------------------------------------"
echo "Grant Cluster-wide permissions for topic management (for connect-cn)"
docker exec "$KAFKA_CONTAINER" kafka-acls \
  --bootstrap-server "$BOOTSTRAP_SERVER" \
  --command-config "$COMMAND_CONFIG" \
  --add \
  --allow-principal "User:$CONNECT_CN" \
  --operation Create \
  --operation Alter \
  --operation Describe \
  --operation ClusterAction \
  --cluster

echo "---------------------------------------------------"
echo "Grant permissions on Kafka Connect's internal topics (for connect-cn)"

for topic in connect-configs connect-offsets connect-status; do
  echo "$topic topic"
  docker exec "$KAFKA_CONTAINER" kafka-acls \
    --bootstrap-server "$BOOTSTRAP_SERVER" \
    --command-config "$COMMAND_CONFIG" \
    --add \
    --allow-principal "User:$CONNECT_CN" \
    --operation Read \
    --operation Write \
    --operation Describe \
    --topic "$topic"
done

echo "---------------------------------------------------"
echo "Grant permissions for Consumer Groups (for connect-cn)"
docker exec "$KAFKA_CONTAINER" kafka-acls \
  --bootstrap-server "$BOOTSTRAP_SERVER" \
  --command-config "$COMMAND_CONFIG" \
  --add \
  --allow-principal "User:$CONNECT_CN" \
  --operation Read \
  --group "$AKHQ_CONSUMER_GROUP"

echo "---------------------------------------------------"
echo "Grant MongoDB Connector topic access for connect-cn"
docker exec "$KAFKA_CONTAINER" kafka-acls \
  --bootstrap-server "$BOOTSTRAP_SERVER" \
  --command-config "$COMMAND_CONFIG" \
  --add \
  --allow-principal "User:$CONNECT_CN" \
  --operation Write \
  --operation Describe \
  --topic "mongo-.testdb.testcollection"

echo "---------------------------------------------------"
echo "Grant AKHQ specific permissions (for akhq-cn)"

echo "Granting Cluster-wide Describe and DescribeConfigs permission"
docker exec "$KAFKA_CONTAINER" kafka-acls \
  --bootstrap-server "$BOOTSTRAP_SERVER" \
  --command-config "$COMMAND_CONFIG" \
  --add \
  --allow-principal "User:$AKHQ_CN" \
  --operation Describe \
  --cluster

docker exec "$KAFKA_CONTAINER" kafka-acls \
  --bootstrap-server "$BOOTSTRAP_SERVER" \
  --command-config "$COMMAND_CONFIG" \
  --add \
  --allow-principal "User:$AKHQ_CN" \
  --operation DescribeConfigs \
  --cluster

echo "Granting ACL Describe permission"
docker exec "$KAFKA_CONTAINER" kafka-acls \
  --bootstrap-server "$BOOTSTRAP_SERVER" \
  --command-config "$COMMAND_CONFIG" \
  --add \
  --allow-principal "User:$AKHQ_CN" \
  --operation Describe \
  --cluster

echo "---------------------------------------------------"
echo "Granting Read, Describe, and DescribeConfigs on all topics using wildcard prefix"

docker exec "$KAFKA_CONTAINER" kafka-acls \
  --bootstrap-server "$BOOTSTRAP_SERVER" \
  --command-config "$COMMAND_CONFIG" \
  --add \
  --allow-principal "User:$AKHQ_CN" \
  --operation Read \
  --operation Describe \
  --operation DescribeConfigs \
  --resource-pattern-type prefixed \
  --topic '*'


echo "Granting access to internal topics (e.g. __consumer_offsets)"
docker exec "$KAFKA_CONTAINER" kafka-acls \
  --bootstrap-server "$BOOTSTRAP_SERVER" \
  --command-config "$COMMAND_CONFIG" \
  --add \
  --allow-principal "User:$AKHQ_CN" \
  --operation Read \
  --operation Describe \
  --topic '__*'

echo "Granting access to Kafka Connect internal topics"
docker exec "$KAFKA_CONTAINER" kafka-acls \
  --bootstrap-server "$BOOTSTRAP_SERVER" \
  --command-config "$COMMAND_CONFIG" \
  --add \
  --allow-principal "User:$AKHQ_CN" \
  --operation Read \
  --operation Describe \
  --topic 'connect-*'

echo "---------------------------------------------------"
echo "Granting Read and Describe on all consumer groups (for akhq-cn)"
docker exec "$KAFKA_CONTAINER" kafka-acls \
  --bootstrap-server "$BOOTSTRAP_SERVER" \
  --command-config "$COMMAND_CONFIG" \
  --add \
  --allow-principal "User:$AKHQ_CN" \
  --operation Read \
  --operation Describe \
  --group '*'

echo "---------------------------------------------------"
echo "✅ Finished ACLs setup script"
