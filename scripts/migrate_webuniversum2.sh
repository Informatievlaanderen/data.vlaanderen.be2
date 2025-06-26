#!/bin/bash

# filepath: scripts/run_replace_webuniversum_recursive.sh
# Script to recursively run replace_webuniversum2_classes.sh on files in a directory

# Parameters
TARGET_DIR="${1:-.}"        # Default to current directory if not specified
FILE_PATTERN="${2:-*.html}"   # Default to .html files if not specified
SCRIPT_TYPE="${3:-classes}" # Default to classes script, can be "classes", "links", or "both"

SCRIPT_DIR=$(dirname "$0")
CLASSES_SCRIPT="$SCRIPT_DIR/replace_webuniversum2_classes.sh"
LINKS_SCRIPT="$SCRIPT_DIR/replace_webuniversum2_links.sh"

# Check if the target directory exists
if [ ! -d "$TARGET_DIR" ]; then
    echo "Error: Directory '$TARGET_DIR' not found!"
    echo "Usage: $0 [directory] [file_pattern] [script_type]"
    echo "  script_type can be 'classes', 'links', or 'both' (default: 'classes')"
    exit 1
fi

# Check if the requested script(s) exist
if [[ "$SCRIPT_TYPE" == "classes" || "$SCRIPT_TYPE" == "both" ]] && [ ! -f "$CLASSES_SCRIPT" ]; then
    echo "Error: Webuniversum classes script '$CLASSES_SCRIPT' not found!"
    exit 1
fi

if [[ "$SCRIPT_TYPE" == "links" || "$SCRIPT_TYPE" == "both" ]] && [ ! -f "$LINKS_SCRIPT" ]; then
    echo "Error: Webuniversum links script '$LINKS_SCRIPT' not found!"
    exit 1
fi

# Find all files matching the pattern in the target directory and subdirectories
# Exclude files that already have "_webuniversum3" in their name
mapfile -t files < <(find "$TARGET_DIR" -type f -name "$FILE_PATTERN" | grep -v "_webuniversum3" || true)
file_count=${#files[@]}

if [ "$file_count" -eq 0 ]; then
    echo "No files matching '$FILE_PATTERN' found in '$TARGET_DIR'"
    exit 0
fi

echo "Found $file_count files matching '$FILE_PATTERN' in '$TARGET_DIR'"
echo "Starting webuniversum conversion using script type: $SCRIPT_TYPE"

# Process each file
classes_success=0
classes_failure=0
links_success=0
links_failure=0

for file in "${files[@]}"; do
    echo "Processing: $file"
    current_file="$file"

    # Run classes script if requested
    if [[ "$SCRIPT_TYPE" == "classes" || "$SCRIPT_TYPE" == "both" ]]; then
        echo "  Applying webuniversum classes conversion..."
        if "$CLASSES_SCRIPT" "$current_file"; then
            echo "  ✅ Successfully processed classes for: $file"
            ((classes_success++))

            # If we're running both scripts, update the current file to the output of the classes script
            if [[ "$SCRIPT_TYPE" == "both" ]]; then
                # Determine the output filename with _webuniversum3 suffix
                dirname=$(dirname "$current_file")
                basename=$(basename "$current_file")
                filename="${basename%.*}"
                extension="${basename##*.}"

                if [[ "$basename" == "$filename" ]]; then
                    next_file="${dirname}/${filename}_webuniversum3"
                else
                    next_file="${dirname}/${filename}_webuniversum3.${extension}"
                fi

                current_file="$next_file"
            fi
        else
            echo "  ❌ Failed to process classes for: $file"
            ((classes_failure++))
        fi
    fi

    # Run links script if requested
    if [[ "$SCRIPT_TYPE" == "links" || "$SCRIPT_TYPE" == "both" ]]; then
        echo "  Applying webuniversum links conversion..."
        if "$LINKS_SCRIPT" "$current_file"; then
            echo "  ✅ Successfully processed links for: $file"
            ((links_success++))
        else
            echo "  ❌ Failed to process links for: $file"
            ((links_failure++))
        fi
    fi

    echo "-----------------------------------"
done

echo "Conversion Summary:"
if [[ "$SCRIPT_TYPE" == "classes" || "$SCRIPT_TYPE" == "both" ]]; then
    echo "Classes Conversion:"
    echo "  ✓ Successfully processed: $classes_success files"
    echo "  ✗ Failed to process: $classes_failure files"
fi

if [[ "$SCRIPT_TYPE" == "links" || "$SCRIPT_TYPE" == "both" ]]; then
    echo "Links Conversion:"
    echo "  ✓ Successfully processed: $links_success files"
    echo "  ✗ Failed to process: $links_failure files"
fi

echo "Total files processed: $file_count"
