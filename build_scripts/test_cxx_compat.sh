#!/bin/bash
# Exercise the compatibility decision using real upstream source and compiler.
# Usage: bash test_cxx_compat.sh [CXX [ARIA2_SOURCE_DIR]]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/cxx_compat.sh"

CXX_COMPILER="${1:-${CXX:-g++}}"
ARIA2_SOURCE_DIR="${2:-$SCRIPT_DIR/../aria2-next}"
SOURCE_FILE="$ARIA2_SOURCE_DIR/src/disk/File.cc"
WORK="$(mktemp -d)"
trap 'rm -rf -- "$WORK"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

[ "$#" -le 2 ] || fail 'usage: test_cxx_compat.sh [CXX [ARIA2_SOURCE_DIR]]'
command -v "$CXX_COMPILER" >/dev/null 2>&1 || fail "compiler not found: $CXX_COMPILER"
[ -f "$SOURCE_FILE" ] || fail "upstream source not found: $SOURCE_FILE"

CXX_FLAGS=(
    -std=c++20
    -O2
    -I "$ARIA2_SOURCE_DIR/src"
    -I "$ARIA2_SOURCE_DIR/third_party/spdlog/include"
)

# A source with no standard headers cannot accidentally obtain std::exchange
# through a compiler-specific transitive include. This keeps fallback coverage
# even after upstream repairs its own source.
printf '%s\n' \
    'int main() { int value = 1; return std::exchange(value, 2); }' \
    >"$WORK/missing-utility.cc"
if ! SELECTED_FLAGS="$(choose_utility_preinclude "$CXX_COMPILER" "$WORK/missing-utility.cc" \
    "${CXX_FLAGS[@]}" 2>"$WORK/missing-utility-probe.log")"; then
    cat "$WORK/missing-utility-probe.log" >&2
    fail 'missing-header source did not compile with the compatibility header'
fi
[ "$SELECTED_FLAGS" = '-include utility' ] || \
    fail 'missing-header source did not select the utility preinclude'

# The selected flags must follow this compiler's actual behavior, not a tag.
# GCC 14/musl needs the header for affected upstream releases; repaired source
# and some standard libraries compile normally without the workaround.
EXPECTED_FLAGS=''
if ! "$CXX_COMPILER" "${CXX_FLAGS[@]}" -fsyntax-only "$SOURCE_FILE" \
    >"$WORK/original.log" 2>&1; then
    EXPECTED_FLAGS='-include utility'
fi
if ! SELECTED_FLAGS="$(choose_utility_preinclude "$CXX_COMPILER" "$SOURCE_FILE" \
    "${CXX_FLAGS[@]}" 2>"$WORK/original-probe.log")"; then
    cat "$WORK/original-probe.log" >&2
    fail 'actual upstream source cannot compile with the compatibility header'
fi
[ "$SELECTED_FLAGS" = "$EXPECTED_FLAGS" ] || \
    fail 'header selection does not match actual compiler behavior'

# A future upstream fix must stop requesting the workaround automatically.
# Only temporary copies change; all original project headers remain in use.
cp "$SOURCE_FILE" "$WORK/repaired.cc"
sed -i '1i#include <utility>' "$WORK/repaired.cc"
if ! SELECTED_FLAGS="$(choose_utility_preinclude "$CXX_COMPILER" "$WORK/repaired.cc" \
    "${CXX_FLAGS[@]}" 2>"$WORK/repaired-probe.log")"; then
    cat "$WORK/repaired-probe.log" >&2
    fail 'source with an explicit utility include did not compile'
fi
[ -z "$SELECTED_FLAGS" ] || fail 'repaired source still requested a preinclude'

# The retry must not swallow unrelated errors or report a successful workaround.
cp "$WORK/repaired.cc" "$WORK/unrelated.cc"
printf '\n#error cxx_compat_unrelated_failure\n' >>"$WORK/unrelated.cc"
if SELECTED_FLAGS="$(choose_utility_preinclude "$CXX_COMPILER" "$WORK/unrelated.cc" \
    "${CXX_FLAGS[@]}" 2>"$WORK/unrelated-probe.log")"; then
    fail 'an unrelated compiler error was accepted'
fi
[ -z "$SELECTED_FLAGS" ] || fail 'failed probe emitted successful compiler flags'
grep -q 'cxx_compat_unrelated_failure' "$WORK/unrelated-probe.log" || \
    fail 'unrelated compiler diagnostic was lost'

if [ -n "$EXPECTED_FLAGS" ]; then
    printf '%s\n' 'Original upstream source requires -include utility on this compiler.'
else
    printf '%s\n' 'Original upstream source compiles without a compatibility header on this compiler.'
fi
printf '%s\n' 'All C++ compatibility regression tests passed.'
