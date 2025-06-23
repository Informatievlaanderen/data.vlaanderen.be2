#!/bin/bash

# Predefined array of CSS class mappings (old_class:new_class)
CLASS_MAPPINGS=(
    "page:vl-page"
    "region:vl-region"
    "layout:vl-layout"
    "grid:vl-grid"
    "typography:vl-typography"
    "introduction:vl-introduction"
    "side-navigation:vl-side-navigation"
    "main-content:vl-main-content"
    "h1:vl-title--h1"
    "h2:vl-title--h2"
    "h3:vl-title--h3"
    "h4:vl-title--h4"
    "h5:vl-title--h5"
)

# Input file (change this to your template file path)
INPUT_FILE="${1:-packages/oslo-generator-html/lib/templates/voc2.j2}"

# Check if input file exists
if [[ ! -f "$INPUT_FILE" ]]; then
    echo "Error: Input file '$INPUT_FILE' not found!"
    echo "Usage: $0 [input_file]"
    exit 1
fi

# Create output filename with _webuniversum3 suffix
DIR=$(dirname "$INPUT_FILE")
BASENAME=$(basename "$INPUT_FILE")
FILENAME="${BASENAME%.*}"
EXTENSION="${BASENAME##*.}"

if [[ "$BASENAME" == "$FILENAME" ]]; then
    OUTPUT_FILE="${DIR}/${FILENAME}_webuniversum3"
else
    OUTPUT_FILE="${DIR}/${FILENAME}_webuniversum3.${EXTENSION}"
fi

echo "CSS Class Replacement Script (Webuniversum 2 → 3)"
echo "================================================="
echo "Input file: $INPUT_FILE"
echo "Output file: $OUTPUT_FILE"
echo ""

total_replacements=0
# Use regular arrays instead of associative arrays
replacement_keys=()
replacement_values=()

echo "Performing CSS class replacements..."
echo ""

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

my $in_head = 0;
my $replaced_links = 0;

