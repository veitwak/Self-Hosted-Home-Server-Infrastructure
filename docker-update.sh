#!/bin/bash

echo "Starting global Docker update"
BASE_DIR="/home/tim"
STORAGE_DIR="/mnt/storage"

# Finds all Compose files in ${BASE_DIR} and Nextcloud
find ${BASE_DIR} ${STORAGE_DIR}/nextcloud -maxdepth 3 -type f \( -name "docker-compose.yml" -o -name "docker-compose.yaml" \) | grep -v "guest lectures" | while read -r compose_file; do

    SERVICE_DIR=$(dirname "$compose_file")
    SERVICE_NAME=$(basename "$SERVICE_DIR")

    echo "Checking for updates for: $SERVICE_NAME"

    cd "$SERVICE_DIR" || continue

    # 1. Download the latest version
    docker compose pull

    # 2. Start containers with the new version (old ones are replaced automatically)
    docker compose up -d

done

echo "Cleaning up old, no longer needed versions"
docker image prune -af

echo "All updates completed!"
