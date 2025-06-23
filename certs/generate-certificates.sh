#!/bin/bash
# Exit immediately if a command exits with a non-zero status.
set -e

# Define variables
CA_NAME="MyKafkaCA"
NODE_COMMON_NAME_SUFFIX="kafka.hichat.prod.services.idf"
CERT_PASS="confluent" # Password for keystores/truststores

# Hostnames for your Kafka components (adjust these to match your docker-compose.yml service hostnames)
# IMPORTANT: These CNs and SANs must match the hostnames/IPs Kafka nodes use to refer to each other.
# For Docker Swarm, using the service names as hostnames within the overlay network is common.
CONTROLLER_NODES=("kafka-controller-0" "kafka-controller-1" "kafka-controller-2")
BROKER_NODES=("kafka-broker-0" "kafka-broker-1" "kafka-broker-2")

# --- Ensure 'certs' directory exists ---
mkdir -p certs

echo "--- Generating CA ---"
# Generate CA private key
openssl genrsa -out certs/ca.key 2048

# Generate CA certificate
openssl req -new -x509 -key certs/ca.key -out certs/ca.crt -days 3650 \
  -subj "/CN=${CA_NAME}/OU=Kafka/O=Example/L=HodHasharon/ST=CenterDistrict/C=IL"

echo "--- Generating Node Certificates and Keystores ---"

generate_node_certs() {
  local NODE_NAME=$1
  local UNIQUE_ID=$2 # Not used in your current script, but kept for consistency
  local KEYSTORE_NAME="${NODE_NAME}.jks"
  local TRUSTSTORE_NAME="${NODE_NAME}-truststore.jks"
  local CSR_CONF_FILE="certs/${NODE_NAME}_csr.conf"
  local CERT_EXT_FILE="certs/${NODE_NAME}_cert_ext.conf"

  echo "Generating certs for node: ${NODE_NAME}"

  # Generate node private key
  openssl genrsa -out certs/${NODE_NAME}.key 2048

  # Create a temporary config file for the CSR with SANs
  cat <<EOF > "${CSR_CONF_FILE}"
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
C = IL
ST = CenterDistrict
L = HodHasharon
O = Example
OU = Kafka
CN = ${NODE_NAME}.${NODE_COMMON_NAME_SUFFIX}

[v3_req]
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth, clientAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = ${NODE_NAME}
DNS.2 = ${NODE_NAME}.${NODE_COMMON_NAME_SUFFIX}
DNS.3 = localhost
IP.1 = 127.0.0.1
EOF

  # Generate certificate signing request (CSR) for the node
  openssl req -new -key certs/${NODE_NAME}.key -out certs/${NODE_NAME}.csr \
    -config "${CSR_CONF_FILE}" -extensions v3_req

  # Create a temporary config file for signing the certificate with SANs
  # This file directly defines the extensions for the X509 certificate.
  cat <<EOF > "${CERT_EXT_FILE}"
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth, clientAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = ${NODE_NAME}
DNS.2 = ${NODE_NAME}.${NODE_COMMON_NAME_SUFFIX}
DNS.3 = localhost
IP.1 = 127.0.0.1
EOF

  # Sign the node's certificate with the CA
  # Here, we point to the extension file directly.
  openssl x509 -req -CA certs/ca.crt -CAkey certs/ca.key -in certs/${NODE_NAME}.csr -out certs/${NODE_NAME}.crt -days 3650 -CAcreateserial \
    -extfile "${CERT_EXT_FILE}"

  # Create a PKCS12 keystore for the node
  openssl pkcs12 -export -in certs/${NODE_NAME}.crt -inkey certs/${NODE_NAME}.key -chain -CAfile certs/ca.crt -name ${NODE_NAME} -out certs/${NODE_NAME}.p12 -password pass:${CERT_PASS}

  # Convert PKCS12 to JKS keystore
  keytool -importkeystore -srckeystore certs/${NODE_NAME}.p12 -srcstoretype PKCS12 \
    -destkeystore certs/${KEYSTORE_NAME} -deststoretype JKS \
    -srcstorepass ${CERT_PASS} -deststorepass ${CERT_PASS} \
    -alias ${NODE_NAME} -noprompt

  # Create a JKS truststore for the node (contains CA certificate)
  keytool -import -trustcacerts -noprompt -alias CA -file certs/ca.crt -keystore certs/${TRUSTSTORE_NAME} -storepass ${CERT_PASS}

  # Clean up temporary config files
  rm "${CSR_CONF_FILE}" "${CERT_EXT_FILE}"

  echo "Finished generating certs for node: ${NODE_NAME}"
}

# --- Generate certs for controller nodes ---
for NODE in "${CONTROLLER_NODES[@]}"; do
  generate_node_certs "$NODE"
done

# --- Generate certs for broker nodes ---
for NODE in "${BROKER_NODES[@]}"; do
  generate_node_certs "$NODE"
done

echo "--- Generating Client Truststore ---"
# Create a truststore for clients (contains CA certificate)
keytool -import -trustcacerts -noprompt -alias CA -file certs/ca.crt -keystore certs/client-truststore.jks -storepass ${CERT_PASS}

echo "All certificates and keystores/truststores generated."
