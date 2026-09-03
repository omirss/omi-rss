#!/bin/bash

# Omi RSS Production Deployment Script
# Usage: ./scripts/deploy.sh [environment]

set -e

# Configuration
ENVIRONMENT=${1:-production}
COMPOSE_FILE="docker-compose.prod.yml"
ENV_FILE=".env.${ENVIRONMENT}"
BACKUP_DIR="./backups"
LOG_FILE="./logs/deploy-$(date +%Y%m%d-%H%M%S).log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
    exit 1
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Docker is installed
    if ! command -v docker &> /dev/null; then
        error "Docker is not installed"
    fi
    
    # Check if Docker Compose is installed
    if ! command -v docker-compose &> /dev/null; then
        error "Docker Compose is not installed"
    fi
    
    # Check if environment file exists
    if [ ! -f "$ENV_FILE" ]; then
        error "Environment file $ENV_FILE not found"
    fi
    
    # Check if compose file exists
    if [ ! -f "$COMPOSE_FILE" ]; then
        error "Compose file $COMPOSE_FILE not found"
    fi
    
    log "Prerequisites check passed"
}

# Create required directories
create_directories() {
    log "Creating required directories..."
    
    mkdir -p logs
    mkdir -p uploads/avatars
    mkdir -p uploads/exports
    mkdir -p backups
    mkdir -p nginx/ssl
    mkdir -p monitoring/prometheus
    mkdir -p monitoring/grafana/dashboards
    mkdir -p monitoring/grafana/datasources
    
    log "Directories created"
}

# Backup database
backup_database() {
    log "Backing up database..."
    
    # Check if postgres container is running
    if docker ps | grep -q omi_rss_postgres; then
        BACKUP_FILE="${BACKUP_DIR}/backup-$(date +%Y%m%d-%H%M%S).sql"
        
        docker exec omi_rss_postgres pg_dump -U ${POSTGRES_USER:-omi_user} ${POSTGRES_DB:-omi_rss} > "$BACKUP_FILE"
        
        if [ -f "$BACKUP_FILE" ]; then
            gzip "$BACKUP_FILE"
            log "Database backed up to ${BACKUP_FILE}.gz"
        else
            warning "Database backup failed"
        fi
    else
        warning "Database container not running, skipping backup"
    fi
}

# Build and deploy
deploy() {
    log "Starting deployment for environment: $ENVIRONMENT"
    
    # Load environment variables
    export $(cat "$ENV_FILE" | grep -v '^#' | xargs)
    
    # Pull latest images
    log "Pulling latest images..."
    docker-compose -f "$COMPOSE_FILE" pull
    
    # Build application image
    log "Building application image..."
    docker-compose -f "$COMPOSE_FILE" build --no-cache app
    
    # Run database migrations
    log "Running database migrations..."
    docker-compose -f "$COMPOSE_FILE" run --rm app npm run db:migrate
    
    # Start services
    log "Starting services..."
    docker-compose -f "$COMPOSE_FILE" up -d
    
    # Wait for services to be healthy
    log "Waiting for services to be healthy..."
    sleep 10
    
    # Check service health
    check_health
}

# Check service health
check_health() {
    log "Checking service health..."
    
    # Check app health
    if curl -f http://localhost:3000/health > /dev/null 2>&1; then
        log "Application is healthy"
    else
        error "Application health check failed"
    fi
    
    # Check database
    if docker exec omi_rss_postgres pg_isready > /dev/null 2>&1; then
        log "Database is healthy"
    else
        error "Database health check failed"
    fi
    
    # Check Redis
    if docker exec omi_rss_redis redis-cli ping > /dev/null 2>&1; then
        log "Redis is healthy"
    else
        error "Redis health check failed"
    fi
}

# Show deployment status
show_status() {
    log "Deployment status:"
    docker-compose -f "$COMPOSE_FILE" ps
    
    log "Application logs:"
    docker-compose -f "$COMPOSE_FILE" logs --tail=50 app
}

# Rollback deployment
rollback() {
    log "Rolling back deployment..."
    
    # Stop current services
    docker-compose -f "$COMPOSE_FILE" down
    
    # Restore from previous image (tagged as 'previous')
    docker tag omi_rss_app:latest omi_rss_app:failed
    docker tag omi_rss_app:previous omi_rss_app:latest
    
    # Start services with previous image
    docker-compose -f "$COMPOSE_FILE" up -d
    
    log "Rollback completed"
}

# Cleanup old resources
cleanup() {
    log "Cleaning up old resources..."
    
    # Remove unused Docker resources
    docker system prune -f --volumes
    
    # Remove old backups (keep last 30 days)
    find "$BACKUP_DIR" -name "backup-*.sql.gz" -mtime +30 -delete
    
    # Remove old logs (keep last 7 days)
    find ./logs -name "*.log" -mtime +7 -delete
    
    log "Cleanup completed"
}

# Main deployment flow
main() {
    log "Starting Omi RSS deployment script"
    
    # Check prerequisites
    check_prerequisites
    
    # Create directories
    create_directories
    
    # Backup database
    backup_database
    
    # Tag current image as previous (for rollback)
    docker tag omi_rss_app:latest omi_rss_app:previous || true
    
    # Deploy
    deploy
    
    # Show status
    show_status
    
    # Cleanup
    cleanup
    
    log "Deployment completed successfully!"
    log "Access the application at: https://${DOMAIN_NAME}"
    log "Access Grafana at: https://${DOMAIN_NAME}:3001"
}

# Handle script arguments
case "${2:-deploy}" in
    "rollback")
        rollback
        ;;
    "status")
        show_status
        ;;
    "health")
        check_health
        ;;
    "backup")
        backup_database
        ;;
    "cleanup")
        cleanup
        ;;
    *)
        main
        ;;
esac