#!/bin/bash

# filepath: scripts/migrate_webuniversum2.sh
# Script to recursively run webuniversum replacement scripts on files in a directory

# Parameters
TARGET_DIR="${1:-.}"        # Default to current directory if not specified
FILE_PATTERN="${2:-*.html}" # Default to .html files if not specified
SCRIPT_TYPE="${3:-all}"     # Default to classes script, can be "classes", "links", "tooltip", or combinations

SCRIPT_DIR=$(dirname "$0")
CLASSES_SCRIPT="$SCRIPT_DIR/replace_webuniversum2_classes.sh"
LINKS_SCRIPT="$SCRIPT_DIR/replace_webuniversum2_links.sh"
TOOLTIP_SCRIPT="$SCRIPT_DIR/replace_webuniversum2_tooltip.sh"

# Check if the target directory exists
if [ ! -d "$TARGET_DIR" ]; then
    echo "Error: Directory '$TARGET_DIR' not found!"
    echo "Usage: $0 [directory] [file_pattern] [script_type]"
    echo "  script_type can be 'classes', 'links', 'tooltip', 'all', or combinations like 'classes,links'"
    echo "  Available combinations: classes, links, tooltip, classes+links, classes+tooltip, links+tooltip, all"
    exit 1
fi

# Parse script types (support comma-separated and plus-separated values)
IFS=',+' read -ra SCRIPT_TYPES <<<"$SCRIPT_TYPE"

# Normalize script types
NORMALIZE_SCRIPTS=()
for script in "${SCRIPT_TYPES[@]}"; do
    script=$(echo "$script" | tr -d ' ') # Remove spaces
    case "$script" in
    "classes" | "links" | "tooltip")
        NORMALIZE_SCRIPTS+=("$script")
        ;;
    "both")
        NORMALIZE_SCRIPTS+=("classes" "links")
        ;;
    "all")
        NORMALIZE_SCRIPTS+=("links" "tooltip" "classes")
        ;;
    *)
        echo "Warning: Unknown script type '$script' ignored"
        ;;
    esac
done

# Remove duplicates using bash 3.x compatible method
SCRIPT_TYPES=()
for script in "${NORMALIZE_SCRIPTS[@]}"; do
    # Check if script is already in SCRIPT_TYPES array
    already_exists=false
    for existing in "${SCRIPT_TYPES[@]}"; do
        if [[ "$existing" == "$script" ]]; then
            already_exists=true
            break
        fi
    done

    # Add to array if not already present
    if [[ "$already_exists" == false ]]; then
        SCRIPT_TYPES+=("$script")
    fi
done

if [ ${#SCRIPT_TYPES[@]} -eq 0 ]; then
    echo "Error: No valid script types specified!"
    echo "Valid options: classes, links, tooltip, both, all"
    exit 1
fi

echo "Script types to run: ${SCRIPT_TYPES[*]}"

# Check if the requested script(s) exist
for script_type in "${SCRIPT_TYPES[@]}"; do
    case "$script_type" in
    "classes")
        if [ ! -f "$CLASSES_SCRIPT" ]; then
            echo "Error: Webuniversum classes script '$CLASSES_SCRIPT' not found!"
            exit 1
        fi
        ;;
    "links")
        if [ ! -f "$LINKS_SCRIPT" ]; then
            echo "Error: Webuniversum links script '$LINKS_SCRIPT' not found!"
            exit 1
        fi
        ;;
    "tooltip")
        if [ ! -f "$TOOLTIP_SCRIPT" ]; then
            echo "Error: Webuniversum tooltip script '$TOOLTIP_SCRIPT' not found!"
            exit 1
        fi
        ;;
    esac
done

# Find all files matching the pattern in the target directory and subdirectories
# Use bash 3.x compatible method instead of mapfile
echo "Searching for files in '$TARGET_DIR' with pattern '$FILE_PATTERN'..."
files=()
while IFS= read -r -d '' file; do
    # Extract just the filename from the full path
    filename=$(basename "$file")

    # Only include files that:
    # 1. Start with "index"
    # 2. End with ".html"
    # 3. Don't already have "_webuniversum3" in their name
    if [[ "$filename" == index*.html ]]; then
        # Additional filter: exclude files that start with something other than "index"
        # (e.g., exclude "respec_index.html" but include "index_nl.html")
        if [[ "$filename" =~ ^index.*\.html$ ]]; then
            files+=("$file")
        fi
    fi
done < <(find "$TARGET_DIR" -type f -name "$FILE_PATTERN" -print0 2>/dev/null)

