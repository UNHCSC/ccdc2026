#!/bin/sh
# pfSense Inventory Collector
# Collects broad host/network/security context for incident response and
# competition triage. Output is written to a timestamped directory.

SCRIPT_NAME="$(basename "$0")"
HOSTNAME_SHORT="$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo unknown)"
TIMESTAMP="$(date '+%Y%m%d_%H%M%S')"
DEFAULT_OUTDIR="/tmp/pfsense_inventory_${HOSTNAME_SHORT}_${TIMESTAMP}"
OUTDIR="${1:-$DEFAULT_OUTDIR}"

umask 077
mkdir -p "$OUTDIR"

log() {
    printf '[%s] %s\n' "$(date '+%F %T')" "$*" >&2
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
    } >>"$OUTDIR/inventory.txt"
}

copy_file_if_exists() {
    # Usage: copy_file_if_exists "/path/to/src" "relative/dest/name"
    _src="$1"
    _dst="$2"
    _dst_dir="$(dirname "$OUTDIR/$_dst")"

    if [ -f "$_src" ]; then
        mkdir -p "$_dst_dir"
        cp "$_src" "$OUTDIR/$_dst"
        chmod 600 "$OUTDIR/$_dst" 2>/dev/null || true
    fi
}

capture_tail_if_exists() {
    # Usage: capture_tail_if_exists "/path/to/log" "relative/dest/name" "lines"
    _src="$1"
    _dst="$2"
    _lines="$3"
    _dst_dir="$(dirname "$OUTDIR/$_dst")"

    if [ -f "$_src" ]; then
        mkdir -p "$_dst_dir"
        tail -n "$_lines" "$_src" >"$OUTDIR/$_dst" 2>/dev/null || true
        chmod 600 "$OUTDIR/$_dst" 2>/dev/null || true
    fi
}

log "Starting collection to: $OUTDIR"
log "This can take a minute depending on system size and log volume."

# Header summary
{
    printf 'pfSense Inventory Collector\n'
    printf 'Script: %s\n' "$SCRIPT_NAME"
    printf 'Collected: %s\n' "$(date '+%F %T %z')"
    printf 'Host: %s\n' "$(hostname 2>/dev/null || echo unknown)"
    printf 'Output Dir: %s\n' "$OUTDIR"
    printf '\n'
} >"$OUTDIR/README.txt"

# Core system context
run_cmd "System - OS/Kernel" "uname -a"
run_cmd "System - pfSense Version Files" "cat /etc/version /etc/version.patch /etc/platform 2>/dev/null"
run_cmd "System - Uptime/Boot" "uptime && sysctl kern.boottime"
run_cmd "System - Date" "date"
run_cmd "System - CPU" "sysctl hw.model hw.ncpu hw.physmem 2>/dev/null"
run_cmd "System - Full Sysctl (verbose)" "sysctl -a"
run_cmd "System - Dmesg" "dmesg -a"
run_cmd "System - Last Logins" "last -n 40 2>/dev/null"

# Filesystems and storage
run_cmd "Storage - Disk Usage" "df -h"
run_cmd "Storage - Mounts" "mount"
run_cmd "Storage - GEOM Disks" "geom disk list 2>/dev/null"
run_cmd "Storage - GEOM Partitions" "geom part list 2>/dev/null"
run_cmd "Storage - gpart show" "gpart show 2>/dev/null"
run_cmd "Storage - swapinfo" "swapinfo -h 2>/dev/null"
run_cmd "Storage - ZFS status" "zpool status 2>/dev/null"
run_cmd "Storage - ZFS datasets" "zfs list 2>/dev/null"

# Network and interface context
run_cmd "Network - Interfaces" "ifconfig -a"
run_cmd "Network - Routing table" "netstat -rn"
run_cmd "Network - Listening sockets" "sockstat -4 -6 -l"
run_cmd "Network - Active sockets" "sockstat -4 -6"
run_cmd "Network - ARP cache" "arp -an"
run_cmd "Network - Interface stats" "netstat -i -W"
run_cmd "Network - Established/All connections" "netstat -an"
run_cmd "Network - IPv4 stats" "netstat -s -p ip 2>/dev/null"
run_cmd "Network - TCP stats" "netstat -s -p tcp 2>/dev/null"
run_cmd "Network - UDP stats" "netstat -s -p udp 2>/dev/null"

# Firewall and pf state
run_cmd "Firewall - pf info" "pfctl -si 2>/dev/null"
run_cmd "Firewall - pf rules" "pfctl -sr 2>/dev/null"
run_cmd "Firewall - pf NAT rules" "pfctl -sn 2>/dev/null"
run_cmd "Firewall - pf tables" "pfctl -sTables 2>/dev/null"
run_cmd "Firewall - pf states" "pfctl -ss 2>/dev/null"
run_cmd "Firewall - pf all status (verbose)" "pfctl -sa 2>/dev/null"

