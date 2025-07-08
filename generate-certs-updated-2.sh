#!/bin/bash
VALIDITY=${1:-3650} 
CA_PASSWORD=${2:-"confluent"}
STORE_PASSWORD=${3:-"confluent"}
CERTS_DIR="certs" 

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

# --- 2. Create a single truststore and import CA certificate ---
echo ""
echo "--- Step 2: Creating single truststore.jks with CA certificate ---"
keytool -keystore truststore.jks -alias CARoot -importcert -file ca.crt \
    -storepass "${STORE_PASSWORD}" -noprompt
echo "Single truststore created: truststore.jks"

# --- Function to Generate Component Certificates ---
# Arguments:
#   $1: Component type (e.g., "server", "client", "producer", "consumer").
#       This determines if a keystore is needed (i.e., it needs its own key pair and signed certificate).
#   $2: Component alias/Common Name (CN) for the certificate (e.g., "localhost", "broker1.example.com", "myclient").
#       This should typically be the hostname for servers or a unique identifier for clients.
#   $3: Base name for the JKS files (e.g., "kafka.server", "kafka.client").
#       This helps in naming the output files (e.g., kafka.server.keystore.jks).
#   $4: Optional: Comma-separated list of Subject Alternative Names (SANs) - e.g., "DNS:localhost,IP:127.0.0.1,DNS:kafka-connect"
generate_component_certs() {
    local component_type="$1"
    local component_alias="$2"
    local jks_basename="$3"
    local san_list="$4" # New argument for SANs

    echo ""
    echo "--- Processing ${component_type} component: ${jks_basename} (alias: ${component_alias}) ---"

    local keystore_file="${jks_basename}-keystore.jks"
    local cert_request_file="${jks_basename}-cert-request.csr"
    local signed_cert_file="${jks_basename}-cert-signed.pem"
    local openssl_ext_file="${jks_basename}-openssl-ext.cnf"

    # Check if the component requires a keystore (i.e., it needs its own key pair and signed certificate).
    if [[ "${component_type}" == "server" || "${component_type}" == "producer" || "${component_type}" == "consumer" || "${component_type}" == "client" ]]; then
        echo "   Generating key pair for '${component_alias}' in '${keystore_file}'..."
        keytool -keystore "${keystore_file}" -alias "${component_alias}" -keyalg RSA -validity "${VALIDITY}" -genkey \
            -storepass "${STORE_PASSWORD}" -keypass "${STORE_PASSWORD}" \
            -dname "CN=${component_alias},OU=Confluent,O=TestOrg,L=MountainView,ST=CA,C=US" \
            -ext san="${san_list}"

        echo "   ${keystore_file} created with key for '${component_alias}'."

        echo "   Generating Certificate Signing Request (CSR) for '${component_alias}'..."
        keytool -keystore "${keystore_file}" -alias "${component_alias}" -certreq -file "${cert_request_file}" \
            -storepass "${STORE_PASSWORD}" -keypass "${STORE_PASSWORD}"

        echo "   CSR generated: ${cert_request_file}"

        echo "   Creating OpenSSL extensions config for SANs: ${openssl_ext_file}"
        cat > "${openssl_ext_file}" <<-EOF
[v3_ext]
subjectAltName = ${san_list}
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth, clientAuth
EOF

        echo "   CA signing '${component_alias}'s certificate with SANs..."
        openssl x509 -req -CA ca.crt -CAkey ca.key -in "${cert_request_file}" -out "${signed_cert_file}" \
            -days "${VALIDITY}" -CAcreateserial -passin pass:"${CA_PASSWORD}" \
            -extfile "${openssl_ext_file}" -extensions v3_ext

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

    echo "--- Finished processing ${component_type} component: ${jks_basename} ---"

    # Clean up the temporary files
    rm -f "${openssl_ext_file}" "${cert_request_file}" "${signed_cert_file}"
}

echo ""
echo "--- Generating Certificates for KRaft Cluster Components (3 Controllers, 3 Brokers) ---"

generate_component_certs "server" "kafka-controller-0" "kafka-controller-0" "DNS:kafka-controller-0" 
generate_component_certs "server" "kafka-controller-1" "kafka-controller-1" "DNS:kafka-controller-1" 
generate_component_certs "server" "kafka-controller-2" "kafka-controller-2" "DNS:kafka-controller-2" 

generate_component_certs "server" "kafka-broker-0" "kafka-broker-0" "DNS:kafka-broker-0" 
generate_component_certs "server" "kafka-broker-1" "kafka-broker-1" "DNS:kafka-broker-1" 
generate_component_certs "server" "kafka-broker-2" "kafka-broker-2" "DNS:kafka-broker-2" 

generate_component_certs "consumer" "kafka-connect-rest" "kafka-connect-rest" "DNS:localhost,IP:127.0.0.1,DNS:kafka-connect"

# generate_component_certs "client" "kafka-connect-client" "client" "DNS:kafka-connect,DNS:localhost"

echo ""
echo "---------------------------------------------------"
echo "Certificate generation complete."
echo "All generated files are located in the './${CERTS_DIR}' directory."
echo "Single truststore file: truststore.jks"
echo "Remember to configure your Kafka and client configurations"
echo "to use the same truststore.jks with password '${STORE_PASSWORD}'."
echo "---------------------------------------------------"

rm -f *.pem
