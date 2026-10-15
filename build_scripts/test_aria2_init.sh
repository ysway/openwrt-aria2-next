#!/bin/sh
# Smoke test: source aria2-next.init under stub procd/uci shims and exercise
# the start_service / aria2_start code path for several config states.
#
# NOTE: real OpenWrt init scripts run without `set -u`. We deliberately
# don't enable it here either — uci_load_validate normally pre-initializes
# every schema variable to empty.
#
# Verifies disabled/invalid directories, legacy directory aliases, persistent
# state configuration, option aliases, headers, and fail-closed RPC migration.
# Set ARIA2_TEST_BINARY to validate successful configs with a native binary.

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
procd_add_jail_mount()  { echo "procd_add_jail_mount $*" >> "$PROCD_TRACE"; }
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
config_list_foreach() {
    local values item
    case "$2" in
        header) values="$test_headers" ;;
        extra_settings) values="$test_extra_settings" ;;
        *) return 0 ;;
    esac
    [ -n "$values" ] || return 0
    while IFS= read -r item; do
        "$3" "$item"
    done <<EOF_LIST
$values
EOF_LIST
}
uci_load_validate() {
    # uci_load_validate <pkg> <type> <section> <validator> [schema...]
    local validator="$4"
    # Emulate the real helper: any schema name not already set in the
    # environment is initialized to empty string before invoking the
    # validator. This matches the behavior aria2_start relies on.
    local i name spec default is_set
    i=5
    while [ $i -le $# ]; do
        eval "spec=\${$i}"
        name="${spec%%:*}"
        case "$spec" in
            *:*:*) default="${spec##*:}" ;;
            *) default="" ;;
        esac
        eval "is_set=\${$name+x}"
        if [ -z "$is_set" ]; then
            eval "$name=\"\$default\""
        fi
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
    LAST_RC=$rc
    LAST_INSTANCES="$(grep -c procd_close_instance "$PROCD_TRACE")"
    echo "── case: $name (rc=$rc) ──"
    echo "log:    $(cat "$LOG")"
    echo "procd:  $LAST_INSTANCES instance(s) registered"
    echo
}

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

assert_result() {
    expected_rc="$1"
    expected_instances="$2"
    [ "$LAST_RC" -eq "$expected_rc" ] || \
        fail "expected rc=$expected_rc, got rc=$LAST_RC"
    [ "$LAST_INSTANCES" -eq "$expected_instances" ] || \
        fail "expected $expected_instances instance(s), got $LAST_INSTANCES"
}

assert_log_contains() {
    grep -Fq "$1" "$LOG" || fail "log does not contain: $1"
}

assert_file_contains() {
    file="$1"
    value="$2"
    [ -f "$file" ] || fail "missing generated file: $file"
    grep -Fqx "$value" "$file" || fail "$file does not contain: $value"
}

assert_file_excludes() {
    file="$1"
    value="$2"
    [ -f "$file" ] || fail "missing generated file: $file"
    if grep -Fq "$value" "$file"; then
        fail "$file unexpectedly contains: $value"
    fi
}

# Case 1: enabled=0 — should bail "Instance disabled"
run_case "enabled=0 default" '
enabled=0
config_dir=/var/etc/aria2
'
assert_result 1 0
assert_log_contains 'disabled'

# Case 2: enabled=1 but no dir
run_case "enabled=1, no dir" '
enabled=1
config_dir=/var/etc/aria2
'
assert_result 1 0
assert_log_contains 'Please set download dir'

# Case 3: enabled=1, dir set but does not exist on disk
run_case "enabled=1, dir missing" "
enabled=1
config_dir=$WORK/runtime/missing
dir=$WORK/nonexistent
"
assert_result 1 0
assert_log_contains 'Please create download dir first'

# Case 4: success path — dir present
mkdir -p "$WORK/dl"
run_case "enabled=1, dir present" "
enabled=1
config_dir=$WORK/runtime/success
dir=$WORK/dl
"
assert_result 0 1
assert_file_contains "$WORK/runtime/success/aria2-next.conf.main" \
    "state-dir=$WORK/runtime/success/state.main"
assert_file_contains "$WORK/runtime/success/aria2-next.conf.main" 'enable-dht=true'
assert_file_excludes "$WORK/runtime/success/aria2-next.conf.main" 'rpc-user='
[ -d "$WORK/runtime/success/state.main" ] || fail "state directory was not created"
if [ -d /etc/ssl ]; then
    grep -Fxq 'procd_add_jail_mount /etc/ssl' "$PROCD_TRACE" || \
        fail "target CA trust directory was not mounted in the service jail"
fi

