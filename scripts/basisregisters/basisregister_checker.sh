#!/bin/bash

set -e

# Configuration
MOCK_DIR="${1:-./scripts/basisregisters/__mock__}"
ENDPOINTS=(
    "https://data.vlaanderen.be/id/adres/3706808"
    "https://data.vlaanderen.be/id/adres/200001"
    "https://data.vlaanderen.be/id/gemeente/11001"
    "https://data.vlaanderen.be/id/gemeente/23047"
    "https://data.vlaanderen.be/id/postinfo/2000"
    "https://data.vlaanderen.be/id/postinfo/8400"
    "https://data.vlaanderen.be/id/straatnaam/116589"
    "https://data.vlaanderen.be/id/straatnaam/1"
    "https://data.vlaanderen.be/id/wegsegment/1"
    "https://data.vlaanderen.be/id/wegsegment/77002"
    "https://data.vlaanderen.be/id/gebouw/5666547"
    "https://data.vlaanderen.be/id/gebouw/31912514"
    "https://data.vlaanderen.be/id/gebouweenheid/14963668"
    "https://data.vlaanderen.be/id/gebouweenheid/5667547"
    "https://data.vlaanderen.be/id/perceel/11001B0001-00S000"
    "https://data.vlaanderen.be/id/perceel/24011E0053-00T004"
)

# Create temp directory for current responses
TEMP_DIR="${MOCK_DIR}/.temp"
mkdir -p "${TEMP_DIR}"
trap "rm -rf ${TEMP_DIR}" EXIT

# Fetch all endpoints
for endpoint in "${ENDPOINTS[@]}"; do
    # Extract resource type and ID. For example perceel and 24011E0053-00T004
    resource_type=$(echo "${endpoint}" | sed 's|https://data.vlaanderen.be/id/||g' | cut -d'/' -f1)
    resource_id=$(echo "${endpoint}" | sed 's|https://data.vlaanderen.be/id/||g' | cut -d'/' -f2)
    
    # Create file path
    response_file="${TEMP_DIR}/${resource_type}-${resource_id}.json"
    mock_file="${MOCK_DIR}/${resource_type}/${resource_id}.json"
    
    echo "Fetching: ${endpoint}"

    echo "curl -L -s ${endpoint}"
    
    # Fetch with Accept header for JSON-LD
    if curl -L -s "${endpoint}" -o "${response_file}" 2>/dev/null; then
        
        # Check if mock file exists
        if [ -f "${mock_file}" ]; then
            # Compare responses using jq for normalization
            if diff -q <(jq -S '.' "${mock_file}" 2>/dev/null || cat "${mock_file}") <(jq -S '.' "${response_file}" 2>/dev/null || cat "${response_file}") > /dev/null 2>&1; then
                echo "Response matches mock"
            else
                echo "CHANGES DETECTED"
                echo ""
                echo "Differences:"
                diff -u <(jq -S '.' "${mock_file}" 2>/dev/null || cat "${mock_file}") <(jq -S '.' "${response_file}" 2>/dev/null || cat "${response_file}") | head -20
            fi
        fi
    else
        echo "Failed to fetch: ${endpoint}"
    fi
done