#!/bin/bash

# Backup Script for Omi RSS Server
# Supports local and S3 backups

set -e

# Configuration
BACKUP_DIR="${BACKUP_DIR:-./backups}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"
S3_BUCKET="${BACKUP_S3_BUCKET:-}"
POSTGRES_CONTAINER="${POSTGRES_CONTAINER:-omi_rss_postgres}"
REDIS_CONTAINER="${REDIS_CONTAINER:-omi_rss_redis}"

# Load environment
if [ -f ".env.production" ]; then
    export $(cat .env.production | grep -v '^#' | xargs)
fi

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Logging
log() {
    echo -e "${GREEN}[BACKUP]${NC} $(date +'%Y-%m-%d %H:%M:%S') - $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $(date +'%Y-%m-%d %H:%M:%S') - $1"
    exit 1
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date +'%Y-%m-%d %H:%M:%S') - $1"
}

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Backup functions
backup_database() {
    log "Starting database backup..."
    
    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    DB_BACKUP_FILE="$BACKUP_DIR/postgres-$TIMESTAMP.sql"
    
    # Dump database
    docker exec "$POSTGRES_CONTAINER" pg_dump \
        -U "${POSTGRES_USER:-omi_user}" \
        "${POSTGRES_DB:-omi_rss}" \
        > "$DB_BACKUP_FILE"
    
    # Compress backup
    gzip "$DB_BACKUP_FILE"
    DB_BACKUP_FILE="$DB_BACKUP_FILE.gz"
    
    log "Database backup completed: $DB_BACKUP_FILE"
    echo "$DB_BACKUP_FILE"
}

backup_redis() {
    log "Starting Redis backup..."
    
    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    REDIS_BACKUP_FILE="$BACKUP_DIR/redis-$TIMESTAMP.rdb"
    
    # Save Redis data
    docker exec "$REDIS_CONTAINER" redis-cli BGSAVE
    
    # Wait for save to complete
    sleep 5
    
    # Copy dump file
    docker cp "$REDIS_CONTAINER:/data/dump.rdb" "$REDIS_BACKUP_FILE"
    
    # Compress backup
    gzip "$REDIS_BACKUP_FILE"
    REDIS_BACKUP_FILE="$REDIS_BACKUP_FILE.gz"
    
    log "Redis backup completed: $REDIS_BACKUP_FILE"
    echo "$REDIS_BACKUP_FILE"
}

backup_uploads() {
    log "Starting uploads backup..."
    
    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    UPLOADS_BACKUP_FILE="$BACKUP_DIR/uploads-$TIMESTAMP.tar.gz"
    
    # Create tar archive
    tar -czf "$UPLOADS_BACKUP_FILE" -C . uploads/
    
    log "Uploads backup completed: $UPLOADS_BACKUP_FILE"
    echo "$UPLOADS_BACKUP_FILE"
}

