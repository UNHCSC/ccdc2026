#!/bin/sh
# pfSense Backup Collector
# Creates a timestamped archive containing critical configuration,
# service state metadata, logs, and security-relevant system files.
#
# Usage:
#   sh pfBackup.sh [output_directory]
#
# Example:
#   sh pfBackup.sh /root/pfBackups

set -u

SCRIPT_NAME="$(basename "$0")"
HOSTNAME_SHORT="$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo unknown)"
TIMESTAMP="$(date '+%Y%m%d_%H%M%S')"
DEST_BASE="${1:-/root/pfBackups}"
STAGE_DIR="${DEST_BASE}/pfbackup_${HOSTNAME_SHORT}_${TIMESTAMP}"
ARCHIVE_NAME="$(basename "$STAGE_DIR").tar.gz"
ARCHIVE_PATH="${DEST_BASE}/${ARCHIVE_NAME}"

log() {
    printf '[%s] %s\n' "$(date '+%F %T')" "$*" >&2
}

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log "This script must run as root on pfSense."
        exit 1
    fi
}

run_cmd() {
    # Usage: run_cmd "description" "command"
    _desc="$1"
    _cmd="$2"

    {
        printf '===== %s =====\n' "$_desc"
        printf 'CMD: %s\n' "$_cmd"
        printf 'TIME: %s\n\n' "$(date '+%F %T')"
        sh -c "$_cmd" 2>&1
        printf '\n'
    } >>"$STAGE_DIR/metadata/system_state.txt"
}

stage_path_if_exists() {
    # Usage: stage_path_if_exists "relative/path/from/root"
    _rel="$1"

    if [ -e "/$_rel" ]; then
        log "Staging /$_rel"
        mkdir -p "$STAGE_DIR/files"

        # Use tar pipe to preserve modes/ownership/symlinks and avoid shell glob issues.
        if tar -C / -cpf - "$_rel" 2>/dev/null | tar -C "$STAGE_DIR/files" -xpf - 2>/dev/null; then
            printf '%s\n' "/$_rel" >>"$STAGE_DIR/metadata/staged_paths.txt"
        else
            printf '%s\n' "/$_rel" >>"$STAGE_DIR/metadata/failed_paths.txt"
        fi
    else
        printf '%s\n' "/$_rel" >>"$STAGE_DIR/metadata/missing_paths.txt"
    fi
}

require_root
umask 077
mkdir -p "$STAGE_DIR/metadata" "$STAGE_DIR/files"

log "Starting pfSense backup stage in: $STAGE_DIR"

# Basic metadata for quick triage and provenance.
{
    printf 'pfSense Backup Collector\n'
    printf 'Script: %s\n' "$SCRIPT_NAME"
    printf 'Collected: %s\n' "$(date '+%F %T %z')"
    printf 'Host: %s\n' "$(hostname 2>/dev/null || echo unknown)"
    printf 'Stage Dir: %s\n' "$STAGE_DIR"
    printf 'Archive: %s\n' "$ARCHIVE_PATH"
    printf '\n'
} >"$STAGE_DIR/README.txt"

# Capture current system/service/firewall state.
run_cmd "System - OS/Kernel" "uname -a"
run_cmd "System - Versions" "cat /etc/version /etc/version.patch /etc/platform 2>/dev/null"
run_cmd "System - Uptime/Boot" "uptime && sysctl kern.boottime"
run_cmd "Network - Interfaces" "ifconfig -a"
run_cmd "Network - Routing table" "netstat -rn"
run_cmd "Network - Listening sockets" "sockstat -4 -6 -l"
run_cmd "Firewall - pf summary" "pfctl -sa 2>/dev/null"
run_cmd "Processes - ps auxww" "ps auxww"
run_cmd "Packages - installed" "pkg info 2>/dev/null"
run_cmd "Cron - root" "crontab -l -u root 2>/dev/null || crontab -l 2>/dev/null"

# Core pfSense + FreeBSD config, secrets, service definitions, and logs.
# Paths are relative to root (/).
IMPORTANT_PATHS="
cf/conf
etc
usr/local/etc
usr/local/www
var/etc
var/db
var/dhcpd
var/unbound
var/cron/tabs
var/log
root
home
boot
"

printf '' >"$STAGE_DIR/metadata/staged_paths.txt"
printf '' >"$STAGE_DIR/metadata/missing_paths.txt"
printf '' >"$STAGE_DIR/metadata/failed_paths.txt"

for rel_path in $IMPORTANT_PATHS; do
    stage_path_if_exists "$rel_path"
done

# Hash everything in the staged backup so integrity can be verified later.
(
    cd "$STAGE_DIR" || exit 1
    find . -type f -print0 | xargs -0 sha256 >SHA256SUMS.txt 2>/dev/null || true
)

# Create compressed archive.
log "Creating archive: $ARCHIVE_PATH"
if tar -C "$DEST_BASE" -czpf "$ARCHIVE_PATH" "$(basename "$STAGE_DIR")"; then
    :
else
    log "Failed to create archive."
    exit 1
fi

{
    printf 'Completed: %s\n' "$(date '+%F %T')"
    printf 'Archive path: %s\n' "$ARCHIVE_PATH"
    printf 'Staged files dir: %s\n' "$STAGE_DIR/files"
    printf 'Metadata report: %s\n' "$STAGE_DIR/metadata/system_state.txt"
} >>"$STAGE_DIR/README.txt"

log "Backup complete."
log "Archive: $ARCHIVE_PATH"
log "Stage directory retained at: $STAGE_DIR"
