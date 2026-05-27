#!/bin/bash

####################################################################################################
# Monitoring Stack Helper Script
# 
# Mempermudah deployment, maintenance, dan troubleshooting Prometheus + Grafana
# 
# Usage:
#   ./monitoring-helper.sh [command]
#   
# Commands:
#   start              - Start monitoring stack
#   stop               - Stop monitoring stack
#   restart            - Restart monitoring stack
#   logs [service]     - View logs
#   status             - Show container status
#   configure          - Configure production server IP
#   backup             - Backup Prometheus & Grafana data
#   restore [file]     - Restore from backup
#   cleanup            - Stop & remove volumes
#   health-check       - Test connectivity
#   help               - Show this help message
#
####################################################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_PROD="$SCRIPT_DIR/docker-compose-node-exporter.yml"
COMPOSE_MON="$SCRIPT_DIR/docker-compose-monitoring.yml"
PROM_CONFIG="$SCRIPT_DIR/monitoring/prometheus.yml"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="$SCRIPT_DIR/backups"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

####################################################################################################
# Helper Functions
####################################################################################################

log_info() {
    echo -e "${BLUE}ℹ️  $@${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $@${NC}"
}

log_warn() {
    echo -e "${YELLOW}⚠️  $@${NC}"
}

log_error() {
    echo -e "${RED}❌ $@${NC}"
}

check_docker() {
    if ! command -v docker-compose &> /dev/null; then
        log_error "docker-compose not found. Please install Docker Compose."
        exit 1
    fi
}

####################################################################################################
# Commands
####################################################################################################

cmd_start() {
    log_info "Starting monitoring stack..."
    check_docker
    
    if [ ! -f "$PROM_CONFIG" ]; then
        log_error "Prometheus config not found: $PROM_CONFIG"
        exit 1
    fi
    
    # Check if production server IP is configured
    if grep -q '<PROD_SERVER_IP>' "$PROM_CONFIG"; then
        log_warn "Production server IP not configured in prometheus.yml"
        log_info "Run: ./monitoring-helper.sh configure"
        exit 1
    fi
    
    docker-compose -f "$COMPOSE_MON" up -d
    
    log_success "Monitoring stack started!"
    echo ""
    echo "Access points:"
    echo "  Prometheus: http://localhost:9990"
    echo "  Grafana:    http://localhost:3000 (admin/admin)"
}

cmd_stop() {
    log_info "Stopping monitoring stack..."
    check_docker
    docker-compose -f "$COMPOSE_MON" down
    log_success "Monitoring stack stopped!"
}

cmd_restart() {
    cmd_stop
    sleep 2
    cmd_start
}

cmd_logs() {
    check_docker
    local service="${1:-prometheus}"
    docker-compose -f "$COMPOSE_MON" logs -f "$service"
}

cmd_status() {
    check_docker
    echo ""
    log_info "Monitoring Stack Status:"
    docker-compose -f "$COMPOSE_MON" ps
    
    echo ""
    log_info "Production Server Status:"
    docker-compose -f "$COMPOSE_PROD" ps 2>/dev/null || log_warn "Node exporter not running"
}

cmd_configure() {
    log_info "Configuring production server IP..."
    
    read -p "Enter production server IP address (e.g., 192.168.1.100): " prod_ip
    
    if [ -z "$prod_ip" ]; then
        log_error "IP address cannot be empty"
        exit 1
    fi
    
    # Validate IP format (simple check)
    if ! echo "$prod_ip" | grep -qE '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$|^[a-zA-Z0-9\.-]+$'; then
        log_error "Invalid IP address format"
        exit 1
    fi
    
    # Backup original config
    cp "$PROM_CONFIG" "$PROM_CONFIG.backup.$TIMESTAMP"
    log_info "Backed up config to: $PROM_CONFIG.backup.$TIMESTAMP"
    
    # Replace placeholder
    sed -i "s|<PROD_SERVER_IP>|$prod_ip|g" "$PROM_CONFIG"
    log_success "Updated production server IP to: $prod_ip"
    
    # Reload prometheus if running
    if docker-compose -f "$COMPOSE_MON" ps prometheus | grep -q "Up"; then
        log_info "Reloading Prometheus config..."
        curl -X POST http://localhost:9990/-/reload 2>/dev/null || log_warn "Failed to reload (Prometheus may not be running)"
        log_success "Config reloaded!"
    fi
}

cmd_backup() {
    log_info "Creating backup..."
    
    mkdir -p "$BACKUP_DIR"
    
    # Backup Prometheus data
    log_info "Backing up Prometheus data..."
    docker run --rm -v prometheus_data:/data -v "$BACKUP_DIR:/backup" \
        busybox tar czf "/backup/prometheus_$TIMESTAMP.tar.gz" /data 2>/dev/null || {
        log_warn "Prometheus volume not found or empty"
    }
    
    # Backup Grafana data
    log_info "Backing up Grafana data..."
    docker run --rm -v grafana_storage:/data -v "$BACKUP_DIR:/backup" \
        busybox tar czf "/backup/grafana_$TIMESTAMP.tar.gz" /data 2>/dev/null || {
        log_warn "Grafana volume not found or empty"
    }
    
    # Backup configs
    cp "$PROM_CONFIG" "$BACKUP_DIR/prometheus_$TIMESTAMP.yml"
    cp "$COMPOSE_MON" "$BACKUP_DIR/docker-compose-monitoring_$TIMESTAMP.yml"
    
    log_success "Backup completed!"
    echo "Backup location: $BACKUP_DIR"
    ls -lh "$BACKUP_DIR" | tail -5
}

