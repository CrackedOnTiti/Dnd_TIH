#!/bin/bash

# Use provided file or default to latest
BACKUP_FILE="${1:-backups/latest.sql}"

if [ ! -f "$BACKUP_FILE" ]; then
    echo "Backup file not found: $BACKUP_FILE"
    echo "Usage: ./restore.sh [backup_file]"
    echo "Example: ./restore.sh backups/backup_20240124_153000.sql"
    exit 1
fi

echo "Restoring from $BACKUP_FILE..."
docker exec -i dnd_tih-db-1 psql -U dnd_user dnd_db < "$BACKUP_FILE"

if [ $? -eq 0 ]; then
    echo "Restore complete!"
else
    echo "Restore failed!"
    exit 1
fi
