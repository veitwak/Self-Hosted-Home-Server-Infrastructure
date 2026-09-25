#!/bin/bash

set -u

# Server config backup: Backs up configurations, compose files, and secrets.
# Excludes large user data.

DEST="/mnt/usb_backup/server_backup"
BASE_DIR="/home/tim"
STORAGE_DIR="/mnt/storage"
DRY_RUN=0

# Usage:
# ./server-backup.sh --dry-run  -> Dry run (shows what would be done)
# ./server-backup.sh            -> Real backup

if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=1
    echo "========================================"
    echo "DRY-RUN MODE"
    echo "NO containers will be stopped."
    echo "NO files will be written."
    echo "========================================"
fi

# USB mount check
if ! mountpoint -q /mnt/usb_backup; then
    echo "ERROR: /mnt/usb_backup is not mounted."
    echo "Backup aborted."
    exit 1
fi

mkdir -p "$DEST"

# Helper functions
copy_file() {
    local source="$1"
    local target="$2"

    if [[ ! -f "$source" ]]; then
        echo "Not found: $source"
        return 0
    fi

    echo "$source"

    if [[ "$DRY_RUN" -eq 1 ]]; then
        return 0
    fi

    mkdir -p "$(dirname "$target")"
    cp -a "$source" "$target"
}

sync_dir() {
    local source="$1"
    local target="$2"
    shift 2

    if [[ ! -d "$source" ]]; then
        echo "Not found: $source"
        return 0
    fi

    echo "$source"

    local args=(
        -a
        -h
    )

    for exclude in "$@"; do
        args+=("--exclude=$exclude")
    done

    if [[ "$DRY_RUN" -eq 1 ]]; then
        rsync -n --stats "${args[@]}" "$source/" "$target/"
    else
        mkdir -p "$target"
        rsync "${args[@]}" "$source/" "$target/"
    fi
}

# Start backup process
echo
echo "========================================"
echo "SERVER BACKUP"
echo "========================================"
echo "Source: Server"
echo "Destination: $DEST"
echo

# Docker Compose Projects
echo "========================================"
echo "DOCKER COMPOSE"
echo "========================================"

PROJECTS=(
    "${BASE_DIR}/home_assistant"
    "${BASE_DIR}/immich"
    "${BASE_DIR}/pihole"
    "${BASE_DIR}/frigate"
    "${BASE_DIR}/jellyfin"
    "${BASE_DIR}/ghostfolio"
    "${BASE_DIR}/kiwix"
    "${BASE_DIR}/llm"
    "${BASE_DIR}/comfyui-setup"
    "${STORAGE_DIR}/nextcloud"
)

for project in "${PROJECTS[@]}"; do

    project_name="$(basename "$project")"
    target="$DEST/projects/$project_name"

    echo
    echo "----- $project_name -----"

    copy_file "$project/docker-compose.yml" "$target/docker-compose.yml"
    copy_file "$project/docker-compose.yaml" "$target/docker-compose.yaml"
    copy_file "$project/compose.yml" "$target/compose.yml"
    copy_file "$project/compose.yaml" "$target/compose.yaml"
    copy_file "$project/.env" "$target/.env"

done

# Home Assistant
echo
echo "========================================"
echo "HOME ASSISTANT"
echo "========================================"

sync_dir \
    "${STORAGE_DIR}/homeassistant/config" \
    "$DEST/config/homeassistant"

# Frigate
echo
echo "========================================"
echo "FRIGATE"
echo "========================================"

sync_dir \
    "${BASE_DIR}/frigate/config" \
    "$DEST/config/frigate" \
    "*.db" \
    "*.db-*"

# Pi-hole
echo
echo "========================================"
echo "PI-HOLE"
echo "========================================"

sync_dir \
    "${BASE_DIR}/pihole/etc-pihole" \
    "$DEST/config/pihole/etc-pihole" \
    "gravity.db" \
    "gravity_old.db" \
    "pihole-FTL.db" \
    "pihole-FTL.db-*" \
    "dhcp.leases"

sync_dir \
    "${BASE_DIR}/pihole/etc-dnsmasq.d" \
    "$DEST/config/pihole/etc-dnsmasq.d"

# Jellyfin
echo
echo "========================================"
echo "JELLYFIN"
echo "========================================"

sync_dir \
    "${STORAGE_DIR}/jellyfin/config" \
    "$DEST/config/jellyfin"

# Do NOT backup cache

# Immich
echo
echo "========================================"
echo "IMMICH"
echo "========================================"

# Compose + .env backed up above.
# Uploads, ML cache, Redis volume, and the main PostgreSQL database are intentionally skipped.

echo "Immich Uploads / PostgreSQL / ML Cache are skipped."

