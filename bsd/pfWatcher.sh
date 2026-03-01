#!/bin/sh
# pfSense Watcher
# Monitors high-value logs for suspicious activity and detects file changes
# (new/modified/deleted) across critical pfSense paths.
#
# Usage:
#   sh pfWatcher.sh [-i interval_seconds] [-s state_dir] [--once]
#
# Examples:
#   sh pfWatcher.sh
#   sh pfWatcher.sh -i 30 -s /var/tmp/pfwatcher
#   sh pfWatcher.sh --once

set -u

INTERVAL_SECONDS=60
STATE_DIR="/var/tmp/pfwatcher"
RUN_ONCE=0

WATCH_PATHS="
/cf/conf
/etc
/usr/local/etc
/var/etc
/var/cron/tabs
/root
/home
"

LOG_FILES="
/var/log/system.log
/var/log/filter.log
/var/log/auth.log
/var/log/vpn.log
/var/log/resolver.log
/var/log/dhcpd.log
/var/log/nginx/error.log
"

# Pattern is intentionally broad for competition triage.
# Tune this on your team network to reduce noise.
LOG_EVENT_REGEX='failed|failure|invalid user|authentication error|accepted password|sudo|su:|login|webconfigurator|ssh|denied|blocked|refused|exploit|reverse shell|c2|payload|nmap|sqlmap|nikto|metasploit|config\.xml|segfault|panic'

IGNORE_REGEX='^/var/log/|^/var/run/|^/tmp/|^/var/tmp/|^/dev/|^/proc/'

PREV_SNAPSHOT=""
CURR_SNAPSHOT=""
DELTA_FILE=""
EVENT_LOG=""
LOG_WATCH_PIDS=""

usage() {
    cat <<EOF
Usage: $0 [-i interval_seconds] [-s state_dir] [--once]

Options:
    -i SECONDS    File integrity scan interval (default: 60)
    -s DIR        State/output directory (default: /var/tmp/pfwatcher)
    --once        Run one file integrity comparison and exit
    -h            Show this help
EOF
}

log_msg() {
    _level="$1"
    _message="$2"
    _ts="$(date '+%F %T')"
    _line="[$_ts] [$_level] $_message"

    printf '%s\n' "$_line"
    printf '%s\n' "$_line" >>"$EVENT_LOG"
}

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "This script must run as root on pfSense." >&2
        exit 1
    fi
}

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            -i)
                shift
                INTERVAL_SECONDS="${1:-}"
                ;;
            -s)
                shift
                STATE_DIR="${1:-}"
                ;;
            --once)
                RUN_ONCE=1
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                echo "Unknown argument: $1" >&2
                usage
                exit 1
                ;;
        esac
        shift
    done

    case "$INTERVAL_SECONDS" in
        ''|*[!0-9]*)
            echo "Invalid interval: $INTERVAL_SECONDS" >&2
            exit 1
            ;;
    esac

    if [ -z "$STATE_DIR" ]; then
        echo "State directory cannot be empty." >&2
        exit 1
    fi
}

init_state() {
    umask 077
    mkdir -p "$STATE_DIR"
    PREV_SNAPSHOT="$STATE_DIR/prev_snapshot.tsv"
    CURR_SNAPSHOT="$STATE_DIR/curr_snapshot.tsv"
    DELTA_FILE="$STATE_DIR/file_changes.txt"
    EVENT_LOG="$STATE_DIR/events.log"

    : >"$EVENT_LOG"
}

hash_file() {
    _file="$1"
    sha256 -q "$_file" 2>/dev/null || echo "sha256_error"
}

collect_file_record() {
    _file="$1"
    _out="$2"

    if printf '%s\n' "$_file" | grep -Eq "$IGNORE_REGEX"; then
        return
    fi

    _hash="$(hash_file "$_file")"
    _stat_line="$(stat -f '%Sp	%u	%g	%z	%m' "$_file" 2>/dev/null || echo '?	?	?	?	?')"

    # Fields:
    # path \t sha256 \t mode \t uid \t gid \t size \t mtime_epoch
    printf '%s	%s	%s\n' "$_file" "$_hash" "$_stat_line" >>"$_out"
}

