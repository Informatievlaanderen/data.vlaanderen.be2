#!/bin/bash

# Script to remove all <link> tags from an HTML file and add specific new ones
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

echo "Replacing <link> tags in '$INPUT_FILE'..."

# Create a temporary file for processing
TMP_FILE=$(mktemp)

# Create a temporary Perl script with the replacement logic
PERL_SCRIPT=$(mktemp)

# New links to add - pass as an environment variable to Perl
# If more webunversum links are needed, add more options here!
export NEW_LINKS='    <link rel="stylesheet" href="https://data.vlaanderen.be/assets/css/index.css"/>
    <link rel="icon" sizes="192x192" href="https://data.vlaanderen.be/assets/favicon/icons/icon-highres-precomposed.png"/>
    <link rel="apple-touch-icon" href="https://data.vlaanderen.be/assets/favicon/icons/apple-touch-icon.png"/>
    <link rel="apple-touch-icon" sizes="76x76" href="https://data.vlaanderen.be/assets/favicon/icons/icon-highres-precomposed.png"/>
    <link rel="apple-touch-icon" sizes="120x120" href="https://data.vlaanderen.be/assets/favicon/icons/icon-highres-precomposed.png"/>
    <link rel="apple-touch-icon" sizes="152x152" href="https://data.vlaanderen.be/assets/favicon/icons/icon-highres-precomposed.png"/>'

# Write the Perl script to a file for cleaner execution
cat >"$PERL_SCRIPT" <<'EOL'
use strict;
use warnings;

# Read the entire file content
local $/;
my $content = <>;

# Count original link tags
my $orig_count = () = $content =~ /<link\s+[^>]*?(?:>|(?:\/>\s*))/gs;

# Remove all <link> tags
$content =~ s/<link\s+[^>]*?(?:>|(?:\/>\s*))//gs;

# Insert new links after the viewport meta tag
$content =~ s/(<meta[^>]*?name="viewport"[^>]*?>)/$1\n$ENV{NEW_LINKS}/i;

# Output the modified content
print $content;
EOL

# Run the Perl script
perl "$PERL_SCRIPT" "$INPUT_FILE" >"$TMP_FILE"

# Count how many tags were removed and added
ORIG_COUNT=$(grep -c "<link" "$INPUT_FILE" 2>/dev/null || echo 0)
NEW_COUNT=$(grep -c "<link" "$TMP_FILE" 2>/dev/null || echo 0)

# Ensure they're treated as integers by trimming whitespace
ORIG_COUNT=$(echo "$ORIG_COUNT" | tr -d '[:space:]')
NEW_COUNT=$(echo "$NEW_COUNT" | tr -d '[:space:]')

# Debug output
echo "Original link count: $ORIG_COUNT"
echo "New link count: $NEW_COUNT"
echo "Links removed: $ORIG_COUNT"
echo "Links added: 6"

# Output the result
if [ -n "$OUTPUT_FILE" ]; then
    mv "$TMP_FILE" "$OUTPUT_FILE"
    echo "Done! Output written to '$OUTPUT_FILE'"
else
    cat "$TMP_FILE"
    rm "$TMP_FILE"
    echo "Done!"
fi

# Clean up temporary files
rm -f "$PERL_SCRIPT"

echo "Process completed successfully."
