#!/bin/bash
# Add verified APK v3 packages to downloaded per-platform build artifacts.
#
# Expected layout:
#   <artifact_root>/aria2-next-static-<platform>/aria2-next
#
# Usage:
#   bash build_apk_artifacts.sh <artifact_root>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

ARTIFACT_ROOT_INPUT="${1:?Usage: build_apk_artifacts.sh <artifact_root>}"

if [ ! -d "$ARTIFACT_ROOT_INPUT" ]; then
    log_fatal "Artifact root not found: $ARTIFACT_ROOT_INPUT"
fi

ARTIFACT_ROOT="$(cd "$ARTIFACT_ROOT_INPUT" && pwd)"
PACKAGE_COUNT=0

for artifact_dir in "$ARTIFACT_ROOT"/aria2-next-static-*/; do
    [ -d "$artifact_dir" ] || continue

    directory_name="${artifact_dir%/}"
    directory_name="${directory_name##*/}"
    platform="${directory_name#aria2-next-static-}"
    binary="$artifact_dir/$BINARY_NAME"

    if [ "$platform" = "$directory_name" ] || [ -z "$platform" ]; then
        log_fatal "Unexpected artifact directory name: $directory_name"
    fi
    if [ ! -f "$binary" ]; then
        log_fatal "Raw binary missing for $platform: $binary"
    fi

    bash "$SCRIPT_DIR/build_apk.sh" "$platform" "$binary" "$artifact_dir"
    PACKAGE_COUNT=$((PACKAGE_COUNT + 1))
done

if [ "$PACKAGE_COUNT" -eq 0 ]; then
    log_fatal "No per-platform artifact directories found in $ARTIFACT_ROOT"
fi

log_info "Built and verified $PACKAGE_COUNT APK v3 packages"