# Case 5: legacy aria2-static keys (download_dir + dht_enable)
mkdir -p "$WORK/dl2"
run_case "legacy download_dir+dht_enable" "
enabled=1
config_dir=$WORK/runtime/legacy
download_dir=$WORK/dl2
dht_enable=true
"
assert_result 0 1
assert_file_contains "$WORK/runtime/legacy/aria2-next.conf.main" "dir=$WORK/dl2"
assert_file_contains "$WORK/runtime/legacy/aria2-next.conf.main" 'enable-dht=true'
assert_file_excludes "$WORK/runtime/legacy/aria2-next.conf.main" 'dht-file-path='

# Case 6: legacy dht_enable=false must override the default.
run_case "legacy dht_enable=false" "
enabled=1
config_dir=$WORK/runtime/legacy-dht-off
download_dir=$WORK/dl2
dht_enable=false
"
assert_result 0 1
assert_file_contains "$WORK/runtime/legacy-dht-off/aria2-next.conf.main" 'enable-dht=false'

# Case 7: the modern key takes precedence if both DHT keys are present.
run_case "modern enable_dht overrides legacy alias" "
enabled=1
config_dir=$WORK/runtime/modern-dht-off
dir=$WORK/dl2
enable_dht=false
dht_enable=true
"
assert_result 0 1
assert_file_contains "$WORK/runtime/modern-dht-off/aria2-next.conf.main" 'enable-dht=false'

# Case 8: explicit legacy username/password auth must fail closed.
run_case "legacy RPC user_pass rejected" "
enabled=1
config_dir=$WORK/runtime/user-pass
dir=$WORK/dl
rpc_auth_method=user_pass
rpc_user=legacy
rpc_passwd=secret
"
assert_result 1 0
assert_log_contains 'no longer supported'

# Case 9: old configs inferred user/password auth from rpc_user.
run_case "implicit legacy RPC user rejected" "
enabled=1
config_dir=$WORK/runtime/implicit-user
dir=$WORK/dl
rpc_user=legacy
rpc_passwd=secret
"
assert_result 1 0
assert_log_contains 'no longer supported'

# Case 10: password-only legacy configs must also fail closed.
run_case "implicit legacy RPC password rejected" "
enabled=1
config_dir=$WORK/runtime/implicit-password
dir=$WORK/dl
rpc_passwd=secret
"
assert_result 1 0
assert_log_contains 'no longer supported'

# Case 11: token mode without a secret must not start unauthenticated.
run_case "RPC token without secret rejected" "
enabled=1
config_dir=$WORK/runtime/token-missing
dir=$WORK/dl
rpc_auth_method=token
"
assert_result 1 0
assert_log_contains 'requires rpc_secret'

# Case 12: token mode emits only the supported RPC secret setting.
run_case "RPC token configured" "
enabled=1
config_dir=$WORK/runtime/token
dir=$WORK/dl
rpc_auth_method=token
rpc_secret=correct-horse
"
assert_result 0 1
assert_file_contains "$WORK/runtime/token/aria2-next.conf.main" \
    'rpc-secret=correct-horse'
assert_file_excludes "$WORK/runtime/token/aria2-next.conf.main" 'rpc-user='
assert_file_excludes "$WORK/runtime/token/aria2-next.conf.main" 'rpc-passwd='

run_case "renamed UCI options preserve legacy behavior" "
enabled=1
config_dir=$WORK/runtime/aliases
dir=$WORK/dl
auto_save_interval=30
bt_detach_seed_only=true
peer_id_prefix=-OW0001-
"
assert_result 0 1
assert_file_contains "$WORK/runtime/aliases/aria2-next.conf.main" 'state-save-interval=30'
assert_file_contains "$WORK/runtime/aliases/aria2-next.conf.main" 'detach-share-only=true'
assert_file_contains "$WORK/runtime/aliases/aria2-next.conf.main" 'bt-peer-id-prefix=-OW0001-'
assert_file_excludes "$WORK/runtime/aliases/aria2-next.conf.main" 'auto-save-interval='
assert_file_excludes "$WORK/runtime/aliases/aria2-next.conf.main" 'bt-detach-seed-only='

run_case "modern options override legacy aliases" "
enabled=1
config_dir=$WORK/runtime/modern-options
dir=$WORK/dl
auto_save_interval=0
state_save_interval=10
bt_detach_seed_only=true
detach_share_only=false
peer_id_prefix=-OLD001-
bt_peer_id_prefix=-NEW001-
rpc_listen_all=false
dns_over_https=https://dns.example/dns-query
"
assert_result 0 1
assert_file_contains "$WORK/runtime/modern-options/aria2-next.conf.main" 'state-save-interval=10'
assert_file_contains "$WORK/runtime/modern-options/aria2-next.conf.main" 'detach-share-only=false'
assert_file_contains "$WORK/runtime/modern-options/aria2-next.conf.main" 'bt-peer-id-prefix=-NEW001-'
assert_file_contains "$WORK/runtime/modern-options/aria2-next.conf.main" 'rpc-listen-all=false'
assert_file_contains "$WORK/runtime/modern-options/aria2-next.conf.main" 'dns-over-https=https://dns.example/dns-query'

