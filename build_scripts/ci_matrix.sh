#!/bin/bash
# Resolve a validated comma-separated platform selection to a GitHub Actions
# matrix. Keeping the supported target list here makes manual one-target builds
# use the same allow-list as automated release builds.
#
# Usage:
#   build_scripts/ci_matrix.sh all
#   build_scripts/ci_matrix.sh x86_64,aarch64_cortex-a53
#   build_scripts/ci_matrix.sh --list

set -euo pipefail

ALL_PLATFORMS=(
    aarch64_cortex-a53
    aarch64_cortex-a72
    aarch64_cortex-a76
    aarch64_generic
    arm_arm1176jzf-s_vfp
    arm_arm926ej-s
    arm_cortex-a15_neon-vfpv4
    arm_cortex-a5_vfpv4
    arm_cortex-a7
    arm_cortex-a7_neon-vfpv4
    arm_cortex-a7_vfpv4
    arm_cortex-a8_vfpv3
    arm_cortex-a9
    arm_cortex-a9_neon
    arm_cortex-a9_vfpv3-d16
    arm_fa526
    arm_xscale
    i386_pentium-mmx
    i386_pentium4
    loongarch64_generic
    mips64_mips64r2
    mips64_octeonplus
    mips64el_mips64r2
    mips_24kc
    mips_4kec
    mips_mips32
    mipsel_24kc
    mipsel_24kc_24kf
    mipsel_74kc
    mipsel_mips32
    riscv64_riscv64
    x86_64
    riscv64_generic
)

if [ "${1:-}" = "--list" ]; then
    printf '%s\n' "${ALL_PLATFORMS[@]}"
    exit 0
fi

requested="${1:-all}"
selected=()

contains_platform() {
    local candidate="$1" platform
    for platform in "${ALL_PLATFORMS[@]}"; do
        [ "$platform" = "$candidate" ] && return 0
    done
    return 1
}

already_selected() {
    local candidate="$1" platform
    for platform in "${selected[@]}"; do
        [ "$platform" = "$candidate" ] && return 0
    done
    return 1
}

if [ "$requested" = "all" ]; then
    selected=("${ALL_PLATFORMS[@]}")
else
    IFS=',' read -r -a requested_platforms <<< "$requested"
    for platform in "${requested_platforms[@]}"; do
        platform="${platform#"${platform%%[![:space:]]*}"}"
        platform="${platform%"${platform##*[![:space:]]}"}"

        if [ -z "$platform" ]; then
            echo "ERROR: Empty platform in selection: $requested" >&2
            exit 1
        fi
        if ! contains_platform "$platform"; then
            echo "ERROR: Unsupported platform: $platform" >&2
            echo "Run $0 --list to see supported values." >&2
            exit 1
        fi
        if ! already_selected "$platform"; then
            selected+=("$platform")
        fi
    done
fi

if [ "${#selected[@]}" -eq 0 ]; then
    echo "ERROR: No build platforms selected" >&2
    exit 1
fi

matrix='{"platform":['
separator=''
for platform in "${selected[@]}"; do
    matrix+="${separator}\"${platform}\""
    separator=','
done
matrix+=']}'

printf '%s\n' "$matrix"
