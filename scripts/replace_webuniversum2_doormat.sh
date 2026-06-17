#!/bin/bash

# Script to replace old Webuniversum 2 doormat markup with Webuniversum 3 markup
# Usage: ./replace_webuniversum2_doormat.sh input_file

set -e

if [ $# -lt 1 ]; then
    echo "Usage: $0 input_file"
    echo "  The input file will be modified in place"
    exit 1
fi

INPUT_FILE="$1"

if [ ! -f "$INPUT_FILE" ]; then
    echo "Error: Input file '$INPUT_FILE' does not exist."
    exit 1
fi

echo "Doormat Component Replacement Script (Webuniversum 2 -> 3)"
echo "==========================================================="
echo "Input file: $INPUT_FILE"
echo "Modifying file in place..."
echo ""

TMP_FILE=$(mktemp)
TMP_LOG_FILE=$(mktemp)

echo "Converting doormat components..."

cat > temp_doormat_replace.pl <<'EOF'
use strict;
use warnings;

local $/;
my $content = <>;
my $doormat_replacements = 0;

$content =~ s{
    (^([ \t]*)<a\b([^>]*\bclass\s*=\s*["'][^"']*\bvl-doormat\b[^"']*["'][^>]*)>)\s*
    <div\s+class\s*=\s*["']vl-doormat__title["']\s*>\s*(.*?)\s*</div>\s*
    <span\s+class\s*=\s*["']vl-doormat__text["']\s*>\s*(.*?)\s*</span>\s*
    </a>
}{
    # Copy outer captures first; nested regexes below would otherwise overwrite $1..$n.
    my ($anchor_indent, $attrs, $title, $text) = ($2, $3, $4, $5);

    my $href = "#";
    if ($attrs =~ /\bhref\s*=\s*(["'])(.*?)\1/i) {
        $href = $2;
    }

    $title =~ s/^\s+|\s+$//g;
    $text =~ s/^\s+|\s+$//g;

    $doormat_replacements++;

    $anchor_indent . qq{<a class="vl-doormat js-vl-equal-height" href="$href">\n} .
    $anchor_indent . qq{  <div class="vl-doormat__content">\n} .
    $anchor_indent . qq{    <span class="vl-doormat__content__arrow" aria-hidden="true"></span>\n} .
    $anchor_indent . qq{    <h2 class="vl-doormat__title" data-vl-clamp="2">$title</h2>\n} .
    $anchor_indent . qq{    <div class="vl-doormat__text" data-vl-clamp="3">$text</div>\n} .
    $anchor_indent . qq{  </div>\n} .
    $anchor_indent . qq{</a>};
}egmsx;

print $content;
print STDERR "DOORMAT_COUNT:$doormat_replacements\n";
EOF

echo "Processing doormat replacements..."
perl temp_doormat_replace.pl "$INPUT_FILE" > "$TMP_FILE" 2> "$TMP_LOG_FILE"
REPLACEMENT_OUTPUT=$(cat "$TMP_LOG_FILE")

rm -f temp_doormat_replace.pl
rm -f "$TMP_LOG_FILE"

DOORMAT_COUNT=$(echo "$REPLACEMENT_OUTPUT" | grep "DOORMAT_COUNT:" | cut -d':' -f2 | tr -d ' ' || echo "0")
DOORMAT_COUNT=${DOORMAT_COUNT:-0}

mv "$TMP_FILE" "$INPUT_FILE"

echo "Doormat conversion completed!"
echo ""
echo "Summary:"
echo "========"
echo "Total doormat conversions: $DOORMAT_COUNT"
echo "File modified: $INPUT_FILE"
echo ""
echo "Process completed successfully!"
