#!/bin/sh
# Smoke test: source aria2-next.init under stub procd/uci shims and exercise
# the start_service / aria2_start code path for several config states.
#
# NOTE: real OpenWrt init scripts run without `set -u`. We deliberately
# don't enable it here either — uci_load_validate normally pre-initializes
# every schema variable to empty.
#
# Verifies:
#   1. enabled=0 → bails with "Instance disabled" (returns 1, no crash)
#   2. enabled=1, no dir → "Please set download dir"
#   3. enabled=1, dir missing on disk → "Please create download dir first"
#   4. enabled=1, dir present → reaches procd_close_instance (success path)
#   5. legacy aria2-static keys (download_dir, dht_enable) → mapped

INIT="$(cd "$(dirname "$0")/../package/aria2-next-static/files" && pwd)/aria2-next.init"
[ -f "$INIT" ] || { echo "init not found: $INIT" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/config" "$WORK/runtime"
LOG="$WORK/log"
: > "$LOG"

# ── stub /etc/rc.common: just defines no-ops; init script will be sourced manually
cat > "$WORK/rc.common" <<'EOF'
# rc.common stub
START=
USE_PROCD=
EOF

# ── stub procd helpers ──
PROCD_TRACE="$WORK/procd.trace"
: > "$PROCD_TRACE"

stub_lib() {
cat <<'EOF'
procd_open_instance()   { echo "procd_open_instance $*"   >> "$PROCD_TRACE"; }
procd_close_instance()  { echo "procd_close_instance"     >> "$PROCD_TRACE"; }
procd_set_param()       { echo "procd_set_param $*"       >> "$PROCD_TRACE"; }
procd_append_param()    { echo "procd_append_param $*"    >> "$PROCD_TRACE"; }
procd_add_jail()        { echo "procd_add_jail $*"        >> "$PROCD_TRACE"; }
procd_add_jail_mount()  { :; }
procd_add_jail_mount_rw() { :; }
procd_add_reload_trigger() { :; }
procd_add_validation()  { :; }

logger() { shift $(($# - 1)); echo "[log] $*" >> "$WORK/log"; }
user_exists() { return 0; }
config_load() { . "$WORK/uci.parsed"; }
config_foreach() {
    # config_foreach <fn> <type> [args...]
    local fn="$1" ; shift
    local type="$1"; shift
    eval "$fn main $*"
}
config_list_foreach() { :; }
uci_load_validate() {
    # uci_load_validate <pkg> <type> <section> <validator> [schema...]
    local validator="$4"
    # Emulate the real helper: any schema name not already set in the
    # environment is initialized to empty string before invoking the
    # validator. This matches the behavior aria2_start relies on.
    local i name
    i=5
    while [ $i -le $# ]; do
        eval "spec=\${$i}"
        name="${spec%%:*}"
        eval "[ -n \"\${$name+x}\" ] || $name=''"
        i=$((i + 1))
    done
    eval "$validator main 0"
}
EOF
}

run_case() {
    name="$1"; shift
    : > "$LOG"
    : > "$PROCD_TRACE"
    cat > "$WORK/uci.parsed" <<EOF
$*
EOF
    # Source the init (skip the rc.common shebang dispatch by sourcing the body)
    (
        export WORK PROCD_TRACE
        eval "$(stub_lib)"
        # Remove the rc.common shebang line so we can source plainly
        # shellcheck disable=SC1090
        . "$INIT"
        start_service 2>&1
    )
    rc=$?
    echo "── case: $name (rc=$rc) ──"
    echo "log:    $(cat "$LOG")"
    echo "procd:  $(grep -c procd_close_instance "$PROCD_TRACE") instance(s) registered"
    echo
}

# Case 1: enabled=0 — should bail "Instance disabled"
run_case "enabled=0 default" '
enabled=0
config_dir=/var/etc/aria2
'

# Case 2: enabled=1 but no dir
run_case "enabled=1, no dir" '
enabled=1
config_dir=/var/etc/aria2
'

# Case 3: enabled=1, dir set but does not exist on disk
run_case "enabled=1, dir missing" "
enabled=1
config_dir=$WORK/runtime
dir=$WORK/nonexistent
"

# Case 4: success path — dir present
mkdir -p "$WORK/dl"
run_case "enabled=1, dir present" "
enabled=1
config_dir=$WORK/runtime
dir=$WORK/dl
"

# Case 5: legacy aria2-static keys (download_dir + dht_enable)
mkdir -p "$WORK/dl2"
run_case "legacy download_dir+dht_enable" "
enabled=1
config_dir=$WORK/runtime
download_dir=$WORK/dl2
dht_enable=true
"

echo "expected:"
echo "  1. log mentions 'disabled', 0 instances"
echo "  2. log mentions 'Please set download dir', 0 instances"
echo "  3. log mentions 'Please create download dir', 0 instances"
echo "  4. 1 instance registered, no error"
echo "  5. 1 instance registered (dir resolved from download_dir)"
