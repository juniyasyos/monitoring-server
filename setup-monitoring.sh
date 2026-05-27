#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_MONITORING="$SCRIPT_DIR/docker-compose-monitoring.yml"
COMPOSE_NODE_EXPORTER="$SCRIPT_DIR/docker-compose-node-exporter.yml"
PROMETHEUS_CONFIG="$SCRIPT_DIR/monitoring/prometheus.yml"
BACKUP_SUFFIX="$(date +%Y%m%d_%H%M%S)"
DEFAULT_NODE_EXPORTER_IP="192.168.1.4"
NODE_EXPORTER_PORT="9100"
NGINX_EXPORTER_PORT="9113"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warn() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

show_help() {
    cat <<'EOF'
Usage:
    ./setup-monitoring.sh monitoring [target-server-ip]
  ./setup-monitoring.sh target-server <monitoring-server-ip>

Examples:
  ./setup-monitoring.sh monitoring 192.168.1.100
    ./setup-monitoring.sh monitoring
    ./setup-monitoring.sh target-server 192.168.1.4
  ./setup-monitoring.sh target-server 192.168.1.200

Roles:
  monitoring     Update Prometheus target IP and start Prometheus + Grafana.
  target-server  Start Node Exporter on the production/target server.

Default target server IP untuk monitoring adalah 192.168.1.4.
Target server IP untuk firewall rule exporter biasanya monitoring server, misalnya 192.168.1.4.
EOF
}

detect_compose_cmd() {
    if docker compose version >/dev/null 2>&1; then
        echo "docker compose"
    elif command -v docker-compose >/dev/null 2>&1; then
        echo "docker-compose"
    else
        return 1
    fi
}