# LLM / Open WebUI
echo
echo "========================================"
echo "LLM / OPEN WEBUI"
echo "========================================"

# Do NOT backup Ollama models (~17 GB): ${BASE_DIR}/llm/ollama_data
# Open WebUI data is small, backup everything except temp/cache files.

sync_dir \
    "${BASE_DIR}/llm/open-webui_data" \
    "$DEST/config/open-webui" \
    "cache" \
    "logs"

echo "Ollama models will NOT be backed up."

# ComfyUI
echo
echo "========================================"
echo "COMFYUI"
echo "========================================"

copy_file \
    "${BASE_DIR}/comfyui-setup/Caddyfile" \
    "$DEST/config/comfyui/Caddyfile"

echo "ComfyUI models / outputs will NOT be backed up."

# Nextcloud
echo
echo "========================================"
echo "NEXTCLOUD"
echo "========================================"

# Essential Nextcloud configuration
sync_dir \
    "${STORAGE_DIR}/nextcloud/html/config" \
    "$DEST/config/nextcloud/config"

# Custom apps may be needed during restore
sync_dir \
    "${STORAGE_DIR}/nextcloud/html/custom_apps" \
    "$DEST/config/nextcloud/custom_apps"

echo "Nextcloud data/ will NOT be backed up."
echo "MariaDB database will NOT be backed up as a file copy."

# Nginx Proxy Manager
echo
echo "========================================"
echo "NGINX PROXY MANAGER"
echo "========================================"

NPM_CONTAINER="nginx-proxy-manager"
NPM_WAS_RUNNING=0

if docker ps --format '{{.Names}}' | grep -qx "$NPM_CONTAINER"; then
    NPM_WAS_RUNNING=1
fi

if [[ "$DRY_RUN" -eq 1 ]]; then

    echo "Would stop container: $NPM_CONTAINER"
    echo "Would backup: /opt/nginx-pm/data"
    echo "Would backup: /opt/nginx-pm/letsencrypt"

else

    if [[ "$NPM_WAS_RUNNING" -eq 1 ]]; then
        echo "Stopping Nginx Proxy Manager..."
        docker stop "$NPM_CONTAINER" >/dev/null || {
            echo "ERROR: Nginx Proxy Manager could not be stopped."
            exit 1
        }
    fi

    # Restart container on exit if it was running
    cleanup_npm() {
        if [[ "$NPM_WAS_RUNNING" -eq 1 ]]; then
            echo
            echo "Restarting Nginx Proxy Manager..."
            docker start "$NPM_CONTAINER" >/dev/null || \
                echo "WARNING: Nginx Proxy Manager could not be started!"
        fi
    }

    trap cleanup_npm EXIT

    sync_dir \
        "/opt/nginx-pm/data" \
        "$DEST/config/nginx-proxy-manager/data"

    sync_dir \
        "/opt/nginx-pm/letsencrypt" \
        "$DEST/config/nginx-proxy-manager/letsencrypt"

    cleanup_npm
    trap - EXIT
fi

# Docker System Information
echo
echo "========================================"
echo "DOCKER INFORMATION"
echo "========================================"

INFO="$DEST/server_info"

if [[ "$DRY_RUN" -eq 0 ]]; then

    mkdir -p "$INFO"

    docker version \
        > "$INFO/docker-version.txt" 2>&1 || true

    docker compose version \
        > "$INFO/docker-compose-version.txt" 2>&1 || true

    docker ps -a \
        > "$INFO/docker-containers.txt" 2>&1 || true

    docker volume ls \
        > "$INFO/docker-volumes.txt" 2>&1 || true

    docker images \
        > "$INFO/docker-images.txt" 2>&1 || true

    # Document Compose projects and mounts
    docker ps -aq | while read -r c; do
        docker inspect "$c"
    done > "$INFO/docker-inspect.json" 2>/dev/null || true

fi

# Server Configuration
echo
echo "========================================"
echo "SERVER CONFIGURATION"
echo "========================================"

copy_file \
    "/etc/docker/daemon.json" \
    "$DEST/server_config/etc/docker/daemon.json"

copy_file \
    "/etc/fstab" \
    "$DEST/server_config/etc/fstab"

copy_file \
    "/etc/hostname" \
    "$DEST/server_config/etc/hostname"

copy_file \
    "/etc/hosts" \
    "$DEST/server_config/etc/hosts"

# Completion
echo
echo "========================================"
echo "BACKUP COMPLETED"
echo "========================================"

if [[ "$DRY_RUN" -eq 0 ]]; then
    echo
    echo "Backup size:"
    du -sh "$DEST" 2>/dev/null || true

    echo
    echo "Backup location:"
    echo "$DEST"

    echo
    echo "NOTE:"
    echo "This backup may contain passwords,"
    echo "API keys, certificates, and other secrets."
fi

echo