backup_config() {
    log "Starting configuration backup..."
    
    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    CONFIG_BACKUP_FILE="$BACKUP_DIR/config-$TIMESTAMP.tar.gz"
    
    # Backup configuration files
    tar -czf "$CONFIG_BACKUP_FILE" \
        .env.production \
        docker-compose.prod.yml \
        nginx/conf.d/ \
        nginx/ssl/*.pem \
        2>/dev/null || true
    
    log "Configuration backup completed: $CONFIG_BACKUP_FILE"
    echo "$CONFIG_BACKUP_FILE"
}

# Upload to S3
upload_to_s3() {
    local FILE=$1
    
    if [ -z "$S3_BUCKET" ]; then
        warning "S3 bucket not configured, skipping upload"
        return
    fi
    
    if ! command -v aws &> /dev/null; then
        warning "AWS CLI not installed, skipping S3 upload"
        return
    fi
    
    log "Uploading $FILE to S3..."
    
    aws s3 cp "$FILE" "s3://$S3_BUCKET/$(basename $FILE)" \
        --storage-class STANDARD_IA
    
    if [ $? -eq 0 ]; then
        log "Upload successful: s3://$S3_BUCKET/$(basename $FILE)"
    else
        warning "S3 upload failed for $FILE"
    fi
}

# Cleanup old backups
cleanup_old_backups() {
    log "Cleaning up old backups..."
    
    # Local cleanup
    find "$BACKUP_DIR" -name "*.gz" -mtime +$BACKUP_RETENTION_DAYS -delete
    
    # S3 cleanup
    if [ -n "$S3_BUCKET" ] && command -v aws &> /dev/null; then
        CUTOFF_DATE=$(date -d "$BACKUP_RETENTION_DAYS days ago" +%Y-%m-%d)
        
        aws s3 ls "s3://$S3_BUCKET/" | while read -r line; do
            FILE_DATE=$(echo $line | awk '{print $1}')
            FILE_NAME=$(echo $line | awk '{print $4}')
            
            if [[ "$FILE_DATE" < "$CUTOFF_DATE" ]]; then
                aws s3 rm "s3://$S3_BUCKET/$FILE_NAME"
                log "Deleted old S3 backup: $FILE_NAME"
            fi
        done
    fi
    
    log "Cleanup completed"
}

# Restore functions
restore_database() {
    local BACKUP_FILE=$1
    
    log "Restoring database from $BACKUP_FILE..."
    
    # Decompress if needed
    if [[ "$BACKUP_FILE" == *.gz ]]; then
        gunzip -c "$BACKUP_FILE" | docker exec -i "$POSTGRES_CONTAINER" \
            psql -U "${POSTGRES_USER:-omi_user}" "${POSTGRES_DB:-omi_rss}"
    else
        docker exec -i "$POSTGRES_CONTAINER" \
            psql -U "${POSTGRES_USER:-omi_user}" "${POSTGRES_DB:-omi_rss}" < "$BACKUP_FILE"
    fi
    
    log "Database restore completed"
}

restore_redis() {
    local BACKUP_FILE=$1
    
    log "Restoring Redis from $BACKUP_FILE..."
    
    # Decompress if needed
    if [[ "$BACKUP_FILE" == *.gz ]]; then
        gunzip -c "$BACKUP_FILE" > /tmp/dump.rdb
        BACKUP_FILE="/tmp/dump.rdb"
    fi
    
    # Stop Redis
    docker-compose -f docker-compose.prod.yml stop redis
    
    # Copy dump file
    docker cp "$BACKUP_FILE" "$REDIS_CONTAINER:/data/dump.rdb"
    
    # Start Redis
    docker-compose -f docker-compose.prod.yml start redis
    
    log "Redis restore completed"
}

# List backups
list_backups() {
    log "Available backups:"
    echo ""
    
    # Local backups
    echo "Local backups:"
    ls -la "$BACKUP_DIR"/*.gz 2>/dev/null || echo "  No local backups found"
    echo ""
    
    # S3 backups
    if [ -n "$S3_BUCKET" ] && command -v aws &> /dev/null; then
        echo "S3 backups:"
        aws s3 ls "s3://$S3_BUCKET/" --human-readable
    fi
}

# Main backup function
perform_backup() {
    log "Starting Omi RSS backup..."
    
    # Create backups
    DB_BACKUP=$(backup_database)
    REDIS_BACKUP=$(backup_redis)
    UPLOADS_BACKUP=$(backup_uploads)
    CONFIG_BACKUP=$(backup_config)
    
    # Upload to S3
    if [ "${UPLOAD_TO_S3:-true}" = "true" ]; then
        upload_to_s3 "$DB_BACKUP"
        upload_to_s3 "$REDIS_BACKUP"
        upload_to_s3 "$UPLOADS_BACKUP"
        upload_to_s3 "$CONFIG_BACKUP"
    fi
    
    # Cleanup old backups
    cleanup_old_backups
    
    log "Backup completed successfully!"
    log "Files created:"
    log "  - $DB_BACKUP"
    log "  - $REDIS_BACKUP"
    log "  - $UPLOADS_BACKUP"
    log "  - $CONFIG_BACKUP"
}

# Handle command line arguments
case "${1:-backup}" in
    "backup")
        perform_backup
        ;;
    "restore-db")
        if [ -z "$2" ]; then
            error "Please provide backup file path"
        fi
        restore_database "$2"
        ;;
    "restore-redis")
        if [ -z "$2" ]; then
            error "Please provide backup file path"
        fi
        restore_redis "$2"
        ;;
    "list")
        list_backups
        ;;
    "cleanup")
        cleanup_old_backups
        ;;
    *)
        echo "Usage: $0 {backup|restore-db <file>|restore-redis <file>|list|cleanup}"
        exit 1
        ;;
esac