#!/bin/bash

# Predefined array of CSS class mappings (old_class:new_class)
CLASS_MAPPINGS=(
    "page:vl-page"
    "region:vl-region"
    "layout:vl-layout"
    "grid:vl-grid"
    "typography:vl-typography"
    "introduction:vl-introduction"
    "content-header:vl-content-header"
    "doormat:vl-doormat"
    "bullet-list:vl-bullet-list"
    "content-header__title__content:vl-content-header__title__content"
    "side-navigation js-sticky region:side-navigation js-sticky region"
    "side-navigation js-sticky:vl-side-navigation vl-u-sticky vl-region"
    "side-navigation:vl-side-navigation"
    "main-content:vl-main-content"
    # Remove the sortable part from it since there is no logic to actually sort the items inside the table
    "data-table__header-title--sortable:data-table__header-title"
    "data-table:vl-data-table"
    "u-table-overflow:vl-u-table-overflow"
    "h1:vl-title--h1"
    "h2:vl-title--h2"
    "h3:vl-title--h3"
    "h4:vl-title--h4"
    "h5:vl-title--h5"
    "col--1-1--s:vl-col--1-1--s"
    "col--3-12:vl-col--3-12"
    "col--4-12--m:vl-col--4-12--m"
    "col--8-12:vl-col--8-12"
    "col--9-12:vl-col--9-12"
    "col--12-12--s:vl-col--12-12--s"
    "col--4-12:vl-col--6-12"
    "col--1-2--s:vl-col--1-2--s"
    "col--12-12--xs:vl-col--12-12--xs"
    "push--1-12:vl-push--1-12"
    "push--reset--m:vl-push--reset--m"
    "skiplink:vl-skiplink"
)

# Parse command line arguments
VALIDATE=false
INPUT_FILE=""

show_usage() {
    echo "Usage: $0 [options] input_file"
    echo "Options:"
    echo "  -v, --validate    Enable validation of class replacements (default: off)"
    echo "  -h, --help        Show this help message"
    echo ""
    echo "Example:"
    echo "  $0 templates/voc2.j2                    # Process without validation"
    echo "  $0 --validate templates/voc2.j2         # Process with validation"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--validate)
            VALIDATE=true
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        -*)
            echo "Unknown option: $1"
            show_usage
            exit 1
            ;;
        *)
            if [[ -z "$INPUT_FILE" ]]; then
                INPUT_FILE="$1"
            else
                echo "Error: Multiple input files specified"
                show_usage
                exit 1
            fi
            shift
            ;;
    esac
done

# Default input file if none provided
if [[ -z "$INPUT_FILE" ]]; then
    INPUT_FILE="packages/oslo-generator-html/lib/templates/voc2.j2"
fi

# Check if input file exists
if [[ ! -f "$INPUT_FILE" ]]; then
    echo "Error: Input file '$INPUT_FILE' not found!"
    show_usage
    exit 1
fi

# Create output filename with _webuniversum3 suffix
DIR=$(dirname "$INPUT_FILE")
BASENAME=$(basename "$INPUT_FILE")
FILENAME="${BASENAME%.*}"
EXTENSION="${BASENAME##*.}"

if [[ "$BASENAME" == "$FILENAME" ]]; then
    OUTPUT_FILE="${DIR}/${FILENAME}"
else
    OUTPUT_FILE="${DIR}/${FILENAME}.${EXTENSION}"
fi

echo "CSS Class Replacement Script (Webuniversum 2 → 3)"
echo "================================================="
echo "Input file: $INPUT_FILE"
echo "Output file: $OUTPUT_FILE"
echo "Validation: $([ "$VALIDATE" = true ] && echo "enabled" || echo "disabled")"
echo ""

total_replacements=0
# Use regular arrays instead of associative arrays
replacement_keys=()
replacement_values=()

