#!/bin/bash
set -e

echo "Starting SCRAM user initialization script..."

echo "Waiting for Kafka broker (${KAFKA_BOOTSTRAP_SERVER}) to be ready for SCRAM user creation..."
until /usr/bin/kafka-broker-api-versions --bootstrap-server "${KAFKA_BOOTSTRAP_SERVER}" --command-config /dev/null --version > /dev/null 2>&1; do
  echo "Kafka broker not ready, retrying in 5 seconds...";
  sleep 5;
done
echo "Kafka broker is ready. Proceeding with SCRAM user creation."

echo "Reading SSL passwords from ${SSL_PASSWORDS_SECRET_PATH}..."
TRUSTSTORE_PASSWORD=$(grep -E '^connect.truststore.password=' "${SSL_PASSWORDS_SECRET_PATH}" | cut -d'=' -f2-)
KEYSTORE_PASSWORD=$(grep -E '^connect.rest.keystore.password=' "${SSL_PASSWORDS_SECRET_PATH}" | cut -d'=' -f2-)

if [ -z "${KEYSTORE_PASSWORD}" ] || [ -z "${TRUSTSTORE_PASSWORD}" ]; then
  echo "ERROR: Required SSL passwords not found or empty in secret file: ${SSL_PASSWORDS_SECRET_PATH}. Exiting."
  exit 1
fi
echo "SSL passwords loaded."

CLIENT_CONFIG_SSL_PATH="/tmp/client-config-ssl.properties"

REQUEST_TIMEOUT_MS="60000"
MAX_BLOCK_MS="60000"

echo "Creating all SCRAM users using SSL superuser (CN=kafka-connect-client)..."

cat > "${CLIENT_CONFIG_SSL_PATH}" <<EOF_SSL
security.protocol=SSL
ssl.truststore.location=/etc/kafka/secrets/truststore.jks
ssl.truststore.password=${TRUSTSTORE_PASSWORD}
ssl.keystore.location=/etc/kafka/secrets/client-keystore.jks
ssl.keystore.password=${KEYSTORE_PASSWORD}
ssl.key.password=${KEYSTORE_PASSWORD}
EOF_SSL

IFS=',' read -ra SCRAM_USERS_ARRAY <<< "${SCRAM_USERS_LIST}"

for user_pass in "${SCRAM_USERS_ARRAY[@]}"; do
  IFS=':' read -r username password <<< "$user_pass"
  echo "Adding SCRAM user: ${username}"

  kafka-configs --bootstrap-server "${KAFKA_BOOTSTRAP_SERVER}" \
    --alter --entity-type users --entity-name "${username}" \
    --add-config "SCRAM-SHA-512=[password=${password}]" \
    --command-config "${CLIENT_CONFIG_SSL_PATH}" || {
      echo "ERROR: Failed to add user ${username}. Make sure SSL cert DN is listed in super.users."
      exit 1
    }

  echo "Successfully added user: ${username}"
done

echo "Verifying SCRAM users by listing topics using first user..."

ADMIN_USER_PASS="${SCRAM_USERS_ARRAY[0]}"
ADMIN_USERNAME=$(echo "${ADMIN_USER_PASS}" | cut -d':' -f1)
ADMIN_PASSWORD=$(echo "${ADMIN_USER_PASS}" | cut -d':' -f2)

CLIENT_CONFIG_SASL_SSL_PATH="/tmp/client-config-sasl-ssl.properties"

cat > "${CLIENT_CONFIG_SASL_SSL_PATH}" <<EOF_SASL
security.protocol=SASL_SSL
ssl.truststore.location=/etc/kafka/secrets/truststore.jks
ssl.truststore.password=${TRUSTSTORE_PASSWORD}
sasl.mechanism=SCRAM-SHA-512
sasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username="${ADMIN_USERNAME}" password="${ADMIN_PASSWORD}";
request.timeout.ms=${REQUEST_TIMEOUT_MS}
max.block.ms=${MAX_BLOCK_MS}
EOF_SASL

kafka-topics --bootstrap-server "${KAFKA_BOOTSTRAP_SERVER}" \
  --list --command-config "${CLIENT_CONFIG_SASL_SSL_PATH}" || {
    echo "ERROR: Verification failed. SCRAM users may not be correctly configured."
    exit 1
  }

echo "SCRAM users verified and script completed successfully."

rm -f "${CLIENT_CONFIG_SSL_PATH}" "${CLIENT_CONFIG_SASL_SSL_PATH}" &>/dev/null
