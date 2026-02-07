#!/bin/bash

echo "=== DnD TIH Shutdown ==="

# Check if -v flag is passed
if [[ "$*" == *"-v"* ]]; then
    echo "WARNING: -v flag detected! This will DELETE the database volume."
    echo "A backup will be created first."
    echo ""
    read -p "Are you sure? (y/N): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo "Aborted."
        exit 0
    fi
fi

# Run backup first
./backup.sh

if [ $? -eq 0 ]; then
    echo ""
    echo "Shutting down containers..."
    docker-compose down "$@"
    echo "Done!"
else
    echo "Backup failed! Aborting shutdown."
    echo "If you want to shutdown anyway, use: docker-compose down"
    exit 1
fi
