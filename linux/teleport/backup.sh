#!/usr/bin/env bash
#
# backup.sh - Backup teleport configuration
#
# Usage:
#   backup.sh <user>@<ip>
#
# Description:
#   This will create a backup of a locally installed teleport service. It
#   creates a 'teleport-backup_<time>.tar.gz' file with all of the imporant
#   directories used by teleport. These can then be reloaded using ./load_backup.sh.
#
# Author: Dan McCarthy
# Date: 3/3/2026

# check that ssh destination is provided
if [[ $# -ne 1 ]]; then
    echo "Please provide argument: './backup.sh <user>@<ip>'"
    exit 1
fi

TARGET="$1"
BACKUP_NAME="teleport-backup_$(date +%s).tar.gz"

# === Read password and backup files locally ===
read -p "Enter Password: " PASSWORD
sshpass -p "$PASSWORD" ssh "$TARGET" "sudo tar czpf ~/$BACKUP_NAME /etc/teleport.yaml /var/lib/teleport /opt/teleport"

# === Copy backup to system ===
echo "This will take a second..."
sshpass -p "$PASSWORD" scp "$TARGET:~/$BACKUP_NAME" .