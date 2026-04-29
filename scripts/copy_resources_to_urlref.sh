#!/bin/bash

# Copy generated artefacts (context, shacl, rdf, swagger) for publication points
# to <urlref>/resources when enabled through the publication point flag.
#
# Args:
#   1) configuration directory (e.g. config)
#   2) generated repository directory
#   3) workspace directory containing report4 (default: /tmp/workspace)

CONFIGDIR=$1
GENERATEDDIR=$2
WORKSPACEDIR=${3:-/tmp/workspace}

if [ -z "$CONFIGDIR" ] || [ -z "$GENERATEDDIR" ]; then
    echo "Usage: $0 <config-dir> <generated-dir> [workspace-dir]"
    exit 1
fi

if [ ! -f "$CONFIGDIR/config.json" ]; then
    echo "config.json not found in configuration directory: $CONFIGDIR"
    exit 1
fi

if [ ! -d "$GENERATEDDIR" ]; then
    echo "Generated directory not found: $GENERATEDDIR"
    exit 1
fi

if [ ! -d "$WORKSPACEDIR" ]; then
    echo "Workspace directory not found: $WORKSPACEDIR"
    exit 1
fi

copy_dir_if_exists() {
    local src_dir=$1
    local dst_dir=$2

    if [ -d "$src_dir" ] && [ "$(find "$src_dir" -mindepth 1 -maxdepth 1 | wc -l)" -ne 0 ]; then
        mkdir -p "$dst_dir"
        cp -R "$src_dir" "$dst_dir/"
        return 0
    fi

    return 1
}

fetch_external_jsonld() {
    local source_url=$1
    local target_dir=$2
    local normalized_url=${source_url%%#*}
    local target_file

    if [ -z "$normalized_url" ]; then
        return 1
    fi

    target_file=$(echo "$normalized_url" | sed -e 's|^https\?://||' -e 's|[^A-Za-z0-9._-]|_|g')
    target_file="$target_dir/${target_file}.jsonld"

    if [ -f "$target_file" ]; then
        return 0
    fi

    mkdir -p "$target_dir"

    if curl -L --fail --silent --show-error \
        -H 'Accept: application/ld+json, application/json;q=0.9, */*;q=0.1' \
        "$normalized_url" > "$target_file"; then
        echo "Fetched external JSON-LD: $normalized_url"
        return 0
    fi

    echo "Failed to fetch external JSON-LD: $normalized_url"
    rm -f "$target_file"
    return 1
}

fetch_external_vocabularies() {
    local urlref=$1
    local resources_dir=$2
    local report_dir="$WORKSPACEDIR/report4/${urlref#/}"
    local fetched_any=false

    if [ ! -d "$report_dir" ]; then
        echo "No intermediary report directory found for $urlref: $report_dir"
        return 1
    fi

    while IFS= read -r intermediary_file; do
        while IFS= read -r external_url; do
            if fetch_external_jsonld "$external_url" "$resources_dir/external"; then
                fetched_any=true
            fi
        done < <(
            jq -r '
                ..
                | objects
                | select(.scope? == "https://data.vlaanderen.be/id/concept/scope/External")
                | .assignedURI?
                | if type == "array" then .[] else . end
                | strings
                | select(test("^https?://"))
            ' "$intermediary_file" \
                | sed -e 's/#.*$//' \
                | grep -v 'data\.vlaanderen\.be' \
                | sort -u
        )
    done < <(find "$report_dir" -maxdepth 1 -name 'all-*.jsonld' -type f)

    if [ "$fetched_any" = "true" ]; then
        return 0
    fi

    if [ -d "$resources_dir/external" ] && [ ! "$(ls -A "$resources_dir/external")" ]; then
        rmdir "$resources_dir/external"
    fi

    return 1
}

process_publication_file() {
    local pubfile=$1

    jq -c '.[] | select(.urlref)' "$pubfile" | while IFS= read -r pubpoint; do
        URLREF=$(echo "$pubpoint" | jq -r '.urlref')
        COPY_RESOURCES=$(echo "$pubpoint" | jq -r '(.bundle // false)')

        if [ -z "$URLREF" ] || [ "$URLREF" = "null" ]; then
            continue
        fi

        URLREF_NO_LEADING=${URLREF#/}
        SOURCE_DIR="$GENERATEDDIR/$URLREF_NO_LEADING"
        RESOURCES_DIR="$SOURCE_DIR/resources"

        if [ "$COPY_RESOURCES" != "true" ]; then
            if [ -d "$RESOURCES_DIR" ]; then
                echo "Removing resources (bundle=false): $RESOURCES_DIR"
                rm -rf "$RESOURCES_DIR"
            fi
            continue
        fi

        if [ ! -d "$SOURCE_DIR" ]; then
            echo "Skipping bundle=true for missing urlref directory: $SOURCE_DIR"
            continue
        fi

        rm -rf "$RESOURCES_DIR"
        mkdir -p "$RESOURCES_DIR"

        copied_any=false

        if copy_dir_if_exists "$SOURCE_DIR/context" "$RESOURCES_DIR"; then
            copied_any=true
        fi

        if copy_dir_if_exists "$SOURCE_DIR/shacl" "$RESOURCES_DIR"; then
            copied_any=true
        fi

        if copy_dir_if_exists "$SOURCE_DIR/rdf" "$RESOURCES_DIR"; then
            copied_any=true
        fi

        if copy_dir_if_exists "$SOURCE_DIR/swagger" "$RESOURCES_DIR"; then
            copied_any=true
        fi

        if fetch_external_vocabularies "$URLREF" "$RESOURCES_DIR"; then
            copied_any=true
        fi

        if [ "$copied_any" = "true" ]; then
            echo "Copied resources for $URLREF -> $RESOURCES_DIR"
        else
            echo "bundle=true but no artefact directories found for $URLREF"
            rm -rf "$RESOURCES_DIR"
        fi
    done
}

PUBLICATIONPOINTSDIRS=$(jq -r '.publicationpoints | @sh' "$CONFIGDIR/config.json")
PUBLICATIONPOINTSDIRS=$(echo "$PUBLICATIONPOINTSDIRS" | sed -e "s/'//g")

for dir in $PUBLICATIONPOINTSDIRS; do
    echo "checking publication points in directory $CONFIGDIR/$dir"
    PUBLICATIONPOINTSFILES=$(find "$CONFIGDIR/$dir" -name '*.publication.json')
    for f in $PUBLICATIONPOINTSFILES; do
        echo "processing publication file: $f"
        process_publication_file "$f"
    done
done
