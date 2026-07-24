#!/bin/bash
# Generate a package feed index from collected .ipk files.
#
# Usage:
#   bash gen_feed.sh <artifacts_dir> <feed_output_dir>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

ARTIFACTS_DIR="${1:?Usage: gen_feed.sh <artifacts_dir> <feed_output_dir>}"
FEED_DIR="${2:?Feed output directory required}"

if [ ! -d "$ARTIFACTS_DIR" ]; then
    log_fatal "Artifacts directory not found: $ARTIFACTS_DIR"
fi

ARTIFACTS_DIR="$(cd "$ARTIFACTS_DIR" && pwd)"
ensure_dir "$FEED_DIR"
FEED_DIR="$(cd "$FEED_DIR" && pwd)"

log_info "Generating feed index from $ARTIFACTS_DIR"

# Copy package and auxiliary artifacts for this architecture.
for artifact in "$ARTIFACTS_DIR"/*; do
    [ -f "$artifact" ] || continue
    cp "$artifact" "$FEED_DIR/"
done

# Generate Packages index
cd "$FEED_DIR"
IPK_COUNT=0
PACKAGES_FILE="$FEED_DIR/Packages"
: > "$PACKAGES_FILE"

for ipk in *.ipk; do
    [ -f "$ipk" ] || continue
    IPK_COUNT=$((IPK_COUNT + 1))

    # Extract control info
    CONTROL_FILE=$(mktemp)
    if tar -xOf "$FEED_DIR/$ipk" ./control.tar.gz 2>/dev/null \
        | tar -xzOf - ./control 2>/dev/null > "$CONTROL_FILE"; then
        cat "$CONTROL_FILE" >> "$PACKAGES_FILE"
    else
        rm -f "$CONTROL_FILE"
        log_fatal "Could not extract package metadata from $FEED_DIR/$ipk"
    fi
    rm -f "$CONTROL_FILE"

    SIZE=$(stat -c%s "$ipk" 2>/dev/null || stat -f%z "$ipk")
    MD5=$(md5sum "$ipk" | awk '{print $1}')
    SHA256=$(sha256sum "$ipk" | awk '{print $1}')

    cat >> "$PACKAGES_FILE" <<EOF
Filename: $ipk
Size: $SIZE
MD5Sum: $MD5
SHA256sum: $SHA256

EOF
done

if [ "$IPK_COUNT" -eq 0 ]; then
    log_fatal "No IPK packages found in $ARTIFACTS_DIR"
fi

# Compress Packages
gzip -n -c "$PACKAGES_FILE" > "${PACKAGES_FILE}.gz"

log_info "Feed generated: $IPK_COUNT packages in $FEED_DIR"
