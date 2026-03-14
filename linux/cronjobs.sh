#!/usr/bin/env bash
#
# cronjobs.sh - List all cronjobs on a system
#
# Usage:
#   ./cronjobs.sh
#
# Description:
#   This script lists all cron jobs for all users and system-wide cron jobs.
#
# Author: Dan McCarthy
# Date: 3/13/2026

# ===
# Output cronjobs for an associated user.
# 
# Parameters:
#   User to check cronjobs
# ===
function list_crontab() {
    echo -e "\n=== Crontab jobs for $1 ==="
    crontab -l -u "$1" 2>/dev/null
}

# === List Cron Jobs from Crontab for All Users ===
echo -e "\n=== Listing Cron Jobs from Crontab for All Users ==="
for user in $(getent passwd | cut -d: -f1); do
    list_crontab "$user"
done

# === List System Cron Jobs from cron.d, cron.daily, cron.weekly, cron.monthly ===
echo -e "\n=== Jobs from /etc/cron.d/ ==="
cat /etc/cron.d/* 2>/dev/null

echo -e "\n=== Jobs from /etc/cron.daily/ ==="
for f in /etc/cron.daily/*; do
    [ -f "$f" ] && echo "cron.daily: $f"
done

echo -e "\n=== Jobs from /etc/cron.weekly/ ==="
for f in /etc/cron.weekly/*; do
    [ -f "$f" ] && echo "cron.weekly: $f"
done

echo -e "\n=== Jobs from /etc/cron.monthly/ ==="
for f in /etc/cron.monthly/*; do
    [ -f "$f" ] && echo "cron.monthly: $f"
done

echo -e "\n=== User cron jobs from /var/spool/cron/crontabs ==="
if [ -d /var/spool/cron/crontabs ]; then
    for file in /var/spool/cron/crontabs/*; do
        user=$(basename "$file")
        echo "Cron jobs for user: $user"
        cat "$file" 2>/dev/null
    done
fi