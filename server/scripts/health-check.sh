#!/bin/bash

# Health Check Script for Omi RSS Server
# Used by Docker and monitoring systems

set -e

# Configuration
APP_URL="${APP_URL:-http://localhost:3000}"
TIMEOUT="${TIMEOUT:-5}"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check functions
check_app() {
    echo -n "Checking application health... "
    if curl -sf --max-time $TIMEOUT "$APP_URL/health" > /dev/null; then
        echo -e "${GREEN}OK${NC}"
        return 0
    else
        echo -e "${RED}FAILED${NC}"
        return 1
    fi
}

check_database() {
    echo -n "Checking database connection... "
    if docker exec omi_rss_postgres pg_isready -U ${POSTGRES_USER:-omi_user} > /dev/null 2>&1; then
        echo -e "${GREEN}OK${NC}"
        return 0
    else
        echo -e "${RED}FAILED${NC}"
        return 1
    fi
}

check_redis() {
    echo -n "Checking Redis connection... "
    if docker exec omi_rss_redis redis-cli ping > /dev/null 2>&1; then
        echo -e "${GREEN}OK${NC}"
        return 0
    else
        echo -e "${RED}FAILED${NC}"
        return 1
    fi
}

check_disk_space() {
    echo -n "Checking disk space... "
    USAGE=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
    if [ $USAGE -lt 90 ]; then
        echo -e "${GREEN}OK${NC} (${USAGE}% used)"
        return 0
    else
        echo -e "${YELLOW}WARNING${NC} (${USAGE}% used)"
        return 1
    fi
}

check_memory() {
    echo -n "Checking memory usage... "
    USAGE=$(free | awk 'NR==2 {printf "%.0f", $3/$2 * 100}')
    if [ $USAGE -lt 90 ]; then
        echo -e "${GREEN}OK${NC} (${USAGE}% used)"
        return 0
    else
        echo -e "${YELLOW}WARNING${NC} (${USAGE}% used)"
        return 1
    fi
}

# Main health check
main() {
    echo "Running Omi RSS health checks..."
    echo "================================"
    
    FAILED=0
    
    check_app || FAILED=$((FAILED + 1))
    check_database || FAILED=$((FAILED + 1))
    check_redis || FAILED=$((FAILED + 1))
    check_disk_space || FAILED=$((FAILED + 1))
    check_memory || FAILED=$((FAILED + 1))
    
    echo "================================"
    
    if [ $FAILED -eq 0 ]; then
        echo -e "${GREEN}All checks passed!${NC}"
        exit 0
    else
        echo -e "${RED}$FAILED checks failed!${NC}"
        exit 1
    fi
}

# Run specific check if requested
case "${1:-all}" in
    "app")
        check_app
        ;;
    "database")
        check_database
        ;;
    "redis")
        check_redis
        ;;
    "disk")
        check_disk_space
        ;;
    "memory")
        check_memory
        ;;
    *)
        main
        ;;
esac