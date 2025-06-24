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

# Exit immediately if any command fails. This ensures that the script stops if an error occurs.
set -e

# Create the certificates directory if it does not exist.
# Then, change into this directory so all generated files are placed there.
mkdir -p "${CERTS_DIR}"
cd "${CERTS_DIR}"

# --- 1. Generate CA (Certificate Authority) Key and Certificate ---
# This is the root certificate that will sign all other component certificates.
# It is generated once for the entire cluster.
echo ""
echo "--- Step 1: Generating CA Key and Certificate (ca.key, ca.crt) ---"
# Changed ca-key to ca.key and ca-cert to ca.crt
openssl req -new -x509 -keyout ca.key -out ca.crt -days "${VALIDITY}" \
    -passout pass:"${CA_PASSWORD}" \
    -subj "/CN=ConfluentRootCA/OU=Confluent/O=TestOrg/L=MountainView/ST=CA/C=US"

echo "CA generated: ca.key, ca.crt in ./${CERTS_DIR}"

# --- Function to Generate Component Certificates ---
# This function encapsulates the steps to create a keystore and/or truststore
# for a specific Kafka component (e.g., server, client).
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

    # Changed file naming convention to match your updated example
    local keystore_file="${jks_basename}-keystore.jks"
    local truststore_file="${jks_basename}-truststore.jks"
    local cert_request_file="${jks_basename}-cert-request.pem"
    local signed_cert_file="${jks_basename}-cert-signed.pem"

    # Check if the component requires a keystore (i.e., it needs its own key pair and signed certificate).
    # Servers (brokers), producers, and consumers that perform mutual TLS will need a keystore.
    if [[ "${component_type}" == "server" || "${component_type}" == "producer" || "${component_type}" == "consumer" ]]; then
        echo "   Generating key pair for '${component_alias}' in '${keystore_file}'..."
        # Step 1 from user's original list (adapted for generic component).
        keytool -keystore "${keystore_file}" -alias "${component_alias}" -keyalg RSA -validity "${VALIDITY}" -genkey \
            -storepass "${STORE_PASSWORD}" -keypass "${STORE_PASSWORD}" \
            -dname "CN=${component_alias},OU=Confluent,O=TestOrg,L=MountainView,ST=CA,C=US"

        echo "   ${keystore_file} created with key for '${component_alias}'."

        echo "   Generating Certificate Signing Request (CSR) for '${component_alias}'..."
        # Step 5 from user's original list.
        keytool -keystore "${keystore_file}" -alias "${component_alias}" -certreq -file "${cert_request_file}" \
            -storepass "${STORE_PASSWORD}" -keypass "${STORE_PASSWORD}"

        echo "   CSR generated: ${cert_request_file}"

        echo "   CA signing '${component_alias}'s certificate..."
        # Step 6 from user's original list. CA signs the component's CSR.
        # This will also create a `ca.srl` file (because CA is now named ca.crt)
        # Changed -CA ca-cert to -CA ca.crt and -CAkey ca-key to -CAkey ca.key
        openssl x509 -req -CA ca.crt -CAkey ca.key -in "${cert_request_file}" -out "${signed_cert_file}" \
            -days "${VALIDITY}" -CAcreateserial -passin pass:"${CA_PASSWORD}"

        echo "   Signed certificate: ${signed_cert_file}"

        echo "   Importing CA certificate into '${keystore_file}'..."
        # Step 7 from user's original list. The keystore needs to trust the CA chain.
        # Changed -file ca-cert to -file ca.crt
        keytool -keystore "${keystore_file}" -alias CARoot -importcert -file ca.crt \
            -storepass "${STORE_PASSWORD}" -noprompt

        echo "   Importing signed certificate for '${component_alias}' into '${keystore_file}'..."
        # Step 8 from user's original list. Import the newly signed certificate into its keystore.
        keytool -keystore "${keystore_file}" -alias "${component_alias}" -importcert -file "${signed_cert_file}" \
            -storepass "${STORE_PASSWORD}" -keypass "${STORE_PASSWORD}" -noprompt
        echo "   All certificates imported into ${keystore_file}."
    else
        echo "   Component type '${component_type}' does not require a keystore. Skipping keystore steps."
    fi

    echo "   Importing CA certificate into '${truststore_file}'..."
    # Steps 3 & 4 from user's original list. Both client and server truststores need to trust the CA.
    # This enables them to trust certificates issued by this CA.
    # Changed -file ca-cert to -file ca.crt
    keytool -keystore "${truststore_file}" -alias CARoot -importcert -file ca.crt \
        -storepass "${STORE_PASSWORD}" -noprompt

    echo "   CA certificate imported into ${truststore_file}."
    echo "--- Finished processing ${component_type} component: ${jks_basename} ---"
}

# --- Call the function for specific components ---
# You can customize these calls for all components in your cluster.
# For each broker, you might call it with its specific hostname as alias.

# Example: Kafka Server (Broker) Certificate Generation
# The original "localhost" example, still useful for single-node testing.
# generate_component_certs "server" "localhost" "kafka.server"

# KRaft Cluster Components: 3 Controllers, 3 Brokers
echo ""
echo "--- Generating Certificates for KRaft Cluster Components (3 Controllers, 3 Brokers) ---"

# Controller Nodes (KRaft Controllers also act as brokers)
# IMPORTANT: Replace "kafka-controller-X" with your actual controller hostnames or IPs if different.
generate_component_certs "server" "kafka-controller-0" "kafka-controller-0"
generate_component_certs "server" "kafka-controller-1" "kafka-controller-1"
generate_component_certs "server" "kafka-controller-2" "kafka-controller-2"

# Broker Nodes (separate from controllers in this setup, if you have dedicated brokers)
# IMPORTANT: Replace "kafka-broker-X" with your actual broker hostnames or IPs if different.
generate_component_certs "server" "kafka-broker-0" "kafka-broker-0"
generate_component_certs "server" "kafka-broker-1" "kafka-broker-1"
generate_component_certs "server" "kafka-broker-2" "kafka-broker-2"

# Kafka Client (Consumer/Producer) Certificate Generation
# This client will have a truststore to trust the Kafka server.
# If this client also needs to authenticate with a client certificate (mutual TLS),
# change its type to "producer" or "consumer" and provide a unique alias.
generate_component_certs "client" "kafka-connect" "client"

# You can also add calls for Kafka Connect, Schema Registry, Control Center, etc.
# generate_component_certs "server" "connect.example.com" "kafka.connect"

# --- Script End Message ---
echo ""
echo "---------------------------------------------------"
echo "Certificate generation complete."
echo "All generated files are located in the './${CERTS_DIR}' directory."
echo "Remember to configure your Kafka `server.properties` and client configurations"
echo "with the paths to these generated JKS files and their passwords."
echo "---------------------------------------------------"

# --- Cleanup (Optional) ---
# Uncomment the line below if you want to remove the intermediate .pem files
# after the script completes. Keep them if you need to inspect them or for debugging.
rm -f *.pem
