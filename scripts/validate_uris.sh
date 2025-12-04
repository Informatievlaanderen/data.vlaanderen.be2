#!/bin/bash

set -e

# Configuration
BRANCH=${1:-dev}
GITHUB_RAW_URL="https://raw.githubusercontent.com/Informatievlaanderen/data.vlaanderen.be-statistics/refs/heads/${BRANCH}"
CLASS_FILE="aggr.class"
PROPS_FILE="aggr.props"
TEMP_DIR="/tmp/uri-validation"
CACHE_DIR="${TEMP_DIR}/cache"

# Create temp directory
mkdir -p "${TEMP_DIR}" "${CACHE_DIR}"

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
skipped_count=0

# Function to validate anchor in RDF/TTL content
validate_anchor_in_content() {
    local anchor=$1
    local content=$2
    
    case "${content}" in
        *"${anchor}"* | *"#${anchor}"* | *": ${anchor} "* | *":${anchor} "* | *": ${anchor}"* | *":${anchor}"*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Function to get base URL content with caching
get_cached_content() {
    local base_uri=$1
    local cache_key=$(echo "${base_uri}" | md5sum | awk '{print $1}')
    local cache_file="${CACHE_DIR}/${cache_key}"
    
    # Check if content is already cached
    if [ -f "${cache_file}" ]; then
        cat "${cache_file}" 2>/dev/null || true
        return 0
    fi
    
    # Fetch and cache
    local content
    content=$(curl -L -s "${base_uri}" 2>/dev/null) || true
    
    if [ -n "${content}" ]; then
        echo "${content}" > "${cache_file}" 2>/dev/null || true
        echo "${content}"
        return 0
    fi
    
    return 1
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
    local total=$(echo "${uris}" | wc -l)
    
    echo "Found ${total} unique URIs"
    echo ""
    
    while IFS= read -r uri; do
        [ -z "${uri}" ] && continue
        
        # Skip URIs that don't contain .vlaanderen.be
        if [[ "${uri}" != *".vlaanderen.be"* ]]; then
            skipped_count=$((skipped_count + 1))
            continue
        fi
        
        # Check if URI has an anchor fragment
        if [[ "${uri}" == *"#"* ]]; then
            base_uri="${uri%#*}"
            anchor="${uri##*#}"
            
            # Fetch base URL content with caching
            local content=$(get_cached_content "${base_uri}" 2>/dev/null)
            local fetch_status=$?
            
            if [ ${fetch_status} -eq 0 ] && [ -n "${content}" ]; then
                if validate_anchor_in_content "${anchor}" "${content}"; then
                    passed_uris+=("${uri}")
                    passed_count=$((passed_count + 1))
                else
                    failed_uris+=("${uri}")
                    failed_count=$((failed_count + 1))
                fi
            else
                failed_uris+=("${uri}")
                failed_count=$((failed_count + 1))
            fi
        else
            local status_code=$(curl -L -o /dev/null -s -w "%{http_code}" "${uri}" 2>/dev/null)
            
            if [ "${status_code}" -eq 200 ] || [ "${status_code}" -eq 302 ] || [ "${status_code}" -eq 301 ]; then
                passed_uris+=("${uri}")
                passed_count=$((passed_count + 1))
            else
                failed_uris+=("${uri}")
                failed_count=$((failed_count + 1))
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
echo "Skipped (not .vlaanderen.be): ${skipped_count}"
echo "Cache files: $(find "${CACHE_DIR}" -type f | wc -l)"
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
    echo "  Skipped: ${skipped_count}"
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