cmd_restore() {
    local backup_file="${1}"
    
    if [ -z "$backup_file" ]; then
        log_error "Backup file not specified"
        echo "Usage: ./monitoring-helper.sh restore /path/to/backup.tar.gz"
        exit 1
    fi
    
    if [ ! -f "$backup_file" ]; then
        log_error "Backup file not found: $backup_file"
        exit 1
    fi
    
    read -p "This will overwrite current data. Continue? (y/N): " confirm
    if [ "$confirm" != "y" ]; then
        log_warn "Restore cancelled"
        exit 0
    fi
    
    log_info "Stopping monitoring stack..."
    cmd_stop
    
    log_info "Restoring from backup: $backup_file"
    
    # Determine which volume to restore based on filename
    if echo "$backup_file" | grep -q prometheus; then
        docker run --rm -v prometheus_data:/data -v "$(cd "$(dirname "$backup_file")" && pwd):/backup" \
            busybox tar xzf "/backup/$(basename "$backup_file")" -C /
        log_success "Prometheus data restored"
    elif echo "$backup_file" | grep -q grafana; then
        docker run --rm -v grafana_storage:/data -v "$(cd "$(dirname "$backup_file")" && pwd):/backup" \
            busybox tar xzf "/backup/$(basename "$backup_file")" -C /
        log_success "Grafana data restored"
    fi
    
    log_info "Starting monitoring stack..."
    cmd_start
}

cmd_cleanup() {
    read -p "This will remove all containers and volumes. Continue? (y/N): " confirm
    if [ "$confirm" != "y" ]; then
        log_warn "Cleanup cancelled"
        exit 0
    fi
    
    log_info "Removing monitoring stack..."
    docker-compose -f "$COMPOSE_MON" down -v
    
    log_success "Cleanup completed!"
}

cmd_health_check() {
    log_info "Performing health checks..."
    echo ""
    
    # Check Prometheus
    if curl -s http://localhost:9990/-/healthy > /dev/null; then
        log_success "Prometheus: OK"
    else
        log_error "Prometheus: NOT RESPONDING"
    fi
    
    # Check Grafana
    if curl -s http://localhost:3000/api/health > /dev/null; then
        log_success "Grafana: OK"
    else
        log_error "Grafana: NOT RESPONDING"
    fi
    
    # Check scrape targets
    log_info "Scrape targets:"
    curl -s http://localhost:9990/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, instance: .labels.instance, state: .health}' 2>/dev/null || log_warn "Could not fetch targets"
    
    echo ""
    log_info "Health check completed!"
}

cmd_help() {
    cat << EOF

${BLUE}Monitoring Stack Helper Script${NC}

Usage:
  ./monitoring-helper.sh [command]

Commands:
  ${YELLOW}start${NC}              - Start monitoring stack (Prometheus + Grafana)
  ${YELLOW}stop${NC}               - Stop monitoring stack
  ${YELLOW}restart${NC}            - Restart monitoring stack
  ${YELLOW}logs${NC} [service]     - View logs (default: prometheus)
                          Example: ./monitoring-helper.sh logs grafana
  ${YELLOW}status${NC}             - Show container and volume status
  ${YELLOW}configure${NC}          - Configure production server IP (interactive)
  ${YELLOW}backup${NC}             - Backup Prometheus & Grafana data
  ${YELLOW}restore${NC} [file]     - Restore from backup file
  ${YELLOW}cleanup${NC}            - Stop & remove all volumes (⚠️  DESTRUCTIVE)
  ${YELLOW}health-check${NC}       - Test service connectivity
  ${YELLOW}help${NC}              - Show this help message

Examples:
  # Start monitoring
  ./monitoring-helper.sh start
  
  # Configure production server
  ./monitoring-helper.sh configure
  
  # View logs
  ./monitoring-helper.sh logs prometheus
  ./monitoring-helper.sh logs grafana
  
  # Backup before update
  ./monitoring-helper.sh backup
  
  # Health check
  ./monitoring-helper.sh health-check

Environment:
  COMPOSE_FILE     - Docker Compose config location
  BACKUP_DIR       - Backup directory (default: ./backups)

EOF
}

####################################################################################################
# Main
####################################################################################################

main() {
    local command="${1:-help}"
    
    case "$command" in
        start)
            cmd_start
            ;;
        stop)
            cmd_stop
            ;;
        restart)
            cmd_restart
            ;;
        logs)
            cmd_logs "$2"
            ;;
        status)
            cmd_status
            ;;
        configure)
            cmd_configure
            ;;
        backup)
            cmd_backup
            ;;
        restore)
            cmd_restore "$2"
            ;;
        cleanup)
            cmd_cleanup
            ;;
        health-check)
            cmd_health_check
            ;;
        help)
            cmd_help
            ;;
        *)
            log_error "Unknown command: $command"
            cmd_help
            exit 1
            ;;
    esac
}

main "$@"
