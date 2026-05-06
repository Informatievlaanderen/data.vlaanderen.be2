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
SCRIPTDIR=$(cd "$(dirname "$0")" && pwd)

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

# Install rdf-dereference into a stable temp location and expose it via NODE_PATH.
RDF_MODULES_DIR="/tmp/rdf-dereference-modules"
if [ ! -d "$RDF_MODULES_DIR/node_modules/rdf-dereference" ]; then
    mkdir -p "$RDF_MODULES_DIR"
    ( cd "$RDF_MODULES_DIR" && npm install --save-exact --no-save rdf-dereference 2>&1 )
fi
export NODE_PATH="$RDF_MODULES_DIR/node_modules"

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

copy_bundle_directory_files() {
    local source_dir=$1
    local bundle_dir=$2
    local resources_dir=$3
    local bundle_source
    
    if [ -z "$bundle_dir" ] || [ "$bundle_dir" = "null" ]; then
        return 1
    fi
    
    bundle_dir=${bundle_dir#/}
    bundle_source="$source_dir/$bundle_dir"
    
    if [ ! -d "$bundle_source" ]; then
        echo "bundleDirectory not found in thema-repo checkout: $bundle_source"
        return 1
    fi
    
    if [ "$(find "$bundle_source" -mindepth 1 | wc -l)" -eq 0 ]; then
        echo "bundleDirectory is empty, skipping: $bundle_source"
        return 1
    fi
    
    mkdir -p "$resources_dir"
    cp -R "$bundle_source"/. "$resources_dir/"
    echo "Copied bundleDirectory files from $bundle_source"
    return 0
}

fetch_external_jsonld() {
    local source_url=$1
    local target_dir=$2
    local normalized_url
    local target_file
    local tmp_file
    local headers_file
    local failed_cache
    
    normalize_namespace_url() {
        local raw_url=$1
        local base_url=${raw_url%%#*}

        # schema.org resources are fetched as-is without namespace normalization.
        if [[ "$raw_url" =~ ^https?://([A-Za-z0-9-]+\.)*schema\.org(/|$) ]]; then
            echo "$raw_url"
            return
        fi
        
        if [ -z "$base_url" ]; then
            echo ""
            return
        fi
        
        # Issue met w3C specs
        
        if [[ "$raw_url" == *"#"* ]]; then
            echo "$base_url"
            return
        fi
        
        # Preserve common namespace roots like .../ns unchanged.
        if [[ "$base_url" == */ns ]]; then
            echo "$base_url"
            return
        fi
        
        # Path-based namespace: remove the last path segment and keep a trailing slash.
        echo "${base_url%/*}/"
    }
    
    normalized_url=$(normalize_namespace_url "$source_url")
    
    if [ -z "$normalized_url" ]; then
        return 1
    fi
    
    target_file=$(echo "$normalized_url" | sed -e 's|^https\?://||' -e 's|[^A-Za-z0-9._-]|_|g')
    target_file="$target_dir/${target_file}"
    failed_cache="$target_dir/.failed_external_sources"
    
    if [ -f "$failed_cache" ] && grep -Fqx "$normalized_url" "$failed_cache"; then
        return 1
    fi
    
    if [ -f "$target_file" ]; then
        return 0
    fi
    
    mkdir -p "$target_dir"
    
    if node "$SCRIPTDIR/fetch_external_rdf.js" "$normalized_url" "$target_file"; then
        return 0
    fi

    # Fallback for namespace documents that only provide HTML (or other non-RDF content).
    if curl -fsSL "$normalized_url" -o "$target_file"; then
        if [ -s "$target_file" ]; then
            echo "Fetched external source as raw document: $normalized_url"
            return 0
        fi
        rm -f "$target_file"
    fi

    echo "Failed to fetch external source: $normalized_url"
    mkdir -p "$target_dir"
    touch "$failed_cache"
    if ! grep -Fqx "$normalized_url" "$failed_cache"; then
        echo "$normalized_url" >> "$failed_cache"
    fi
    rm -f "$target_file"
    return 1
}

fetch_external_vocabularies() {
    local urlref=$1
    local resources_dir=$2
    local report_dir="$WORKSPACEDIR/report4/${urlref#/}"
    local fetched_any=false
    local seen_urls_file
    
    if [ ! -d "$report_dir" ]; then
        echo "No intermediary report directory found for $urlref: $report_dir"
        return 1
    fi
    
    seen_urls_file=$(mktemp)
    
    while IFS= read -r intermediary_file; do
        while IFS= read -r external_url; do
            if grep -Fqx "$external_url" "$seen_urls_file"; then
                continue
            fi
            echo "$external_url" >> "$seen_urls_file"
            if fetch_external_jsonld "$external_url" "$resources_dir/ontologies"; then
                fetched_any=true
            fi
            done < <(
            jq -r '
                ..
                | objects
                | .assignedURI?
                | if type == "array" then .[] else . end
                | strings
            ' "$intermediary_file" \
            | sort -u
        )
    done < <(find "$report_dir" -maxdepth 1 -name 'all-*.jsonld' -type f)
    
    rm -f "$seen_urls_file"
    
    if [ "$fetched_any" = "true" ]; then
        return 0
    fi
    
    if [ -d "$resources_dir/ontologies" ] && [ ! "$(ls -A "$resources_dir/ontologies")" ]; then
        rmdir "$resources_dir/ontologies"
    fi
    
    return 1
}

write_bundle_report() {
    local urlref=$1
    local copied_any=$2
    local resources_dir=$3
    local report_dir="$WORKSPACEDIR/report4/${urlref#/}"
    local report_file="$report_dir/bundle.report.md"
    local failed_cache="$resources_dir/ontologies/.failed_external_sources"
    
    mkdir -p "$report_dir"
    
    {
        echo "#||# bundling for $urlref"
        echo "#||# ----------------------"
        if [ "$copied_any" = "true" ]; then
            echo "INFO: resources copied to ${resources_dir}"
        else
            echo "warning: bundle=true but no resources were copied"
        fi
        
        if [ -f "$failed_cache" ] && [ -s "$failed_cache" ]; then
            while IFS= read -r failed_url; do
                echo "error: failed to fetch external source ${failed_url}"
            done < "$failed_cache"
        fi
    } > "$report_file"
}

process_publication_file() {
    local pubfile=$1
    
    jq -c 'if type == "array" then .[] else . end | select(.urlref)' "$pubfile" | while IFS= read -r pubpoint; do
        URLREF=$(echo "$pubpoint" | jq -r '.urlref')
        COPY_RESOURCES=$(echo "$pubpoint" | jq -r '(.bundle // false)')
        BUNDLE_DIRECTORY=$(echo "$pubpoint" | jq -r '(.bundleDirectory // "")')
        
        if [ -z "$URLREF" ] || [ "$URLREF" = "null" ]; then
            continue
        fi
        
        URLREF_NO_LEADING=${URLREF#/}
        SOURCE_DIR="$GENERATEDDIR/$URLREF_NO_LEADING"
        THEMA_SOURCE_DIR="$WORKSPACEDIR/src/$URLREF_NO_LEADING"
        RESOURCES_DIR="$SOURCE_DIR/resources"
        
        # no need to delete previous resources. Might be needed later? 29/06/2026
        
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
        
        if copy_bundle_directory_files "$THEMA_SOURCE_DIR" "$BUNDLE_DIRECTORY" "$RESOURCES_DIR"; then
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
        
        write_bundle_report "$URLREF" "$copied_any" "$RESOURCES_DIR"
    done
}

process_checkout_dir() {
    local checkout_rel_dir=$1
    local checkout_dir="$WORKSPACEDIR/src/$checkout_rel_dir"
    local pubpoint_file="$checkout_dir/.publication-point.json"
    
    if [ ! -f "$pubpoint_file" ]; then
        echo "Skipping checkout without .publication-point.json: $checkout_dir"
        return
    fi
    
    process_publication_file "$pubpoint_file"
}

CHECKOUTFILE="$WORKSPACEDIR/checkouts.txt"

if [ -f "$CHECKOUTFILE" ] && [ -s "$CHECKOUTFILE" ]; then
    while IFS= read -r checkout_rel_dir; do
        if [ -n "$checkout_rel_dir" ]; then
            echo "processing checked out publication point: $checkout_rel_dir"
            process_checkout_dir "$checkout_rel_dir"
        fi
    done < "$CHECKOUTFILE"
else
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
fi
