#!/bin/bash

CONFIGDIR=$1

# Check if the directory argument is provided
if [ -z "$CONFIGDIR" ]; then
    echo "Usage: $0 <directory>"
    exit 1
fi

HOSTNAME=$(jq -r .hostname ${CONFIGDIR}/config.json)
DIRECTORY=$(jq -r '.publicationpoints[0]' "${CONFIGDIR}/config.json")

# Initialize arrays for tracking
failed_urls=()
failed_details=()

# Count total publication files
total_pubs=$(find "$CONFIGDIR/$DIRECTORY" -name '*.publication.json' | wc -l)

# Use process substitution to avoid subshell issues
while read -r pub_file; do
    pub_file_basename=$(basename "$pub_file")
    echo "Processing $pub_file"

    # Get the number of entries in the array
    count=$(jq '. | length' "$pub_file")

    # Process each entry in the array
    for ((i = 0; i < $count; i++)); do
        echo "Processing entry $i"

        # Check if urlref exists and is not null/empty for this entry
        if ! jq -e ".[$i] | has(\"urlref\") and .urlref != null and .urlref != \"\"" "$pub_file" >/dev/null 2>&1; then
            echo "Skipping: No urlref in entry $i (shorthand notation)"
            continue
        fi

        # Rest of the processing remains unchanged
        has_name=false
        if jq -e ".[$i] | has(\"name\") and .name != null and .name != \"\"" "$pub_file" >/dev/null 2>&1; then
            has_name=true
            name=$(jq -r ".[$i].name" "$pub_file")
        elif jq -e ".[$i] | has(\"seealso\") and .seealso != null and .seealso != \"\"" "$pub_file" >/dev/null 2>&1; then
            # If no direct name but has 'seealso', find the referenced entry
            seealso=$(jq -r ".[$i].seealso" "$pub_file")
            echo "Entry $i has no name but references: $seealso"

            # Find the entry with matching urlref
            ref_index=$(jq -r "map(.urlref == \"$seealso\") | index(true)" "$pub_file")

            if [[ "$ref_index" != "null" ]]; then
                # Found matching reference, get its name
                if jq -e ".[$ref_index] | has(\"name\") and .name != null and .name != \"\"" "$pub_file" >/dev/null 2>&1; then
                    has_name=true
                    name=$(jq -r ".[$ref_index].name" "$pub_file")
                    echo "Using name '$name' from referenced entry at index $ref_index"
                fi
            fi
        fi

        if [[ "$has_name" != "true" ]]; then
            echo "Skipping: No name in entry $i and no valid reference found"
            continue
        fi

        urlref=$(jq -r ".[$i].urlref" "$pub_file")

        # Ensure urlref never ends with a slash
        if [[ "$urlref" == */ ]]; then
            urlref="${urlref%/}"
        fi

        # Check main URL
        status_code=$(curl -L -o /dev/null -s -w "%{http_code}\n" "$HOSTNAME$urlref")
        if [ "$status_code" -ne 200 ]; then
            echo "URL: $HOSTNAME$urlref - Status Code: $status_code"
            failed_urls+=("$HOSTNAME$urlref")
            failed_details+=("Publication: $pub_file_basename, Entry: $i, Name: $name, Type: Main URL, URL: $HOSTNAME$urlref, Status: $status_code")
        else
            echo "URL: $HOSTNAME$urlref - Status Code: 200 ✓"
        fi

        # Check for different URL types and perform specific validations
        if [[ "$urlref" == *"applicatieprofiel"* ]] || [[ "$urlref" == *"implementatiemodel"* ]]; then
            # Check .ttl file for application profiles
            ttl_url="$HOSTNAME$urlref/shacl/$name-SHACL.ttl"
            status_code=$(curl -L -o /dev/null -s -w "%{http_code}\n" "$ttl_url")
            if [ "$status_code" -ne 200 ]; then
                echo "TTL URL: $ttl_url - Status Code: $status_code"
                failed_urls+=("$ttl_url")
                failed_details+=("Publication: $pub_file_basename, Entry: $i, Name: $name, Type: SHACL TTL, URL: $ttl_url, Status: $status_code")
            else
                echo "TTL URL: $ttl_url - Status Code: 200 ✓"
            fi

            # Check JSON-LD context file for application profiles
            jsonld_url="$HOSTNAME$urlref/context/$name.jsonld"
            status_code=$(curl -L -o /dev/null -s -w "%{http_code}\n" "$jsonld_url")
            if [ "$status_code" -ne 200 ]; then
                echo "JSON-LD URL: $jsonld_url - Status Code: $status_code"
                failed_urls+=("$jsonld_url")
                failed_details+=("Publication: $pub_file_basename, Entry: $i, Name: $name, Type: Context JSON-LD, URL: $jsonld_url, Status: $status_code")
            else
                echo "JSON-LD URL: $jsonld_url - Status Code: 200 ✓"
            fi
        elif [[ "$urlref" == */ns/* ]]; then
            # Check for TTL file in NS path
            ns_ttl_url="$HOSTNAME/ns/$name.ttl"
            status_code=$(curl -L -o /dev/null -s -w "%{http_code}\n" "$ns_ttl_url")
            if [ "$status_code" -ne 200 ]; then
                echo "NS TTL URL: $ns_ttl_url - Status Code: $status_code"
                failed_urls+=("$ns_ttl_url")
                failed_details+=("Publication: $pub_file_basename, Entry: $i, Name: $name, Type: NS TTL, URL: $ns_ttl_url, Status: $status_code")
            else
                echo "NS TTL URL: $ns_ttl_url - Status Code: 200 ✓"
            fi

            # Check for JSON-LD file in NS path
            ns_jsonld_url="$HOSTNAME/ns/$name.jsonld"
            status_code=$(curl -L -o /dev/null -s -w "%{http_code}\n" "$ns_jsonld_url")
            if [ "$status_code" -ne 200 ]; then
                echo "NS JSON-LD URL: $ns_jsonld_url - Status Code: $status_code"
                failed_urls+=("$ns_jsonld_url")
                failed_details+=("Publication: $pub_file_basename, Entry: $i, Name: $name, Type: NS JSON-LD, URL: $ns_jsonld_url, Status: $status_code")
            else
                echo "NS JSON-LD URL: $ns_jsonld_url - Status Code: 200 ✓"
            fi
        elif [[ "$urlref" == *"vocabularium"* ]]; then
            echo "Skipping SHACL and JSON-LD checks for vocabulary: $urlref"
        else
            echo "URL type not recognized, skipping additional checks: $urlref"
        fi
    done
done < <(find "$CONFIGDIR/$DIRECTORY" -name '*.publication.json')

# Summary of validation results
echo "======= Validation Summary ======="
if [ ${#failed_urls[@]} -eq 0 ]; then
    echo "All URLs validated successfully!"
else
    echo "Failed URLs: ${#failed_urls[@]}"
    echo ""
    echo "===== DETAILED OVERVIEW OF FAILED ENDPOINTS ====="
    printf "%s\n" "${failed_details[@]}"
    exit 1
fi