file_count=${#files[@]}

if [ "$file_count" -eq 0 ]; then
    echo "No index*.html files matching '$FILE_PATTERN' found in '$TARGET_DIR'"
    echo "Checking what files exist in the directory..."
    echo "All HTML files found:"
    find "$TARGET_DIR" -type f -name "*.html" | head -10
    echo ""
    echo "Files starting with 'index':"
    find "$TARGET_DIR" -type f -name "index*.html" | head -10
    exit 0
fi

echo "Found $file_count index*.html files matching '$FILE_PATTERN' in '$TARGET_DIR'"
echo "Starting webuniversum conversion using script types: ${SCRIPT_TYPES[*]}"

# List the files that will be processed
echo ""
echo "Files to be processed:"
for file in "${files[@]}"; do
    echo "  - $file"
done
echo ""

# Process each file
classes_success=0
classes_failure=0
links_success=0
links_failure=0
tooltip_success=0
tooltip_failure=0

for file in "${files[@]}"; do
    echo "Processing: $file"
    current_file="$file"
    file_success=true

    # Run scripts in order: classes, tooltip, links
    for script_type in "${SCRIPT_TYPES[@]}"; do
        case "$script_type" in
        "classes")
            echo "  Applying webuniversum classes conversion..."
            if "$CLASSES_SCRIPT" "$current_file"; then
                echo "  ✅ Successfully processed classes for: $file"
                ((classes_success++))

                # Update current file to the output file for chaining
                dirname=$(dirname "$current_file")
                basename=$(basename "$current_file")
                filename="${basename%.*}"
                extension="${basename##*.}"

                if [[ "$basename" == "$filename" ]]; then
                    current_file="${dirname}/${filename}_webuniversum3"
                else
                    current_file="${dirname}/${filename}_webuniversum3.${extension}"
                fi
            else
                echo "  ❌ Failed to process classes for: $file"
                ((classes_failure++))
                file_success=false
            fi
            ;;

        "tooltip")
            echo "  Applying webuniversum tooltip conversion..."
            # Tooltip script modifies file in place, so we use current_file
            if "$TOOLTIP_SCRIPT" "$current_file"; then
                echo "  ✅ Successfully processed tooltips for: $current_file"
                ((tooltip_success++))
            else
                echo "  ❌ Failed to process tooltips for: $current_file"
                ((tooltip_failure++))
                file_success=false
            fi
            ;;

        "links")
            echo "  Applying webuniversum links conversion..."
            # Links script needs input and output files
            temp_links_file=$(mktemp)
            if "$LINKS_SCRIPT" "$current_file" "$temp_links_file"; then
                mv "$temp_links_file" "$current_file"
                echo "  ✅ Successfully processed links for: $current_file"
                ((links_success++))
            else
                rm -f "$temp_links_file"
                echo "  ❌ Failed to process links for: $current_file"
                ((links_failure++))
                file_success=false
            fi
            ;;
        esac

        # If any script fails, break the chain for this file
        if [ "$file_success" = false ]; then
            break
        fi
    done

    echo "-----------------------------------"
done

echo ""
echo "Conversion Summary:"
echo "=================="

total_success=0
total_failure=0

for script_type in "${SCRIPT_TYPES[@]}"; do
    case "$script_type" in
    "classes")
        echo "Classes Conversion:"
        echo "  ✓ Successfully processed: $classes_success files"
        echo "  ✗ Failed to process: $classes_failure files"
        total_success=$((total_success + classes_success))
        total_failure=$((total_failure + classes_failure))
        ;;
    "tooltip")
        echo "Tooltip Conversion:"
        echo "  ✓ Successfully processed: $tooltip_success files"
        echo "  ✗ Failed to process: $tooltip_failure files"
        total_success=$((total_success + tooltip_success))
        total_failure=$((total_failure + tooltip_failure))
        ;;
    "links")
        echo "Links Conversion:"
        echo "  ✓ Successfully processed: $links_success files"
        echo "  ✗ Failed to process: $links_failure files"
        total_success=$((total_success + links_success))
        total_failure=$((total_failure + links_failure))
        ;;
    esac
done

echo ""
echo "Overall Summary:"
echo "==============="
echo "Total files found: $file_count"
echo "Total successful operations: $total_success"
echo "Total failed operations: $total_failure"
echo ""

if [ $total_failure -eq 0 ]; then
    echo "🎉 All conversions completed successfully!"
else
    echo "⚠️  Some conversions failed. Check the output above for details."
fi