build_snapshot() {
    _output="$1"
    : >"$_output"

    for base_path in $WATCH_PATHS; do
        if [ ! -e "$base_path" ]; then
            continue
        fi

        if [ -f "$base_path" ]; then
            collect_file_record "$base_path" "$_output"
            continue
        fi

        find "$base_path" -type f 2>/dev/null | while IFS= read -r file_path; do
            collect_file_record "$file_path" "$_output"
        done
    done

    sort -u "$_output" -o "$_output"
}

compare_snapshots() {
    _old="$1"
    _new="$2"
    _delta="$3"

    awk -F '\t' '
    NR == FNR {
        old[$1] = $0
        next
    }
    {
        new[$1] = $0
    }
    END {
        for (path in old) {
            if (!(path in new)) {
                printf "DELETED\t%s\n", path
            }
        }

        for (path in new) {
            split(new[path], n, FS)
            if (!(path in old)) {
                printf "NEW\t%s\n", path
                printf "  sha256: %s\n", n[2]
                printf "  mode: %s uid: %s gid: %s size: %s mtime: %s\n", n[3], n[4], n[5], n[6], n[7]
                continue
            }

            if (new[path] != old[path]) {
                split(old[path], o, FS)
                printf "MODIFIED\t%s\n", path
                if (o[2] != n[2]) {
                    printf "  sha256: %s -> %s\n", o[2], n[2]
                }
                if (o[3] != n[3]) {
                    printf "  mode: %s -> %s\n", o[3], n[3]
                }
                if (o[4] != n[4] || o[5] != n[5]) {
                    printf "  owner: %s:%s -> %s:%s\n", o[4], o[5], n[4], n[5]
                }
                if (o[6] != n[6]) {
                    printf "  size: %s -> %s\n", o[6], n[6]
                }
                if (o[7] != n[7]) {
                    printf "  mtime: %s -> %s\n", o[7], n[7]
                }
            }
        }
    }' "$_old" "$_new" >"$_delta"
}

process_log_line() {
    _log_file="$1"
    _line="$2"

    if printf '%s\n' "$_line" | grep -Eiq "$LOG_EVENT_REGEX"; then
        log_msg "LOG" "$_log_file :: $_line"
    fi
}

start_log_watchers() {
    for log_file in $LOG_FILES; do
        if [ ! -f "$log_file" ]; then
            log_msg "INFO" "Log file not found (skipping): $log_file"
            continue
        fi

        (
            tail -n 0 -F "$log_file" 2>/dev/null | while IFS= read -r line; do
                process_log_line "$log_file" "$line"
            done
        ) &

        LOG_WATCH_PIDS="$LOG_WATCH_PIDS $!"
        log_msg "INFO" "Watching log file: $log_file"
    done
}

stop_log_watchers() {
    for pid in $LOG_WATCH_PIDS; do
        kill "$pid" 2>/dev/null || true
    done
}

cleanup() {
    log_msg "INFO" "Stopping pfWatcher."
    stop_log_watchers
    exit 0
}

main_loop() {
    build_snapshot "$PREV_SNAPSHOT"
    log_msg "INFO" "Initial file baseline complete."

    if [ "$RUN_ONCE" -eq 1 ]; then
        build_snapshot "$CURR_SNAPSHOT"
        compare_snapshots "$PREV_SNAPSHOT" "$CURR_SNAPSHOT" "$DELTA_FILE"

        if [ -s "$DELTA_FILE" ]; then
            while IFS= read -r line; do
                [ -n "$line" ] || continue
                log_msg "FILE" "$line"
            done <"$DELTA_FILE"
        else
            log_msg "FILE" "No file changes detected."
        fi
        return
    fi

    start_log_watchers
    log_msg "INFO" "File integrity scan interval: ${INTERVAL_SECONDS}s"

    while :; do
        sleep "$INTERVAL_SECONDS"

        build_snapshot "$CURR_SNAPSHOT"
        compare_snapshots "$PREV_SNAPSHOT" "$CURR_SNAPSHOT" "$DELTA_FILE"

        if [ -s "$DELTA_FILE" ]; then
            log_msg "FILE" "File changes detected:"
            while IFS= read -r line; do
                [ -n "$line" ] || continue
                log_msg "FILE" "$line"
            done <"$DELTA_FILE"
        fi

        mv "$CURR_SNAPSHOT" "$PREV_SNAPSHOT"
    done
}

parse_args "$@"
require_root
init_state
trap cleanup INT TERM
log_msg "INFO" "Starting pfWatcher. State dir: $STATE_DIR"
main_loop
