#!/bin/bash

# Script to push all generated files to oslo-publications-service repository
# Usage: push-to-oslo-publications.sh <workspace-dir> <ssh-key-fingerprint>

WORKSPACE_DIR=$1
SSH_KEY_FINGERPRINT=$2
JSONI=$3
CURRENT_BRANCH=${CIRCLE_BRANCH:-"main"}

echo "Current branch: ${CURRENT_BRANCH}"
echo "Workspace directory: ${WORKSPACE_DIR}"
echo "SSH key fingerprint: ${SSH_KEY_FINGERPRINT}"

echo $JSONI

TYPE=$(jq -r ".type" ${JSONI})
echo "Type: ${TYPE} from JSONI"

if [ -z "$WORKSPACE_DIR" ] || [ -z "$SSH_KEY_FINGERPRINT" ] || [ -z "$JSONI"]; then
    echo "Usage: $0 <workspace-dir> <ssh-key-fingerprint>"
    exit 1
fi

echo "Setting up Git configuration..."
git config --global user.email "circleci@informatievlaanderen.be"
git config --global user.name "CircleCI"

echo "Cloning oslo-publications-service repository..."
cd /tmp
git clone git@github.com:Informatievlaanderen/oslo-publications-service.git
cd oslo-publications-service

# Switch to the current branch
echo "Switching to branch: ${CURRENT_BRANCH}"
git checkout ${CURRENT_BRANCH} || git checkout -b ${CURRENT_BRANCH}

echo "Processing generated files..."

# Function to determine file type and language
determine_type_and_language() {
    local file="$1"
    local filename=$(basename "$file")
    local file_extension="${file##*.}"
    local type=""
    local language="nl" # default

    # Extract language from filename if present (e.g., *_en.json, *_nl.json)
    if [[ "$filename" =~ _([a-z]{2})\. ]]; then
        language="${BASH_REMATCH[1]}"
    fi

    # Determine type from file extension or filename patterns
    case "$file_extension" in
    "json")
        if [[ "$filename" == *"webuniversum-config"* ]]; then
            type="webuniversum-config"
        elif [[ "$filename" == *"context"* ]]; then
            type="context"
        else
            type="json"
        fi
        ;;
    "jsonld") type="jsonld" ;;
    "ttl") type="ttl" ;;
    "rdf") type="rdf" ;;
    "shacl") type="shacl" ;;
    "html") type="html" ;;
    "md") type="markdown" ;;
    *)
        # Try to determine type from directory structure
        if [[ "$file" == *"/html/"* ]]; then
            type="html"
        elif [[ "$file" == *"/rdf/"* ]]; then
            type="rdf"
        elif [[ "$file" == *"/shacl/"* ]]; then
            type="shacl"
        elif [[ "$file" == *"/context/"* ]]; then
            type="context"
        else
            type="misc"
        fi
        ;;
    esac

    echo "${type}:${language}"
}

extract_spec_name() {
    local path="$1"
    # Handle different path patterns
    if [[ "$path" =~ ^doc/applicatieprofiel/([^/]+) ]]; then
        # Pattern: doc/applicatieprofiel/SPEC_NAME/...
        spec_name="${BASH_REMATCH[1]}"
    elif [[ "$path" =~ ^doc/vocabularium/([^/]+) ]]; then
        # Pattern: doc/vocabularium/SPEC_NAME/...
        spec_name="${BASH_REMATCH[1]}"
    elif [[ "$path" =~ ^doc/implementatiemodel/([^/]+) ]]; then
        # Pattern: doc/implementatiemodel/SPEC_NAME/...
        spec_name="${BASH_REMATCH[1]}"
    elif [[ "$path" =~ ^([^/]+)/([^/]+) ]]; then
        # Fallback: assume second part is spec name
        spec_name="${BASH_REMATCH[2]}"
    else
        # Last resort: use first directory
        spec_name=$(echo "$path" | cut -d'/' -f1)
    fi

    echo "$spec_name"
}

# Process files from target directory
if [ -d "${WORKSPACE_DIR}/target" ]; then
    echo "Processing target directory files..."
    find "${WORKSPACE_DIR}/target" -type f | while read generated_file; do
        echo "Processing: $generated_file"

        # Extract spec name from path
        relative_path=$(echo "$generated_file" | sed "s|${WORKSPACE_DIR}/target/||")
        Relative path: doc/applicatieprofiel/energiehuis/ontwerpstandaard/test/context/energiehuis.jsonld
        echo "Relative path: $relative_path"
        spec_name=$(extract_spec_name "$relative_path")

        # Get type and language
        type_lang=$(determine_type_and_language "$generated_file")
        type=$(echo "$type_lang" | cut -d':' -f1)
        language=$(echo "$type_lang" | cut -d':' -f2)
        filename=$(basename "$generated_file")
        echo "Type: $TYPE, Language: $language, Filename: $filename"

        # Create target directory structure
        target_dir="content/${spec_name}/${language}/${TYPE}"
        mkdir -p "$target_dir"

        # Copy the file
        cp "$generated_file" "$target_dir/$filename"
        echo "Copied to: $target_dir/$filename"
    done
fi

# Process files from report4 directory
if [ -d "${WORKSPACE_DIR}/report4" ]; then
    echo "Processing report4 directory files..."
    find "${WORKSPACE_DIR}/report4" -type f \( -name "*.json" -o -name "*.jsonld" -o -name "*.ttl" -o -name "*.rdf" -o -name "*.shacl" -o -name "*.html" \) | while read report_file; do
        echo "Processing report file: $report_file"

        # Extract spec name from path
        relative_path=$(echo "$report_file" | sed "s|${WORKSPACE_DIR}/report4/||")
        spec_name=$(extract_spec_name "$relative_path")

        # Get type and language
        type_lang=$(determine_type_and_language "$report_file")
        type=$(echo "$type_lang" | cut -d':' -f1)
        language=$(echo "$type_lang" | cut -d':' -f2)
        filename=$(basename "$report_file")

        # Create target directory structure
        target_dir="content/${spec_name}/${language}/${type}"
        mkdir -p "$target_dir"

        # Copy the file
        cp "$report_file" "$target_dir/$filename"
        echo "Copied report file to: $target_dir/$filename"
    done
fi

# Check if there are any changes to commit
if [ -n "$(git status --porcelain)" ]; then
    echo "Committing and pushing changes..."
    git add .
    git commit -m "Update generated files from ${CURRENT_BRANCH} branch - $(date)"
    git push origin ${CURRENT_BRANCH}
    echo "Successfully pushed all generated files to oslo-publications-service"
else
    echo "No changes to commit"
fi

echo "Script completed successfully"