# Service and process context
run_cmd "Processes - ps auxww" "ps auxww"
run_cmd "Services - rc status" "service -e 2>/dev/null"
run_cmd "Services - pkg inventory" "pkg info 2>/dev/null"
run_cmd "Services - package locks" "pkg lock -l 2>/dev/null"
run_cmd "Services - cron jobs (root)" "crontab -l -u root 2>/dev/null || crontab -l 2>/dev/null"
run_cmd "Services - periodic conf" "cat /etc/periodic.conf 2>/dev/null"

# User and auth context
run_cmd "Users - passwd" "cat /etc/passwd"
run_cmd "Users - group" "cat /etc/group"
run_cmd "Users - login classes" "cat /etc/login.conf 2>/dev/null"
run_cmd "Users - sudoers" "cat /usr/local/etc/sudoers 2>/dev/null"
run_cmd "Users - authorized_keys files" "find /root /home -maxdepth 4 -type f -name authorized_keys 2>/dev/null | while IFS= read -r f; do echo --- \"\$f\"; cat \"\$f\"; done"
run_cmd "Users - SSH daemon config" "cat /etc/ssh/sshd_config 2>/dev/null"

# pfSense-specific configuration references
run_cmd "pfSense - Config history/listing" "ls -lah /cf/conf 2>/dev/null && ls -lah /cf/conf/backup 2>/dev/null"
run_cmd "pfSense - OpenVPN files" "ls -lah /var/etc/openvpn 2>/dev/null"
run_cmd "pfSense - IPsec files" "ls -lah /var/etc/ipsec 2>/dev/null"
run_cmd "pfSense - Unbound DNS files" "ls -lah /var/unbound 2>/dev/null"
run_cmd "pfSense - DHCP files" "ls -lah /var/dhcpd 2>/dev/null"
run_cmd "pfSense - Resolver/Services local configs" "find /var/etc -maxdepth 2 -type f 2>/dev/null | head -n 300"

# Copy key configuration files (sensitive)
mkdir -p "$OUTDIR/config" "$OUTDIR/log_tails"
copy_file_if_exists "/cf/conf/config.xml" "config/config.xml"
copy_file_if_exists "/etc/ssh/sshd_config" "config/sshd_config"
copy_file_if_exists "/etc/rc.conf" "config/rc.conf"
copy_file_if_exists "/etc/resolv.conf" "config/resolv.conf"
copy_file_if_exists "/etc/hosts" "config/hosts"
copy_file_if_exists "/usr/local/etc/sudoers" "config/sudoers"
copy_file_if_exists "/etc/crontab" "config/crontab"
copy_file_if_exists "/var/cron/tabs/root" "config/root_crontab"

# Log tails for quick triage
capture_tail_if_exists "/var/log/system.log" "log_tails/system.log.tail" "400"
capture_tail_if_exists "/var/log/filter.log" "log_tails/filter.log.tail" "400"
capture_tail_if_exists "/var/log/auth.log" "log_tails/auth.log.tail" "400"
capture_tail_if_exists "/var/log/vpn.log" "log_tails/vpn.log.tail" "400"
capture_tail_if_exists "/var/log/dhcpd.log" "log_tails/dhcpd.log.tail" "400"
capture_tail_if_exists "/var/log/resolver.log" "log_tails/resolver.log.tail" "400"
capture_tail_if_exists "/var/log/nginx/error.log" "log_tails/nginx_error.log.tail" "400"

# Permissions and integrity quick checks
run_cmd "Security - SUID/SGID files" "find / -xdev \\( -perm -4000 -o -perm -2000 \\) -type f 2>/dev/null"
run_cmd "Security - Writable by others (top level paths)" "find /bin /sbin /usr/bin /usr/sbin /usr/local/bin /usr/local/sbin -type f -perm -0002 2>/dev/null"
run_cmd "Security - rc scripts" "ls -lah /etc/rc* /usr/local/etc/rc.d 2>/dev/null"
run_cmd "Security - SSH host keys fingerprints" "ssh-keygen -lf /etc/ssh/ssh_host_rsa_key.pub 2>/dev/null; ssh-keygen -lf /etc/ssh/ssh_host_ecdsa_key.pub 2>/dev/null; ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub 2>/dev/null"

# Build a simple file manifest
(
    cd "$OUTDIR" || exit 1
    find . -type f -print0 | xargs -0 sha256 >SHA256SUMS.txt 2>/dev/null || true
) 

{
    printf 'Collection complete: %s\n' "$(date '+%F %T')"
    printf 'Primary report: %s/inventory.txt\n' "$OUTDIR"
    printf 'Sensitive config copies may exist in: %s/config\n' "$OUTDIR"
} >>"$OUTDIR/README.txt"

log "Collection complete."
log "Report: $OUTDIR/inventory.txt"
log "Bundle this directory for offline analysis if needed."