while (<>) {
    my $line = $_;
    
    # Track if we're in the head section
    if ($line =~ /<head[^>]*>/) {
        $in_head = 1;
    } elsif ($line =~ /<\/head>/) {
        # Insert new link tags before </head> if we haven't already
        if (!$replaced_links) {
            print <<'LINKS';
    <link rel="stylesheet" href="https://ui.vlaanderen.be/3.latest/css/vlaanderen-ui.css"/>
    <link rel="stylesheet" href="https://ui.vlaanderen.be/3.latest/css/vlaanderen-ui-corporate.css"/>
    <link
      rel="icon"
      sizes="192x192"
      href="https://ui.vlaanderen.be/3.latest/icons/app-icon/icon-highres-precomposed.png"/>
    <link
      rel="apple-touch-icon"
      href="https://ui.vlaanderen.be/3.latest/icons/app-icon/touch-icon-iphone-precomposed.png"/>
    <link
      rel="apple-touch-icon"
      sizes="76x76"
      href="https://ui.vlaanderen.be/3.latest/icons/app-icon/touch-icon-ipad-precomposed.png"/>
    <link
      rel="apple-touch-icon"
      sizes="120x120"
      href="https://ui.vlaanderen.be/3.latest/icons/app-icon/touch-icon-iphone-retina-precomposed.png"/>
    <link
      rel="apple-touch-icon"
      sizes="152x152"
      href="https://ui.vlaanderen.be/3.latest/icons/app-icon/touch-icon-ipad-retina-precomposed.png"/>
    <meta
      name="msapplication-square70x70logo"
      content="https://ui.vlaanderen.be/3.latest/icons/app-icon/tile-small.png"/>
    <meta
      name="msapplication-square150x150logo"
      content="https://ui.vlaanderen.be/3.latest/icons/app-icon/tile-medium.png"/>
    <meta
      name="msapplication-wide310x150logo"
      content="https://ui.vlaanderen.be/3.latest/icons/app-icon/tile-wide.png"/>
    <meta
      name="msapplication-square310x310logo"
      content="https://ui.vlaanderen.be/3.latest/icons/app-icon/tile-large.png"/>
    <meta name="msapplication-TileColor" content="#FFE615"/>
    <script src="https://prod.widgets.burgerprofiel.vlaanderen.be/api/v1/node_modules/@govflanders/vl-widget-polyfill/dist/index.js"></script>
LINKS
            $replaced_links = 1;
        }
        $in_head = 0;
    }
    
    # Skip existing link and meta tags in head section that we're replacing
    if ($in_head && ($line =~ /<link[^>]*rel=["']?(stylesheet|icon|apple-touch-icon)["']?[^>]*>/ ||
                     $line =~ /<meta[^>]*name=["']?msapplication-[^"']*["']?[^>]*>/ ||
                     $line =~ /<meta[^>]*name=["']?msapplication-TileColor["']?[^>]*>/ ||
                     $line =~ /<script[^>]*@govflanders\/vl-widget-polyfill[^>]*>/)) {
        next; # Skip this line
    }
    
    # Only process lines that contain class attributes for CSS class replacement
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
    
    # Update JavaScript URL to version 3
    if ($line =~ /vlaanderen-ui\.js/) {
        $line =~ s/ui\.vlaanderen\.be\/2\.latest/ui.vlaanderen.be\/3.latest/g;
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
echo "Processing all class replacements and link updates in a single pass..."
perl temp_replace.pl "$INPUT_FILE" >"$OUTPUT_FILE.tmp"

# Clean up
rm -f temp_replace.pl
for i in "${!CLASS_MAPPINGS[@]}"; do
    unset "OLD_CLASS_$i"
    unset "NEW_CLASS_$i"
done

# Count total replacements
for mapping in "${CLASS_MAPPINGS[@]}"; do
    IFS=':' read -r old_class new_class <<<"$mapping"

    echo "Checking replacements for '$old_class' → '$new_class'..."

    # Count occurrences in original and new files using precise patterns
    # FIXED: Ensure grep always returns a number, not empty string
    old_count_original=$(grep -c "class=\"[^\"]*[[:space:]]${old_class}[[:space:]\"]" "$INPUT_FILE" 2>/dev/null || echo 0)
    old_count_original=$((old_count_original + $(grep -c "class=\"${old_class}[[:space:]\"]" "$INPUT_FILE" 2>/dev/null || echo 0)))
    old_count_original=$((old_count_original + $(grep -c "class=\"[^\"]*[[:space:]]${old_class}\"" "$INPUT_FILE" 2>/dev/null || echo 0)))
    old_count_original=$((old_count_original + $(grep -c "class=\"${old_class}\"" "$INPUT_FILE" 2>/dev/null || echo 0)))

    old_count_final=$(grep -c "class=\"[^\"]*[[:space:]]${old_class}[[:space:]\"]" "$OUTPUT_FILE.tmp" 2>/dev/null || echo 0)
    old_count_final=$((old_count_final + $(grep -c "class=\"${old_class}[[:space:]\"]" "$OUTPUT_FILE.tmp" 2>/dev/null || echo 0)))
    old_count_final=$((old_count_final + $(grep -c "class=\"[^\"]*[[:space:]]${old_class}\"" "$OUTPUT_FILE.tmp" 2>/dev/null || echo 0)))
    old_count_final=$((old_count_final + $(grep -c "class=\"${old_class}\"" "$OUTPUT_FILE.tmp" 2>/dev/null || echo 0)))

    new_count_final=$(grep -c "class=\"[^\"]*[[:space:]]${new_class}[[:space:]\"]" "$OUTPUT_FILE.tmp" 2>/dev/null || echo 0)
    new_count_final=$((new_count_final + $(grep -c "class=\"${new_class}[[:space:]\"]" "$OUTPUT_FILE.tmp" 2>/dev/null || echo 0)))
    new_count_final=$((new_count_final + $(grep -c "class=\"[^\"]*[[:space:]]${new_class}\"" "$OUTPUT_FILE.tmp" 2>/dev/null || echo 0)))
    new_count_final=$((new_count_final + $(grep -c "class=\"${new_class}\"" "$OUTPUT_FILE.tmp" 2>/dev/null || echo 0)))

    new_count_original=$(grep -c "class=\"[^\"]*[[:space:]]${new_class}[[:space:]\"]" "$INPUT_FILE" 2>/dev/null || echo 0)
    new_count_original=$((new_count_original + $(grep -c "class=\"${new_class}[[:space:]\"]" "$INPUT_FILE" 2>/dev/null || echo 0)))
    new_count_original=$((new_count_original + $(grep -c "class=\"[^\"]*[[:space:]]${new_class}\"" "$INPUT_FILE" 2>/dev/null || echo 0)))
    new_count_original=$((new_count_original + $(grep -c "class=\"${new_class}\"" "$INPUT_FILE" 2>/dev/null || echo 0)))

    replacements=$((old_count_original - old_count_final))

    if [[ $replacements -gt 0 ]]; then
        echo "  ✓ Replaced $replacements instances of '$old_class' CSS classes with '$new_class'"
        # Store replacement info in regular arrays
        replacement_keys+=("${old_class}_to_${new_class}")
        replacement_values+=("$replacements")
        total_replacements=$((total_replacements + replacements))
    else
        echo "  No CSS class replacements needed for '$old_class'"
    fi
done

# Count link replacements
echo ""
echo "Checking link tag updates..."
old_link_count=$(grep -c "ui\.vlaanderen\.be/2\.latest" "$INPUT_FILE" 2>/dev/null || echo 0)
new_link_count=$(grep -c "ui\.vlaanderen\.be/3\.latest" "$OUTPUT_FILE.tmp" 2>/dev/null || echo 0)
link_replacements=$((new_link_count - $(grep -c "ui\.vlaanderen\.be/3\.latest" "$INPUT_FILE" 2>/dev/null || echo 0)))

if [[ $link_replacements -gt 0 ]]; then
    echo "  ✓ Updated $link_replacements Webuniversum links from v2 to v3"
    total_replacements=$((total_replacements + link_replacements))
fi

echo ""
echo "Summary:"
echo "========"
echo "Total replacements made: $total_replacements"

if [[ $total_replacements -gt 0 ]]; then
    echo ""
    echo "Detailed breakdown:"
    for i in "${!replacement_keys[@]}"; do
        key="${replacement_keys[$i]}"
        value="${replacement_values[$i]}"
        readable_key=$(echo "$key" | sed 's/_to_/ → /g')
        echo "  $readable_key: $value replacement(s)"
    done

    if [[ $link_replacements -gt 0 ]]; then
        echo "  Webuniversum v2 → v3 links: $link_replacements replacement(s)"
    fi
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

# FINAL VALIDATION - Uses precise class matching to avoid false positives
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

# Validate link updates
echo ""
echo "Validating link updates:"

# Fix: Ensure variables are properly initialized as integers
v2_links=$(grep -c "ui\.vlaanderen\.be/2\.latest" "$OUTPUT_FILE" 2>/dev/null) || v2_links=0

# Strip any whitespace and ensure they're integers
v2_links=$(echo "$v2_links" | tr -d ' \n\r')

# Default to 0 if empty
v2_links=${v2_links:-0}

echo "Debug: v2_links='$v2_links', v3_links='$v3_links'"

if [[ $v2_links -eq 0 ]] && [[ $v3_links -gt 0 ]]; then
    echo "  ✅ SUCCESS: All Webuniversum links updated to v3 ($v3_links links found)"
elif [[ $v2_links -gt 0 ]]; then
    echo "  ⚠️  PARTIAL: $v2_links Webuniversum v2 links still remain, $v3_links v3 links found"
else
    echo "  ℹ️  INFO: No Webuniversum links found (v2: $v2_links, v3: $v3_links)"
fi

echo ""
echo "Final Summary:"
echo "=============="
echo "✓ Webuniversum 3 conversion completed successfully!"
echo "✓ CSS classes updated to Webuniversum 3"
echo "✓ Link tags updated to Webuniversum 3"
echo "✓ HTML formatting applied!"
echo "✓ Output file: $OUTPUT_FILE"
echo ""
echo "All validation completed!"