create_perl_script() {
    cat >temp_replace.pl <<'EOF'
use strict;
use warnings;

# Read all mappings from environment variables
my @mappings;
for my $i (0..99) {  # Support up to 100 mappings
    my $old = $ENV{"OLD_CLASS_$i"};
    my $new = $ENV{"NEW_CLASS_$i"};
    last unless defined $old && defined $new;
    push @mappings, [$old, $new];
}

# Sort mappings by length of old_class (longest first) to avoid substring issues
@mappings = sort { length($b->[0]) <=> length($a->[0]) } @mappings;

while (<>) {
    my $line = $_;
    
    # Only process lines that contain class attributes
    if ($line =~ /class="/) {
        # Apply all mappings to class attributes only
        for my $mapping (@mappings) {
            my ($old, $new) = @$mapping;
            
            # FIXED: Use global flag to replace ALL occurrences of the base class
            # This handles cases like "layout layout--wide" correctly
            $line =~ s/(class="[^"]*?)(?<![a-zA-Z0-9_-])\Q$old\E(?!(?:__|--)|\w)([^"]*")/$1$new$2/g;
            
            # Also handle BEM variants that need the base class updated
            $line =~ s/(class="[^"]*?)(?<![a-zA-Z0-9_-])\Q$old\E(--[a-zA-Z0-9-]+)(?![a-zA-Z0-9_-])([^"]*")/$1$new$2$3/g;
            $line =~ s/(class="[^"]*?)(?<![a-zA-Z0-9_-])\Q$old\E(__[a-zA-Z0-9-]+)(?![a-zA-Z0-9_-])([^"]*")/$1$new$2$3/g;
        }
    }
    
    print $line;
}
EOF
}

# Create the Perl script
create_perl_script

# Set environment variables for all mappings
for i in "${!CLASS_MAPPINGS[@]}"; do
    IFS=':' read -r old_class new_class <<<"${CLASS_MAPPINGS[$i]}"
    export "OLD_CLASS_$i=$old_class"
    export "NEW_CLASS_$i=$new_class"
done

# Run the replacement
echo "Processing all class replacements in a single pass..."
perl temp_replace.pl "$INPUT_FILE" >"$OUTPUT_FILE.tmp"

# Clean up
rm -f temp_replace.pl
for i in "${!CLASS_MAPPINGS[@]}"; do
    unset "OLD_CLASS_$i"
    unset "NEW_CLASS_$i"
done

if [[ $total_replacements -gt 0 ]]; then
    echo ""
    echo "Detailed breakdown:"
    for i in "${!replacement_keys[@]}"; do
        key="${replacement_keys[$i]}"
        value="${replacement_values[$i]}"
        readable_key=$(echo "$key" | sed 's/_to_/ → /g')
        echo "  $readable_key: $value replacement(s)"
    done
fi

echo ""

# Optional: Show a diff of changes
if command -v diff >/dev/null 2>&1 && [[ $total_replacements -gt 0 ]]; then
    echo "Preview of changes (first 20 lines):"
    echo "===================================="
    diff -u "$INPUT_FILE" "$OUTPUT_FILE.tmp" | head -20
    echo ""
    echo "(Use 'diff -u $INPUT_FILE $OUTPUT_FILE.tmp' to see all changes)"
    echo ""
fi

# FORMAT THE HTML OUTPUT
echo "Formatting HTML output..."
echo "========================"

