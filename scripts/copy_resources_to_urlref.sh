#!/bin/bash

# Copy generated artefacts (context, shacl, rdf, swagger) for publication points
# to <urlref>/resources when enabled through the publication point flag.
#
# Args:
#   1) configuration directory (e.g. config)
#   2) generated repository directory

CONFIGDIR=$1
GENERATEDDIR=$2

if [ -z "$CONFIGDIR" ] || [ -z "$GENERATEDDIR" ]; then
    echo "Usage: $0 <config-dir> <generated-dir>"
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