run_case "legacy checkpoint zero has clear migration error" "
enabled=1
config_dir=$WORK/runtime/zero-checkpoint
dir=$WORK/dl
auto_save_interval=0
"
assert_result 1 0
assert_log_contains '0 is no longer supported'

for tls_setting in 'rpc_secure=true' 'rpc_certificate=/old/cert.pem' 'rpc_private_key=/old/key.pem'; do
    run_case "legacy RPC TLS rejected: $tls_setting" "
enabled=1
config_dir=$WORK/runtime/tls
dir=$WORK/dl
$tls_setting
"
    assert_result 1 0
    assert_log_contains 'TLS reverse proxy'
done

for extra_setting in 'rpc-secure=true' '  rpc-secure = true  ' 'rpc-secure' '  rpc-secure  ' 'rpc-certificate=/old/cert.pem' 'rpc-private-key=/old/key.pem' 'rpc-user=legacy' 'rpc-passwd=secret'; do
    run_case "unsafe extra_settings rejected" "
enabled=1
config_dir=$WORK/runtime/extra-unsafe
dir=$WORK/dl
test_extra_settings='$extra_setting'
"
    assert_result 1 0
    assert_log_contains 'no longer supported'
done

run_case "multiline extra_settings cannot bypass TLS guard" "
enabled=1
config_dir=$WORK/runtime/extra-multiline
dir=$WORK/dl
test_extra_settings='split=2
 rpc-secure = true'
"
assert_result 1 0
assert_log_contains 'TLS reverse proxy'

run_case "multiline bare flag cannot bypass TLS guard" "
enabled=1
config_dir=$WORK/runtime/extra-bare-multiline
dir=$WORK/dl
test_extra_settings='split=2
  rpc-secure  '
"
assert_result 1 0
assert_log_contains 'TLS reverse proxy'

run_case "extra_settings cannot empty configured RPC token" "
enabled=1
config_dir=$WORK/runtime/extra-empty-token
dir=$WORK/dl
rpc_auth_method=token
rpc_secret=correct-horse
test_extra_settings='rpc-secret='
"
assert_result 1 0
assert_log_contains 'non-empty rpc-secret'

run_case "plaintext proxy config and request headers accepted" "
enabled=1
config_dir=$WORK/runtime/headers
dir=$WORK/dl
rpc_secure=false
rpc_auth_method=token
rpc_secret=correct-horse
test_extra_settings='# rpc-secure=true is only a comment
  # rpc-secure
  rpc-secure = false
split=2'
test_headers='X-OpenWrt-Test: two words
Accept-Encoding: gzip'
"
assert_result 0 1
assert_file_contains "$WORK/runtime/headers/aria2-next.conf.main" 'header=X-OpenWrt-Test: two words'
assert_file_contains "$WORK/runtime/headers/aria2-next.conf.main" 'header=Accept-Encoding: gzip'
assert_file_excludes "$WORK/runtime/headers/aria2-next.conf.main" 'header="'

if [ -n "${ARIA2_TEST_BINARY:-}" ]; then
    # Upstream answers --version before reading the config. Run the empty
    # session in foreground command-line mode instead, without RPC listeners.
    validate_native_config() {
        "$ARIA2_TEST_BINARY" --conf-path="$1" \
            --daemon=false --enable-rpc=false --enable-dht=false \
            --bt-enable-lpd=false --bt-port-mapping=false --stop=1 \
            >/dev/null
    }
    for native_config in success legacy aliases modern-options headers; do
        validate_native_config "$WORK/runtime/$native_config/aria2-next.conf.main" || \
            fail "binary rejected generated $native_config config"
    done
    cp "$WORK/runtime/success/aria2-next.conf.main" "$WORK/invalid.conf"
    printf '\nunknown-openwrt-regression-option=true\n' >> "$WORK/invalid.conf"
    if validate_native_config "$WORK/invalid.conf" 2>"$WORK/invalid.log"; then
        fail "native config check did not reject an unknown option"
    fi
    grep -Fq 'unknown-openwrt-regression-option' "$WORK/invalid.log" || \
        fail "native config check failed without parsing the unknown option"
fi

echo "All aria2-next init smoke tests passed."