validate_ip() {
    local ip="$1"

    if [[ "$ip" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then
        IFS='.' read -r o1 o2 o3 o4 <<< "$ip"
        for octet in "$o1" "$o2" "$o3" "$o4"; do
            if [[ "$octet" -lt 0 || "$octet" -gt 255 ]]; then
                return 1
            fi
        done
        return 0
    fi

    if [[ "$ip" =~ ^[A-Za-z0-9.-]+$ ]]; then
        return 0
    fi

    return 1
}

require_file() {
    local file_path="$1"

    if [[ ! -f "$file_path" ]]; then
        log_error "File tidak ditemukan: $file_path"
        exit 1
    fi
}

update_prometheus_target() {
    local target_ip="$1"
    local backup_file="${PROMETHEUS_CONFIG}.backup.${BACKUP_SUFFIX}"

    cp "$PROMETHEUS_CONFIG" "$backup_file"
    sed -i "/job_name: 'node-exporter-prod'/,/relabel_configs:/ s|targets: \['[^']*:9100'\]|targets: ['${target_ip}:9100']|" "$PROMETHEUS_CONFIG"

    if grep -Eq "^[[:space:]]*-[[:space:]]*targets:[[:space:]]*\['<PROD_SERVER_IP>:[0-9]+'\]" "$PROMETHEUS_CONFIG"; then
        log_warn "Masih ada placeholder <PROD_SERVER_IP> di prometheus.yml. Cek file hasil edit."
    fi

    log_success "Prometheus target diperbarui ke ${target_ip}:9100"
    log_info "Backup konfigurasi disimpan di ${backup_file}"
}

setup_monitoring_server() {
    local target_ip="$1"
    local compose_cmd="$2"

    require_file "$PROMETHEUS_CONFIG"
    require_file "$COMPOSE_MONITORING"

    if ! validate_ip "$target_ip"; then
        log_error "Target server IP tidak valid: $target_ip"
        exit 1
    fi

    update_prometheus_target "$target_ip"

    # Ensure Grafana dashboards are provisioned automatically
    if [[ -x "$SCRIPT_DIR/monitoring/provision-grafana.sh" ]]; then
        log_info "Provisioning Grafana dashboards..."
        # try download default dashboard (node exporter full)
        "$SCRIPT_DIR/monitoring/provision-grafana.sh" 1860 || log_warn "Could not download Grafana dashboard(s)"
    else
        log_warn "Provisioning script not found or not executable: $SCRIPT_DIR/monitoring/provision-grafana.sh"
    fi

    log_info "Menjalankan monitoring stack..."
    $compose_cmd -f "$COMPOSE_MONITORING" up -d

    log_info "Menjalankan testing setelah startup..."
    run_monitoring_tests "$target_ip"

    log_success "Monitoring stack aktif"
    echo ""
    echo "Akses:"
    echo "  Prometheus: http://localhost:9990"
    echo "  Grafana:    http://localhost:3000"
    echo ""
    echo "Target yang discrape: ${target_ip}:9100"
}

setup_target_server() {
    local monitoring_ip="$1"
    local compose_cmd="$2"

    require_file "$COMPOSE_NODE_EXPORTER"

    if ! validate_ip "$monitoring_ip"; then
        log_error "Monitoring server IP tidak valid: $monitoring_ip"
        exit 1
    fi

    if command -v ufw >/dev/null 2>&1; then
        if sudo ufw status >/dev/null 2>&1; then
            log_info "Membuka port 9100 hanya untuk ${monitoring_ip} via ufw..."
            sudo ufw allow from "$monitoring_ip" to any port 9100 proto tcp || true
            log_info "Membuka port 9113 hanya untuk ${monitoring_ip} via ufw..."
            sudo ufw allow from "$monitoring_ip" to any port 9113 proto tcp || true
        else
            log_warn "ufw terpasang tetapi tidak aktif, lewati konfigurasi firewall"
        fi
    else
        log_warn "ufw tidak ditemukan, lewati konfigurasi firewall"
    fi

    log_info "Menjalankan node exporter di target server..."
    $compose_cmd -f "$COMPOSE_NODE_EXPORTER" up -d

    log_info "Menjalankan testing setelah startup..."
    run_target_server_tests

    log_success "Node exporter aktif"
    echo ""
    echo "Metrics endpoint: http://localhost:9100/metrics"
    echo "Monitoring server yang diizinkan: ${monitoring_ip}"
}

run_monitoring_tests() {
    local target_ip="$1"
    local failures=0
    local node_exporter_url="http://${target_ip}:${NODE_EXPORTER_PORT}/metrics"

    if wait_for_http "http://localhost:9990/-/healthy" 30 2; then
        log_success "Test Prometheus health: OK"
    else
        log_error "Test Prometheus health: FAILED"
        failures=$((failures + 1))
    fi

    if wait_for_http "http://localhost:3000/api/health" 45 2; then
        log_success "Test Grafana health: OK"
    else
        log_error "Test Grafana health: FAILED"
        failures=$((failures + 1))
    fi

    if wait_for_scrape_target "$target_ip" 30 2; then
        log_success "Test scrape target ${target_ip}:9100: OK"
    else
        log_error "Test scrape target ${target_ip}:9100: FAILED"
        failures=$((failures + 1))
    fi

    if wait_for_http "$node_exporter_url" 30 2; then
        log_success "Test node exporter metrics endpoint ${target_ip}:9100: OK"
    else
        log_error "Test node exporter metrics endpoint ${target_ip}:9100: FAILED"
        failures=$((failures + 1))
    fi

    if wait_for_prometheus_query 'nginx_up' 30 2; then
        log_success "Test scraping data nginx_up: OK"
    else
        log_error "Test scraping data nginx_up: FAILED"
        failures=$((failures + 1))
    fi

    if wait_for_prometheus_query 'nginx_connections_active' 30 2; then
        log_success "Test scraping data nginx_connections_active: OK"
    else
        log_error "Test scraping data nginx_connections_active: FAILED"
        failures=$((failures + 1))
    fi

    if wait_for_prometheus_query 'up{job="snmp-mikrotik"}' 30 2; then
        log_success "Test scraping data Mikrotik snmp-mikrotik up: OK"
    else
        log_error "Test scraping data Mikrotik snmp-mikrotik up: FAILED"
        failures=$((failures + 1))
    fi

    if [[ "$failures" -gt 0 ]]; then
        log_error "Monitoring setup test gagal (${failures} pemeriksaan gagal)"
        exit 1
    fi
}

run_target_server_tests() {
    local failures=0

    if wait_for_http "http://localhost:9100/metrics" 20 2; then
        log_success "Test node exporter metrics endpoint: OK"
    else
        log_error "Test node exporter metrics endpoint: FAILED"
        failures=$((failures + 1))
    fi

    if wait_for_http "http://localhost:${NGINX_EXPORTER_PORT}/metrics" 20 2; then
        log_success "Test nginx exporter metrics endpoint: OK"
    else
        log_error "Test nginx exporter metrics endpoint: FAILED"
        failures=$((failures + 1))
    fi

    if [[ "$failures" -gt 0 ]]; then
        log_error "Target server setup test gagal (${failures} pemeriksaan gagal)"
        exit 1
    fi
}

wait_for_http() {
    local url="$1"
    local attempts="${2:-20}"
    local delay_seconds="${3:-2}"
    local i

    for ((i = 1; i <= attempts; i++)); do
        if curl -fsS "$url" >/dev/null 2>&1; then
            return 0
        fi
        sleep "$delay_seconds"
    done

    return 1
}

wait_for_scrape_target() {
    local target_ip="$1"
    local attempts="${2:-20}"
    local delay_seconds="${3:-2}"
    local i

    for ((i = 1; i <= attempts; i++)); do
        if curl -fsS http://localhost:9990/api/v1/targets 2>/dev/null | grep -q "${target_ip}:9100"; then
            return 0
        fi
        sleep "$delay_seconds"
    done

    return 1
}

wait_for_prometheus_query() {
    local query_expr="$1"
    local attempts="${2:-20}"
    local delay_seconds="${3:-2}"
    local i

    for ((i = 1; i <= attempts; i++)); do
        if curl -fsS --get --data-urlencode "query=${query_expr}" "http://localhost:9990/api/v1/query" 2>/dev/null | grep -Eq '"result"[[:space:]]*:[[:space:]]*\[[[:space:]]*\{' ; then
            return 0
        fi
        sleep "$delay_seconds"
    done

    return 1
}

main() {
    if [[ $# -lt 1 ]]; then
        show_help
        exit 1
    fi

    local role="$1"
    local ip="${2:-}"
    local compose_cmd

    if [[ "$role" == "-h" || "$role" == "--help" || "$role" == "help" ]]; then
        show_help
        exit 0
    fi

    if ! compose_cmd="$(detect_compose_cmd)"; then
        log_error "Docker Compose tidak ditemukan. Install Docker Compose terlebih dahulu."
        exit 1
    fi

    case "$role" in
        monitoring)
            ip="${ip:-$DEFAULT_NODE_EXPORTER_IP}"
            setup_monitoring_server "$ip" "$compose_cmd"
            ;;
        target-server|target|production)
            if [[ -z "$ip" ]]; then
                show_help
                exit 1
            fi
            setup_target_server "$ip" "$compose_cmd"
            ;;
        *)
            log_error "Role tidak dikenal: $role"
            show_help
            exit 1
            ;;
    esac
}

main "$@"