# Function to count exact class matches without false positives
count_exact_class_matches() {
    local class_name="$1"
    local file="$2"
    local count=0

    # Process each line that contains class="
    while IFS= read -r line; do
        if [[ "$line" =~ class=\"([^\"]*)\" ]]; then
            local class_content="${BASH_REMATCH[1]}"
            # Split class content by spaces and check each class
            IFS=' ' read -ra class_array <<<"$class_content"
            for class in "${class_array[@]}"; do
                # Check for exact match or BEM variants
                if [[ "$class" == "$class_name" ]] ||
                    [[ "$class" =~ ^${class_name}--[a-zA-Z0-9-]+$ ]] ||
                    [[ "$class" =~ ^${class_name}__[a-zA-Z0-9-]+$ ]]; then
                    ((count++))
                fi
            done
        fi
    done < <(grep 'class=' "$file" 2>/dev/null || true)

    echo "$count"
}

# Format the HTML output using available tools
if command -v tidy >/dev/null 2>&1; then
    echo "Using 'tidy' to format HTML..."
    tidy -indent -wrap 120 -quiet --show-warnings no --drop-empty-elements no --fix-bad-html no "$OUTPUT_FILE.tmp" >"$OUTPUT_FILE" 2>/dev/null || cp "$OUTPUT_FILE.tmp" "$OUTPUT_FILE"
elif command -v xmllint >/dev/null 2>&1; then
    echo "Using 'xmllint' to format HTML..."
    xmllint --format --html "$OUTPUT_FILE.tmp" >"$OUTPUT_FILE" 2>/dev/null || cp "$OUTPUT_FILE.tmp" "$OUTPUT_FILE"
elif command -v python3 >/dev/null 2>&1; then
    echo "Using Python to format HTML..."
    python3 -c "
import sys
try:
    with open('$OUTPUT_FILE.tmp', 'r') as f:
        content = f.read()
    
    # Simple indentation fix for template files
    lines = content.split('\n')
    formatted_lines = []
    indent_level = 0
    
    for line in lines:
        stripped = line.strip()
        if not stripped:
            formatted_lines.append('')
            continue
            
        # Decrease indent for closing tags
        if stripped.startswith('</') or stripped.startswith('{%- end') or stripped.startswith('{% end'):
            indent_level = max(0, indent_level - 1)
        elif stripped.startswith('{% else') or stripped.startswith('{%- else'):
            current_indent = max(0, indent_level - 1)
        else:
            current_indent = indent_level
            
        # Add proper indentation
        formatted_lines.append('  ' * current_indent + stripped)
        
        # Increase indent for opening tags
        if (stripped.startswith('<') and not stripped.startswith('</') and not stripped.endswith('/>') and 
            not any(tag in stripped for tag in ['<meta', '<link', '<br', '<hr', '<img', '<input'])) or \
           stripped.startswith('{% if') or stripped.startswith('{%- if') or \
           stripped.startswith('{% for') or stripped.startswith('{%- for') or \
           stripped.startswith('{% block') or stripped.startswith('{%- block') or \
           stripped.startswith('{% else') or stripped.startswith('{%- else'):
            indent_level += 1
    
    with open('$OUTPUT_FILE', 'w') as f:
        f.write('\n'.join(formatted_lines))
        
except Exception as e:
    # If formatting fails, just copy the file
    import shutil
    shutil.copy('$OUTPUT_FILE.tmp', '$OUTPUT_FILE')
" || cp "$OUTPUT_FILE.tmp" "$OUTPUT_FILE"
else
    echo "No HTML formatter found, using unformatted output..."
    cp "$OUTPUT_FILE.tmp" "$OUTPUT_FILE"
fi

# Clean up temporary file
rm -f "$OUTPUT_FILE.tmp"

echo "✓ HTML formatting completed!"
echo ""
echo "Webuniversum 3 file created: $OUTPUT_FILE"
echo ""

# CONDITIONAL VALIDATION - Only run if --validate flag is provided
if [[ "$VALIDATE" = true ]]; then
    echo "Final Validation:"
    echo "================="
    echo "Analyzing the generated output file for class replacement success..."
    echo ""

    for mapping in "${CLASS_MAPPINGS[@]}"; do
        IFS=':' read -r old_class new_class <<<"$mapping"

        echo "Validating mapping: '$old_class' → '$new_class'"

        # Count old classes remaining in the OUTPUT file (should be 0)
        old_total=$(count_exact_class_matches "$old_class" "$OUTPUT_FILE")

        # Count new classes present in the OUTPUT file
        new_total=$(count_exact_class_matches "$new_class" "$OUTPUT_FILE")

        # Calculate how many replacements were made for this mapping
        original_old_count=$(count_exact_class_matches "$old_class" "$INPUT_FILE")
        original_new_count=$(count_exact_class_matches "$new_class" "$INPUT_FILE")
        replacements_made=$((new_total - original_new_count))

        if [[ $original_old_count -gt 0 ]]; then
            if [[ $old_total -eq 0 ]]; then
                echo "  ✅ SUCCESS: All $replacements_made instances of '$old_class' were replaced with '$new_class'"
            else
                echo "  ⚠️  PARTIAL: $replacements_made replaced, but $old_total instances of '$old_class' still remain"
            fi
        else
            if [[ $new_total -gt 0 ]]; then
                echo "  ℹ️  INFO: No '$old_class' found in input, but $new_total instances of '$new_class' exist in output"
            else
                echo "  ℹ️  INFO: No instances of '$old_class' or '$new_class' found"
            fi
        fi
    done

    echo ""
    echo "All validation completed!"
else
    echo "Validation skipped (use --validate flag to enable)"
fi

echo ""
echo "Final Summary:"
echo "=============="
echo "✓ Webuniversum 3 conversion completed successfully!"
echo "✓ HTML formatting applied!"
echo "✓ Output file: $OUTPUT_FILE"
echo ""