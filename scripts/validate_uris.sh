#!/bin/bash

set -e

# Configuration
BRANCH=${1:-dev}
GITHUB_RAW_URL="https://raw.githubusercontent.com/Informatievlaanderen/data.vlaanderen.be-statistics/refs/heads/${BRANCH}"
CLASS_FILE="aggr.class"
PROPS_FILE="aggr.props"
TEMP_DIR="/tmp/uri-validation"

# Create temp directory
mkdir -p "${TEMP_DIR}"

echo "URI Validation Script"
echo "Branch: ${BRANCH}"
echo ""

# Download files
echo "Downloading files from GitHub..."
curl -s -o "${TEMP_DIR}/${CLASS_FILE}" "${GITHUB_RAW_URL}/${CLASS_FILE}" || {
    echo "Error downloading ${CLASS_FILE}"
    exit 1
}

curl -s -o "${TEMP_DIR}/${PROPS_FILE}" "${GITHUB_RAW_URL}/${PROPS_FILE}" || {
    echo "Error downloading ${PROPS_FILE}"
    exit 1
}

echo "Files downloaded successfully"
echo ""

# Initialize counters and arrays
passed_count=0
failed_count=0
failed_uris=()
passed_uris=()

# Function to validate anchor in RDF/TTL content
validate_anchor_in_content() {
    local anchor=$1
    local content=$2
    
    if echo "${content}" | grep -qE "(${anchor}|<[^>]*#${anchor}>|:[[:space:]]*${anchor}[[:space:]])" ; then
        return 0
    else
        return 1
    fi
}

# Function to validate URIs from a file
validate_uris_from_file() {
    local file=$1
    local file_type=$2
    
    if [ ! -f "${file}" ]; then
        echo "File not found: ${file}"
        return 1
    fi
    
    echo "Validating ${file_type} URIs from $(basename ${file})..."
    
    # Extract unique assignedURIs from JSON array of objects
    local uris=$(jq -r '.[].assignedURI' "${file}" 2>/dev/null | sort | uniq)
    local total=$(echo "${uris}" | grep -c . || echo 0)
    
    echo "Found ${total} unique URIs"
    echo ""
    
    while IFS= read -r uri; do
        [ -z "${uri}" ] && continue
        
        # Skip URIs that don't contain .vlaanderen.be
        if [[ "${uri}" != *".vlaanderen.be"* ]]; then
            continue
        fi
        
        # Check to see if the uri is available. We will check the anchor later. ANchor can be wrong but publication could be done correct
        local status_code=$(curl -Lo /dev/null -s -w "%{http_code}\n" "${uri}")
        if [ "${status_code}" -ne 200 ]; then
            echo "[FAIL] ${uri} (publication not found)"
            failed_uris+=("${uri}")
            failed_count=$((failed_count + 1))
        fi


        # Check if URI has an anchor fragment
        if [[ "${uri}" == *"#"* ]] && [ "${status_code}" -eq 200 ]; then
            base_uri="${uri%#*}"
            anchor="${uri##*#}"
            
            # Fetch base URL content
            local content=$(curl -L -s "${base_uri}" 2>/dev/null)
            local base_status=$?
            
            if [ ${base_status} -eq 0 ] && [ -n "${content}" ]; then
                if validate_anchor_in_content "${anchor}" "${content}"; then
                    echo "[PASS] ${uri}"
                    
                    passed_uris+=("${uri}")
                    passed_count=$((passed_count + 1))
                else
                    echo "[FAIL] ${uri} (anchor not found)"
                    failed_uris+=("${uri}")
                    failed_count=$((failed_count + 1))
                fi
            else
                echo "[FAIL] ${uri} (base URL failed)"
                failed_uris+=("${uri}")
                failed_count=$((failed_count + 1))
            fi
        else    
            if [ "${status_code}" -eq 200 ] || [ "${status_code}" -eq 302 ] || [ "${status_code}" -eq 301 ]; then
                echo "[PASS] ${uri}"
                passed_uris+=("${uri}")
                passed_count=$((passed_count + 1))
            fi
        fi
    done <<< "${uris}"
    
    echo ""
}

# Validate both files
validate_uris_from_file "${TEMP_DIR}/${CLASS_FILE}" "Classes"
validate_uris_from_file "${TEMP_DIR}/${PROPS_FILE}" "Properties"

# Summary
echo "Validation Summary"
echo "Passed: ${passed_count}"
echo "Failed: ${failed_count}"
echo ""

# Display failed URIs if any
if [ ${#failed_uris[@]} -gt 0 ]; then
    echo "Failed URIs:"
    printf '%s\n' "${failed_uris[@]}"
    echo ""
fi

# Save detailed report
REPORT_FILE="${TEMP_DIR}/validation-report.txt"
{
    echo "URI Validation Report"
    echo "Generated: $(date)"
    echo "Branch: ${BRANCH}"
    echo ""
    echo "Summary:"
    echo "  Passed: ${passed_count}"
    echo "  Failed: ${failed_count}"
    echo ""
    
    if [ ${#failed_uris[@]} -gt 0 ]; then
        echo "Failed URIs:"
        printf '%s\n' "${failed_uris[@]}"
    fi
} > "${REPORT_FILE}"

echo "Report saved to: ${REPORT_FILE}"
echo ""

# Exit with appropriate code
if [ ${failed_count} -gt 0 ]; then
    exit 1
else
    echo "All vlaanderen.be URIs validated successfully"
    exit 0
fi