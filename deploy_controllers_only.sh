#!/bin/bash
# Exit immediately if a command exits with a non-zero status.
set -e

COMPOSE_FILE="docker-compose.yml"
# Use a unique temporary file name to avoid conflicts
OUTPUT_FILE="/tmp/filtered-compose-controllers-$(date +%s).yml" 

# --- !!! CRITICAL WARNING: FRAGILE SCRIPT FOR YAML FILTERING WITHOUT `yq` !!! ---
# --- This script uses `awk` to filter YAML, which is EXTREMELY BRITTLE. ---
# --- It relies heavily on your docker-compose.yml having: ---
# ---   - EXACTLY 2-space indentation for top-level keys and service names. ---
# ---   - EXACTLY 4-space indentation for properties directly under a service. ---
# ---   - The sections appear in the order: version, networks, volumes, services. ---
# ---   - Service names for controllers follow the pattern 'kafka-controller-X'. ---
# --- ANY deviation in formatting or order will likely cause errors ---
# --- (e.g., "services must be a mapping", "networks must be a mapping"). ---
# --- For robust YAML manipulation, `yq` (Go version) is the ONLY reliable tool. ---
# --- Please reconsider troubleshooting your `yq` installation. ---

echo "--- Attempting to filter docker-compose.yml without yq (HIGHLY FRAGILE) ---"
echo "--- Deploying only 'kafka-controller-X' services ---"

# Awk script to filter the YAML content
awk '
BEGIN {
    in_service_block = 0;           # Flag: Are we inside the "services:" block?
    in_desired_service = 0;         # Flag: Are we inside a "kafka-controller-X" service?
    current_indent_level = 0;       # Current indentation level of the line
    service_indent = 2;             # Expected indentation for service names (e.g., "  service_name:")
}

{
    # Calculate current line indentation (number of leading spaces)
    current_indent_level = 0;
    while (substr($0, current_indent_level + 1, 1) == " ") {
        current_indent_level++;
    }

    # --- Section: Top-level keys (version, networks, volumes) ---
    # These should always be printed, and reset service block flags if encountered
    if (current_indent_level == 0) {
        if ($0 ~ /^version:/ || $0 ~ /^networks:/ || $0 ~ /^volumes:/) {
            print;                      # Print the top-level header
            in_service_block = 0;       # Ensure we are not considered inside the services block
            in_desired_service = 0;     # Reset service flag
            next;                       # Move to the next line
        }
    }

    # --- Section: "services:" header ---
    if ($0 ~ /^services:/) {
        print;                      # Print the "services:" header
        in_service_block = 1;       # We are now inside the services block
        next;                       # Move to the next line
    }

    # --- Section: Processing inside the "services:" block ---
    if (in_service_block) {
        # Check for start of a new service definition (e.g., "  service-name:")
        # This regex matches lines like "  my-service:" and avoids lines like "    key: value"
        if (current_indent_level == service_indent && substr($0, service_indent + 1, 1) != " ") {
            # Extract the service name (e.g., "kafka-controller-0")
            service_header = substr($0, service_indent + 1);
            # This extracts the name before the first colon and before any further content on the same line
            current_service_name = substr(service_header, 1, index(service_header, ":") - 1);

            # Decide if this is a desired service (kafka-controller-X)
            if (current_service_name ~ /^kafka-controller-[0-9]+$/) {
                in_desired_service = 1;
                print; # Print the header of the desired service
            } else {
                in_desired_service = 0;
                # Do NOT print the header of undesired services (e.g., kafka-broker-0, kafka-connect)
            }
            next; # Move to the next line (header handled)
        }

        # If we are inside a desired service (kafka-controller-X), print all its indented content
        if (in_desired_service) {
            # Lines indented more than 'service_indent' (e.g., 4+ spaces) belong to the service
            if (current_indent_level > service_indent) {
                print;
            }
            next; # Move to the next line
        } else {
            # We are in the services block, but NOT inside a desired service.
            # If the current line is indented (i.e., content of an undesired service), skip it.
            if (current_indent_level > service_indent) {
                next; # Skip indented content of undesired services
            }
            # If it's not indented (current_indent_level <= service_indent),
            # it might be a new top-level key after services, which will be caught by the top-level section logic.
        }
    }
}
' "${COMPOSE_FILE}" > "${OUTPUT_FILE}"

echo "Filtered compose file created: ${OUTPUT_FILE}"

# Deploy the stack using the filtered temporary file
docker stack deploy --with-registry-auth --prune -c "${OUTPUT_FILE}" my-kafka-stack

# Clean up the temporary file after deployment
rm "${OUTPUT_FILE}"

echo "Deployment attempt completed."
