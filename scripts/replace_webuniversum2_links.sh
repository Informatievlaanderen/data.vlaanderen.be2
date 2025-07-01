#!/bin/bash

# Script to remove all <link>, <meta>, and specific <script> tags from an HTML file and add specific new ones
# Usage: ./replace_webuniversum2_links.sh input.html [output.html]

set -e

# Display usage if no arguments provided
if [ $# -lt 1 ]; then
    echo "Usage: $0 input_file [output_file]"
    echo "  If output_file is not specified, the result will be printed to stdout"
    exit 1
fi

INPUT_FILE="$1"
OUTPUT_FILE="$2"

# Check if input file exists
if [ ! -f "$INPUT_FILE" ]; then
    echo "Error: Input file '$INPUT_FILE' does not exist."
    exit 1
fi

echo "Replacing <link>, <meta>, and <script> tags in '$INPUT_FILE'..."

# Create a temporary file for processing
TMP_FILE=$(mktemp)

# Create a temporary Perl script with the replacement logic
PERL_SCRIPT=$(mktemp)

# New links to add - pass as an environment variable to Perl
# If more webuniversum links are needed, add more options here!
export NEW_LINKS='
    <link rel="stylesheet" href="https://data.vlaanderen.be/assets/css/index.css"/>
    <link rel="icon" sizes="192x192" href="https://data.vlaanderen.be/assets/favicon/icons/icon-highres-precomposed.png"/>
    <link rel="apple-touch-icon" href="https://data.vlaanderen.be/assets/favicon/icons/apple-touch-icon.png"/>
    <link rel="apple-touch-icon" sizes="76x76" href="https://data.vlaanderen.be/assets/favicon/icons/icon-highres-precomposed.png"/>
    <link rel="apple-touch-icon" sizes="120x120" href="https://data.vlaanderen.be/assets/favicon/icons/icon-highres-precomposed.png"/>
    <link rel="apple-touch-icon" sizes="152x152" href="https://data.vlaanderen.be/assets/favicon/icons/icon-highres-precomposed.png"/>
'

# New meta tags to add - pass as an environment variable to Perl
export NEW_META_TAGS='
    <meta http-equiv="Content-Type" content="text/html; charset=UTF-8"/>
    <meta http-equiv="X-UA-Compatible" content="IE=edge,chrome=1"/>
    <meta name="viewport" content="width=device-width, initial-scale=1"/>
    <meta name="msapplication-square70x70logo" content="https://data.vlaanderen.be/assets/favicon/icons/tile-small.png"/>
    <meta name="msapplication-square150x150logo" content="https://data.vlaanderen.be/assets/favicon/icons/tile-medium.png"/>
    <meta name="msapplication-wide310x150logo" content="https://data.vlaanderen.be/assets/favicon/icons/tile-wide.png"/>
    <meta name="msapplication-square310x310logo" content="https://data.vlaanderen.be/assets/favicon/icons/tile-large.png"/>
    <meta name="msapplication-TileColor" content="#FFE615"/>
'

# New script tags to add - pass as an environment variable to Perl
export NEW_SCRIPTS='
    <script src="https://data.vlaanderen.be/assets/dist/core.js"></script>
    <script src="https://data.vlaanderen.be/assets/dist/tooltip.js"></script>
'

# Write the Perl script to a file for cleaner execution
cat >"$PERL_SCRIPT" <<'EOL'
use strict;
use warnings;

# Read the entire file content
local $/;
my $content = <>;

# Count original tags
my $orig_link_count = () = $content =~ /<link\s+[^>]*?(?:>|(?:\/>\s*))/gs;
my $orig_meta_count = () = $content =~ /<meta\s+[^>]*?(?:>|(?:\/>\s*))/gs;
my $orig_script_count = () = $content =~ /<script\s+[^>]*?src\s*=\s*["'][^"']*vlaanderen-ui\.js["'][^>]*?><\/script>/gs;

# Remove all <link> tags
$content =~ s/<link\s+[^>]*?(?:>|(?:\/>\s*))//gs;

# Remove all <meta> tags
$content =~ s/<meta\s+[^>]*?(?:>|(?:\/>\s*))//gs;

# Remove specific vlaanderen-ui.js script tags
$content =~ s/<script\s+[^>]*?src\s*=\s*["'][^"']*vlaanderen-ui\.js["'][^>]*?><\/script>\s*//gs;

# Find the <head> tag and insert new meta tags and links after it
if ($content =~ s/(<head[^>]*>)/$1\n$ENV{NEW_META_TAGS}\n$ENV{NEW_LINKS}/i) {
    # Silently insert new meta and link tags after <head>
} else {
    # Fallback: try to find any existing <title> tag and insert before it
    if ($content =~ s/(<title[^>]*>)/$ENV{NEW_META_TAGS}\n$ENV{NEW_LINKS}\n$1/i) {
        # Silently insert new meta and link tags before <title>
    } else {
        # Could not find suitable insertion point for new meta/link tags
    }
}

# Find the closing </body> tag and insert new script tags before it
if ($content =~ s/(<\/body>)/$ENV{NEW_SCRIPTS}\n$1/i) {
    # Silently insert new script tags before </body>
} else {
    # Fallback: try to find closing </html> tag and insert before it
    if ($content =~ s/(<\/html>)/$ENV{NEW_SCRIPTS}\n$1/i) {
        # Silently insert new script tags before </html>
    } else {
        # Could not find suitable insertion point for new script tags
    }
}

# Output the modified content
print $content;
EOL

# Run the Perl script and capture the counts from stderr
REPLACEMENT_OUTPUT=$(perl "$PERL_SCRIPT" "$INPUT_FILE" >"$TMP_FILE" 2>&1)

# Count how many tags were removed and added
ORIG_LINK_COUNT=$(grep -c "<link" "$INPUT_FILE" 2>/dev/null || echo 0)
ORIG_META_COUNT=$(grep -c "<meta" "$INPUT_FILE" 2>/dev/null || echo 0)
ORIG_SCRIPT_COUNT=$(grep -c "vlaanderen-ui\.js" "$INPUT_FILE" 2>/dev/null || echo 0)
NEW_LINK_COUNT=$(grep -c "<link" "$TMP_FILE" 2>/dev/null || echo 0)
NEW_META_COUNT=$(grep -c "<meta" "$TMP_FILE" 2>/dev/null || echo 0)
NEW_SCRIPT_COUNT=$(grep -c "data\.vlaanderen\.be/assets/dist/" "$TMP_FILE" 2>/dev/null || echo 0)

# Ensure they're treated as integers by trimming whitespace
ORIG_LINK_COUNT=$(echo "$ORIG_LINK_COUNT" | tr -d '[:space:]')
ORIG_META_COUNT=$(echo "$ORIG_META_COUNT" | tr -d '[:space:]')
ORIG_SCRIPT_COUNT=$(echo "$ORIG_SCRIPT_COUNT" | tr -d '[:space:]')
NEW_LINK_COUNT=$(echo "$NEW_LINK_COUNT" | tr -d '[:space:]')
NEW_META_COUNT=$(echo "$NEW_META_COUNT" | tr -d '[:space:]')
NEW_SCRIPT_COUNT=$(echo "$NEW_SCRIPT_COUNT" | tr -d '[:space:]')

# Debug output
echo "Tag replacement summary:"
echo "========================"
echo "Link tags:"
echo "  Original: $ORIG_LINK_COUNT"
echo "  New: $NEW_LINK_COUNT"
echo "  Removed: $ORIG_LINK_COUNT"
echo "  Added: $NEW_LINK_COUNT"
echo ""
echo "Meta tags:"
echo "  Original: $ORIG_META_COUNT"
echo "  New: $NEW_META_COUNT"
echo "  Removed: $ORIG_META_COUNT"
echo "  Added: $NEW_META_COUNT"
echo ""
echo "Script tags:"
echo "  Original vlaanderen-ui.js: $ORIG_SCRIPT_COUNT"
echo "  New data.vlaanderen.be scripts: $NEW_SCRIPT_COUNT"
echo "  Removed: $ORIG_SCRIPT_COUNT"
echo "  Added: $NEW_SCRIPT_COUNT"
echo ""

# Show Perl script output for debugging
echo "Processing details:"
echo "$REPLACEMENT_OUTPUT"
echo ""

# Output the result
if [ -n "$OUTPUT_FILE" ]; then
    mv "$TMP_FILE" "$OUTPUT_FILE"
    echo "✓ Output written to '$OUTPUT_FILE'"
else
    cat "$TMP_FILE"
    rm "$TMP_FILE"
    echo "✓ Output printed to stdout"
fi

# Clean up temporary files
rm -f "$PERL_SCRIPT"

echo "✓ Process completed successfully!"
echo ""
echo "Summary:"
echo "========"
echo "Total tags replaced: $((ORIG_LINK_COUNT + ORIG_META_COUNT + ORIG_SCRIPT_COUNT)) → $((NEW_LINK_COUNT + NEW_META_COUNT + NEW_SCRIPT_COUNT))"
