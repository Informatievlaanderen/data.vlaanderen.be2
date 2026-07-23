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

MISMATCHES=0

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
    
    echo "curl -L ${endpoint}"
    
    # Fetch with Accept header for JSON-LD
    if curl -L "${endpoint}" -o "${response_file}" 2>/dev/null; then
        
        # Check if mock file exists
        if [ -f "${mock_file}" ]; then
            # Normalize both files for comparison
            mock_normalized=$(jq -S '.' "${mock_file}" 2>/dev/null) || mock_normalized=$(cat "${mock_file}")
            response_normalized=$(jq -S '.' "${response_file}" 2>/dev/null) || response_normalized=$(cat "${response_file}")
            
            # Compare normalized versions
            if [ "${mock_normalized}" = "${response_normalized}" ]; then
                echo "Response matches mock"
            else
                echo "MISMATCH DETECTED"
                cat "${response_file}"
                MISMATCHES=$((MISMATCHES + 1))
            fi
        fi
    else
        echo "Failed to fetch: ${endpoint}"
        MISMATCHES=$((MISMATCHES + 1))
    fi
done

echo ""
echo "=========================================="
if [ ${MISMATCHES} -gt 0 ]; then
    echo "Validation Failed - ${MISMATCHES} mismatch(es) detected"
    echo "=========================================="
    exit 1
else
    echo "Validation Complete - No mismatches detected"
    echo "=========================================="
    echo ""
    echo "Check the detailed logs above for specifics"
    exit 0
fi