#!/bin/bash
# Render architecture/file sections and build metadata into the feed template.
#
# Usage:
#   bash render_feed_index.sh <feed_dir> <version> <build_date>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

FEED_DIR_INPUT="${1:?Usage: render_feed_index.sh <feed_dir> <version> <build_date>}"
VERSION="${2:?Version required}"
BUILD_DATE="${3:?Build date required}"

if [ ! -d "$FEED_DIR_INPUT" ]; then
    log_fatal "Feed directory not found: $FEED_DIR_INPUT"
fi

FEED_DIR="$(cd "$FEED_DIR_INPUT" && pwd)"
INDEX_FILE="$FEED_DIR/index.html"

if [ ! -f "$INDEX_FILE" ]; then
    log_fatal "Feed template not found: $INDEX_FILE"
fi

if ! grep -q '<!-- arch-section-anchor -->' "$INDEX_FILE" ||
    ! grep -q '<!-- end-arch-section-anchor -->' "$INDEX_FILE"; then
    log_fatal "Architecture anchors are missing from $INDEX_FILE"
fi

SECTIONS_FILE="$(mktemp)"
RENDERED_FILE="$(mktemp)"
trap 'rm -f "$SECTIONS_FILE" "$RENDERED_FILE"' EXIT

ARCH_COUNT=0
for arch_dir in "$FEED_DIR"/*/; do
    [ -d "$arch_dir" ] || continue
    arch="${arch_dir%/}"
    arch="${arch##*/}"
    ARCH_COUNT=$((ARCH_COUNT + 1))

    {
        echo "<details class=\"arch-section\" data-architecture=\"$arch\">"
        echo "    <summary>$arch</summary>"
        echo "    <table>"
        echo "        <thead>"
        echo "            <tr><th>File</th><th>Size</th><th>SHA-256</th></tr>"
        echo "        </thead>"
        echo "        <tbody>"
    } >> "$SECTIONS_FILE"

    for file_path in "$arch_dir"*; do
        [ -f "$file_path" ] || continue
        file="${file_path##*/}"

        case "$file" in
            *.ipk|*.apk|aria2-next|BUILDINFO|Packages|Packages.gz|Packages.sig|packages.adb)
                ;;
            *)
                continue
                ;;
        esac

        file_size=$(du -h "$file_path" | awk '{print $1}')
        file_sha256=$(sha256sum "$file_path" | awk '{print $1}')

        {
            echo "            <tr>"
            echo "                <td><a href=\"$arch/$file\">$file</a></td>"
            echo "                <td class=\"size-cell\">$file_size</td>"
            echo "                <td class=\"sha256-cell\">$file_sha256</td>"
            echo "            </tr>"
        } >> "$SECTIONS_FILE"
    done

    {
        echo "        </tbody>"
        echo "    </table>"
        echo "</details>"
    } >> "$SECTIONS_FILE"
done

if [ "$ARCH_COUNT" -eq 0 ]; then
    log_fatal "No architecture directories found in $FEED_DIR"
fi

awk -v sections="$SECTIONS_FILE" '
    /<!-- arch-section-anchor -->/ {
        print
        while ((getline line < sections) > 0) {
            print line
        }
        close(sections)
        replacing = 1
        next
    }
    replacing && /<!-- end-arch-section-anchor -->/ {
        replacing = 0
        print
        next
    }
    replacing { next }
    { print }
' "$INDEX_FILE" > "$RENDERED_FILE"

awk -v version="$VERSION" -v build_date="$BUILD_DATE" '
    /<strong id="version">/ {
        sub(/>[^<]*</, ">" version "<")
    }
    /<strong id="date">/ {
        sub(/>[^<]*</, ">" build_date "<")
    }
    { print }
' "$RENDERED_FILE" > "$INDEX_FILE"

log_info "Rendered $ARCH_COUNT architecture sections in $INDEX_FILE"
