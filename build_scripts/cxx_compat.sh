#!/bin/bash
# Target-compiler checks for narrowly scoped upstream C++ compatibility fixes.
# This file is sourced by build scripts and must not change their globals.

# Print '-include utility' only when it repairs the actual translation unit.
# Usage: choose_utility_preinclude COMPILER SOURCE [CXX compiler flags...]
# An unrelated compiler failure remains fatal, with both diagnostics retained.
choose_utility_preinclude() (
    if [ "$#" -lt 2 ]; then
        printf '%s\n' 'ERROR: choose_utility_preinclude requires a compiler and source' >&2
        return 2
    fi

    local compiler="$1" source="$2" probe_dir
    shift 2
    probe_dir="$(mktemp -d)" || return 1
    trap 'rm -rf -- "$probe_dir"' EXIT

    if "$compiler" "$@" -fsyntax-only "$source" \
        >"$probe_dir/plain.log" 2>&1; then
        return 0
    fi

    if "$compiler" "$@" -include utility -fsyntax-only "$source" \
        >"$probe_dir/utility.log" 2>&1; then
        printf '==> Target compiler requires <utility> preinclude for %s\n' "$source" >&2
        printf '%s\n' '-include utility'
        return 0
    fi

    printf 'ERROR: C++ compatibility check failed for %s\n' "$source" >&2
    printf '%s\n' 'Compiler diagnostics without the compatibility header:' >&2
    cat "$probe_dir/plain.log" >&2
    printf '%s\n' 'Compiler diagnostics with <utility>:' >&2
    cat "$probe_dir/utility.log" >&2
    return 1
)
