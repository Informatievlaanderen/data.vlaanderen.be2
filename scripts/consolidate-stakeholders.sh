#!/bin/bash
# filepath: consolidate-stakeholders.sh
# THIS SCRIPT NEEDS TO BE RAN IN THE ROOT OF A GENERATED REPOSITORY
# THIS COULD BE EXTENDED TO CLONE THE GENERATED REPO HERE AND DO IT LIKE THAT

# Output file
OUTPUT_FILE="consolidated-stakeholders.csv"

# Temporary file for all records
TEMP_FILE=$(mktemp)

# Associative array to track seen emails
declare -A SEEN_EMAILS

# Header
echo "Voornaam;Naam;E-mail;Affiliatie;Website" > "$OUTPUT_FILE"

# Find all stakeholders.csv and stakeholders.json files
find . -type f \( -name "stakeholders.csv" -o -name "stakeholders.json" \) | while read -r file; do
  echo "Processing: $file"
  
  if [[ "$file" == *.csv ]]; then
    # Skip header and process CSV (skip first line)
    tail -n +2 "$file" | while IFS=';' read -r voornaam naam affiliatie email website rest; do
      # Trim whitespace and skip empty emails
      email=$(echo "$email" | xargs)
      if [[ -n "$email" && "$email" != "E-mail" ]]; then
        echo "$voornaam;$naam;$email;$affiliatie;$website"
      fi
    done >> "$TEMP_FILE"
  
  elif [[ "$file" == *.json ]]; then
    # Parse JSON with nested structure (contributors, authors, editors arrays)
    # Extract from all three arrays and convert to CSV format
    jq -r '
      ((.contributors // []) + (.authors // []) + (.editors // [])) |
      .[] |
      "\(.firstName);\(.lastName);\(.email);\(.affiliation.affiliationName // "");\(.affiliation.homepage // "")"
    ' "$file" 2>/dev/null | while read -r line; do
      if [[ -n "$line" && "$line" != ";;" ]]; then
        email=$(echo "$line" | cut -d';' -f3)
        # Skip invalid entries (empty emails or URLs as emails)
        if [[ -n "$email" && ! "$email" =~ ^https?:// ]]; then
          echo "$line"
        fi
      fi
    done >> "$TEMP_FILE"
  fi
done

# Deduplicate by email (3rd field) - keep first occurrence
if [[ -f "$TEMP_FILE" ]]; then
  awk -F';' '
    !seen[tolower($3)]++ {
      print
    }
  ' "$TEMP_FILE" | sort >> "$OUTPUT_FILE"
  
  rm "$TEMP_FILE"
  
  # Count unique stakeholders
  TOTAL=$(tail -n +2 "$OUTPUT_FILE" | wc -l)
  echo ""
  echo "✓ Consolidated $TOTAL unique stakeholders to: $OUTPUT_FILE"
else
  echo "✗ No stakeholder files found"
fi