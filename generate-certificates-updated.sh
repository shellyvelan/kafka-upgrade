#!/bin/bash

# This script automates the generation of SSL certificates for Kafka components
# using keytool and openssl, based on the steps provided.

# --- Configuration ---
# Default validity period for certificates in days. Can be overridden by the first argument.
VALIDITY=${1:-3650} # Changed to 3650 days as per your request
# Default password for the CA key. Can be overridden by the second argument.
CA_PASSWORD=${2:-"confluent"}
# Default password for all generated JKS keystores and truststores. Can be overridden by the third argument.
STORE_PASSWORD=${3:-"confluent"}

# Directory where all generated certificates and keys will be stored.
CERTS_DIR="certs" # Changed to "certs" as per your request

# --- Script Start Message ---
echo "---------------------------------------------------"
echo "Starting Kafka Cluster Certificate Generation Script"
echo "Validity for certificates: ${VALIDITY} days"
echo "CA Password: (hidden for security)"
echo "Keystore/Truststore Password: (hidden for security)"
echo "Certificates and keys will be saved in: ./${CERTS_DIR}"
echo "---------------------------------------------------"

set -e

mkdir -p "${CERTS_DIR}"
cd "${CERTS_DIR}"

# --- 1. Generate CA (Certificate Authority) Key and Certificate ---
echo ""
echo "--- Step 1: Generating CA Key and Certificate (ca.key, ca.crt) ---"
openssl req -new -x509 -keyout ca.key -out ca.crt -days "${VALIDITY}" \
    -passout pass:"${CA_PASSWORD}" \
    -subj "/CN=ConfluentRootCA/OU=Confluent/O=TestOrg/L=MountainView/ST=CA/C=US"

echo "CA generated: ca.key, ca.crt in ./${CERTS_DIR}"

# --- Function to Generate Component Certificates ---
# Arguments:
#   $1: Component type (e.g., "server", "client", "producer", "consumer").
#       This determines if a keystore is needed (e.g., server, producer, consumer need keys).
#   $2: Component alias/Common Name (CN) for the certificate (e.g., "localhost", "broker1.example.com", "myclient").
#       This should typically be the hostname for servers or a unique identifier for clients.
#   $3: Base name for the JKS files (e.g., "kafka.server", "kafka.client").
#       This helps in naming the output files (e.g., kafka.server.keystore.jks).
generate_component_certs() {
    local component_type="$1"
    local component_alias="$2"
    local jks_basename="$3"

    echo ""
    echo "--- Processing ${component_type} component: ${jks_basename} (alias: ${component_alias}) ---"

    local keystore_file="${jks_basename}-keystore.jks"
    local truststore_file="${jks_basename}-truststore.jks"
    local cert_request_file="${jks_basename}-cert-request.pem"
    local signed_cert_file="${jks_basename}-cert-signed.pem"

    # Check if the component requires a keystore (i.e., it needs its own key pair and signed certificate).
    # Servers (brokers), producers, and consumers that perform mutual TLS will need a keystore.
    if [[ "${component_type}" == "server" || "${component_type}" == "producer" || "${component_type}" == "consumer" ]]; then
        echo "   Generating key pair for '${component_alias}' in '${keystore_file}'..."
        keytool -keystore "${keystore_file}" -alias "${component_alias}" -keyalg RSA -validity "${VALIDITY}" -genkey \
            -storepass "${STORE_PASSWORD}" -keypass "${STORE_PASSWORD}" \
            -dname "CN=${component_alias},OU=Confluent,O=TestOrg,L=MountainView,ST=CA,C=US"

        echo "   ${keystore_file} created with key for '${component_alias}'."

        echo "   Generating Certificate Signing Request (CSR) for '${component_alias}'..."
        keytool -keystore "${keystore_file}" -alias "${component_alias}" -certreq -file "${cert_request_file}" \
            -storepass "${STORE_PASSWORD}" -keypass "${STORE_PASSWORD}"

        echo "   CSR generated: ${cert_request_file}"

        echo "   CA signing '${component_alias}'s certificate..."
        
        openssl x509 -req -CA ca.crt -CAkey ca.key -in "${cert_request_file}" -out "${signed_cert_file}" \
            -days "${VALIDITY}" -CAcreateserial -passin pass:"${CA_PASSWORD}"

        echo "   Signed certificate: ${signed_cert_file}"

        echo "   Importing CA certificate into '${keystore_file}'..."
 
        keytool -keystore "${keystore_file}" -alias CARoot -importcert -file ca.crt \
            -storepass "${STORE_PASSWORD}" -noprompt

        echo "   Importing signed certificate for '${component_alias}' into '${keystore_file}'..."
       
        keytool -keystore "${keystore_file}" -alias "${component_alias}" -importcert -file "${signed_cert_file}" \
            -storepass "${STORE_PASSWORD}" -keypass "${STORE_PASSWORD}" -noprompt
        echo "   All certificates imported into ${keystore_file}."
    else
        echo "   Component type '${component_type}' does not require a keystore. Skipping keystore steps."
    fi

    echo "   Importing CA certificate into '${truststore_file}'..."
    
    keytool -keystore "${truststore_file}" -alias CARoot -importcert -file ca.crt \
        -storepass "${STORE_PASSWORD}" -noprompt

    echo "   CA certificate imported into ${truststore_file}."
    echo "--- Finished processing ${component_type} component: ${jks_basename} ---"
}

echo ""
echo "--- Generating Certificates for KRaft Cluster Components (3 Controllers, 3 Brokers) ---"

generate_component_certs "server" "kafka-controller-0" "kafka-controller-0"
generate_component_certs "server" "kafka-controller-1" "kafka-controller-1"
generate_component_certs "server" "kafka-controller-2" "kafka-controller-2"

generate_component_certs "server" "kafka-broker-0" "kafka-broker-0"
generate_component_certs "server" "kafka-broker-1" "kafka-broker-1"
generate_component_certs "server" "kafka-broker-2" "kafka-broker-2"

generate_component_certs "client" "kafka-connect" "client"
generate_component_certs "consumer" "kafka-admin-client" "kafka-admin-client"

# can also add calls for Kafka Connect, Schema Registry, Control Center, etc.
# generate_component_certs "server" "connect.example.com" "kafka.connect"

# --- Script End Message ---
echo ""
echo "---------------------------------------------------"
echo "Certificate generation complete."
echo "All generated files are located in the './${CERTS_DIR}' directory."
echo "Remember to configure your Kafka `server.properties` and client configurations"
echo "with the paths to these generated JKS files and their passwords."
echo "---------------------------------------------------"

rm -f *.pem
