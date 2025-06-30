#!/bin/bash

# Script to replace old tooltip attributes with new Webuniversum 3 tooltip format
# and replace .tooltip CSS class with .vl-tooltip containing only max-width
# Usage: ./replace_webuniversum_tooltip.sh input_file

set -e

# Display usage if no arguments provided
if [ $# -lt 1 ]; then
    echo "Usage: $0 input_file"
    echo "  The input file will be modified in place"
    exit 1
fi

INPUT_FILE="$1"

# Check if input file exists
if [ ! -f "$INPUT_FILE" ]; then
    echo "Error: Input file '$INPUT_FILE' does not exist."
    exit 1
fi

echo "Tooltip Attribute & CSS Replacement Script (Webuniversum 2 → 3)"
echo "================================================================="
echo "Input file: $INPUT_FILE"
echo "Modifying file in place..."
echo ""

# Create a temporary file for processing
TMP_FILE=$(mktemp)

echo "Converting tooltip attributes and CSS..."

# Create a Perl script to handle the replacements
cat > temp_tooltip_replace.pl <<'EOF'
use strict;
use warnings;

my $total_tooltip_replacements = 0;
my $css_replacements = 0;
my $in_tooltip_css = 0;
my $brace_count = 0;
my $indent = "";

while (my $line = <>) {
    my $original_line = $line;
    
    # Handle .tooltip CSS class deletion and replacement
    if ($line =~ /^(\s*)\.tooltip\s*\{/) {
        $in_tooltip_css = 1;
        $indent = $1; # Capture the indentation
        $brace_count = 1;
        
        # Check if the opening and closing braces are on the same line
        my $open_braces = () = $line =~ /\{/g;
        my $close_braces = () = $line =~ /\}/g;
        $brace_count = $open_braces - $close_braces;
        
        if ($brace_count == 0) {
            # Single line CSS rule, replace immediately
            print $indent . ".vl-tooltip {\n";
            print $indent . "  max-width: 128rem;\n";
            print $indent . "}\n";
            $css_replacements++;
            $in_tooltip_css = 0;
        } else {
            # Multi-line CSS rule, start replacement
            print $indent . ".vl-tooltip {\n";
        }
        next;
    }
    
    if ($in_tooltip_css) {
        # Count braces to know when we've reached the end of the CSS rule
        my $open_braces = () = $line =~ /\{/g;
        my $close_braces = () = $line =~ /\}/g;
        $brace_count += $open_braces - $close_braces;
        
        if ($brace_count <= 0) {
            # End of .tooltip CSS rule found, replace with simplified version
            print $indent . "  max-width: 128rem;\n";
            print $indent . "}\n";
            $css_replacements++;
            $in_tooltip_css = 0;
        }
        # Skip this line as we're inside the .tooltip CSS rule being deleted
        next;
    }
    
    # Replace tooltip attributes in anchor tags - more flexible pattern
    if ($line =~ /data-toggle\s*=\s*["']tooltip["']/) {
        my $line_modified = 0;
        
        # Add js-vl-tooltip class if class attribute exists
        if ($line =~ /class\s*=\s*["']([^"']*?)["']/) {
            my $existing_classes = $1;
            if ($existing_classes !~ /\bjs-vl-tooltip\b/) {
                $line =~ s/(class\s*=\s*["'])([^"']*?)(["'])/$1$2 js-vl-tooltip$3/;
                $line_modified = 1;
            }
        } else {
            # No class attribute exists, add it before the data-toggle
            $line =~ s/(\s+)data-toggle/$1class="js-vl-tooltip" data-toggle/;
            $line_modified = 1;
        }
        
        # Remove data-toggle="tooltip"
        $line =~ s/\s*data-toggle\s*=\s*["']tooltip["']//g;
        $line_modified = 1;
        
        # Replace data-content with data-vl-tooltip-content
        if ($line =~ s/data-content\s*=/data-vl-tooltip-content=/g) {
            $line_modified = 1;
        }
        
        # Replace data-placement with data-vl-tooltip-placement
        if ($line =~ s/data-placement\s*=/data-vl-tooltip-placement=/g) {
            $line_modified = 1;
        }
        
        if ($line_modified) {
            $total_tooltip_replacements++;
        }
    }
    
    print $line;
}

print STDERR "TOOLTIP_COUNT:$total_tooltip_replacements\n";
print STDERR "CSS_COUNT:$css_replacements\n";
EOF

# Run the Perl script and capture the replacement count
echo "Processing tooltip attribute and CSS replacements..."
REPLACEMENT_OUTPUT=$(perl temp_tooltip_replace.pl "$INPUT_FILE" > "$TMP_FILE" 2>&1)

# Clean up Perl script
rm -f temp_tooltip_replace.pl

# Extract the replacement counts
TOOLTIP_COUNT=$(echo "$REPLACEMENT_OUTPUT" | grep "TOOLTIP_COUNT:" | cut -d':' -f2 | tr -d ' ' || echo "0")
CSS_COUNT=$(echo "$REPLACEMENT_OUTPUT" | grep "CSS_COUNT:" | cut -d':' -f2 | tr -d ' ' || echo "0")

# Ensure we have numeric values
TOOLTIP_COUNT=${TOOLTIP_COUNT:-0}
CSS_COUNT=${CSS_COUNT:-0}

# Count actual changes made by comparing files
if [ -f "$INPUT_FILE" ] && [ -f "$TMP_FILE" ]; then
    # Count CSS .tooltip occurrences in original vs output
    ORIGINAL_TOOLTIP_CSS=$(grep -c "\.tooltip\s*{" "$INPUT_FILE" || echo "0")
    NEW_VL_TOOLTIP_CSS=$(grep -c "\.vl-tooltip\s*{" "$TMP_FILE" || echo "0")
    
    # Count data-toggle="tooltip" in original
    ORIGINAL_DATA_TOGGLE=$(grep -c 'data-toggle.*=.*["'\'']tooltip["'\'']' "$INPUT_FILE" || echo "0")
    NEW_JS_VL_TOOLTIP=$(grep -c 'js-vl-tooltip' "$TMP_FILE" || echo "0")
    
    echo "Debug - File analysis:"
    echo "Original .tooltip CSS classes: $ORIGINAL_TOOLTIP_CSS"
    echo "New .vl-tooltip CSS classes: $NEW_VL_TOOLTIP_CSS"
    echo "Original data-toggle=\"tooltip\": $ORIGINAL_DATA_TOGGLE"
    echo "New js-vl-tooltip classes: $NEW_JS_VL_TOOLTIP"
    echo ""
    
    # Use file analysis results if Perl counts are 0
    if [ "$CSS_COUNT" -eq 0 ] && [ "$ORIGINAL_TOOLTIP_CSS" -gt 0 ] && [ "$NEW_VL_TOOLTIP_CSS" -gt 0 ]; then
        CSS_COUNT=$ORIGINAL_TOOLTIP_CSS
    fi
    
    if [ "$TOOLTIP_COUNT" -eq 0 ] && [ "$ORIGINAL_DATA_TOGGLE" -gt 0 ]; then
        TOOLTIP_COUNT=$ORIGINAL_DATA_TOGGLE
    fi
fi

# Overwrite the original file with the modified content
mv "$TMP_FILE" "$INPUT_FILE"

echo "✓ Tooltip attribute and CSS conversion completed!"
echo ""
echo "Summary:"
echo "========"
echo "Total tooltip attribute conversions: $TOOLTIP_COUNT"
echo "Total .tooltip CSS deletions and .vl-tooltip CSS additions: $CSS_COUNT"
echo "File modified: $INPUT_FILE"
echo ""

echo "Process completed successfully!"