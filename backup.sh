#!/bin/bash

# Create backups directory if it doesn't exist
mkdir -p backups

# Generate filename with timestamp
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="backups/backup_${TIMESTAMP}.sql"

echo "Backing up database..."
docker exec dnd_tih-db-1 pg_dump -U dnd_user dnd_db > "$BACKUP_FILE"

if [ $? -eq 0 ]; then
    echo "Backup saved to $BACKUP_FILE"
    # Also save as latest for easy restore
    cp "$BACKUP_FILE" backups/latest.sql
    echo "Also copied to backups/latest.sql"
else
    echo "Backup failed!"
    exit 1
fi
