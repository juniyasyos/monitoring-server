#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROM_CONFIG="${PROM_CONFIG:-$SCRIPT_DIR/monitoring/prometheus.yml}"
PROM_API_URL="${PROM_API_URL:-http://localhost:9990}"
DEFAULT_PORT="${DEFAULT_PORT:-9100}"
METRICS_PATH="${METRICS_PATH:-/metrics}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}ℹ️  $*${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $*${NC}"
}

log_warn() {
    echo -e "${YELLOW}⚠️  $*${NC}"
}

log_error() {
    echo -e "${RED}❌ $*${NC}"
}

check_dependency() {
    local name="$1"
    if ! command -v "$name" >/dev/null 2>&1; then
        log_error "Required command not found: $name"
        return 1
    fi
}

discover_targets() {
    awk '
        $0 ~ /job_name:[[:space:]]*["\047]node-exporter-prod["\047]/ { in_job = 1; next }
        in_job && $0 ~ /^[[:space:]]*-[[:space:]]*job_name:/ { in_job = 0 }
        in_job && $0 ~ /targets:/ { in_targets = 1; next }
        in_targets && $0 ~ /^[[:space:]]*-[[:space:]]*["\047]?[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+["\047]?/ {
            if (match($0, /([0-9]+\.){3}[0-9]+:[0-9]+/)) {
                print substr($0, RSTART, RLENGTH)
            }
            next
        }
        in_targets && $0 !~ /^[[:space:]]*-[[:space:]]*/ { in_targets = 0 }
    ' "$PROM_CONFIG" | tr -d "'\"" | sed 's/[[:space:]]//g' | sort -u
}

extract_host() {
    local target="$1"
    echo "${target%:*}"
}

extract_port() {
    local target="$1"
    if [[ "$target" == *:* ]]; then
        echo "${target##*:}"
    else
        echo "$DEFAULT_PORT"
    fi
}

check_prom_config() {
    local target="$1"
    if grep -qF "$target" "$PROM_CONFIG"; then
        log_success "Target terdaftar di prometheus.yml: $target"
    else
        log_warn "Target tidak ditemukan di prometheus.yml: $target"
    fi
}

check_port() {
    local host="$1"
    local port="$2"

    if command -v nc >/dev/null 2>&1; then
        if nc -z -w 3 "$host" "$port" >/dev/null 2>&1; then
            log_success "Port TCP terbuka: $host:$port"
            return 0
        fi
        log_error "Port TCP tidak bisa dijangkau: $host:$port"
        return 1
    fi

    if timeout 3 bash -c "</dev/tcp/$host/$port" >/dev/null 2>&1; then
        log_success "Port TCP terbuka: $host:$port"
        return 0
    fi

    log_error "Port TCP tidak bisa dijangkau: $host:$port"
    return 1
}

check_metrics() {
    local target="$1"
    local url="http://$target$METRICS_PATH"
    local body

    if ! body="$(curl -fsS --max-time 8 "$url" 2>/dev/null)"; then
        log_error "HTTP metrics gagal diakses: $url"
        return 1
    fi

    if grep -q '^node_exporter_build_info' <<<"$body" || grep -q '^process_cpu_seconds_total' <<<"$body"; then
        log_success "Endpoint metrics valid: $url"
        return 0
    fi

    log_error "Respons dari $url tidak terlihat seperti node exporter"
    return 1
}

check_prometheus_status() {
    local target="$1"
    local api_url="$PROM_API_URL/api/v1/targets"

    if ! command -v jq >/dev/null 2>&1; then
        log_warn "jq tidak tersedia, lewati cek status target di Prometheus"
        return 0
    fi

    local payload
    if ! payload="$(curl -fsS --max-time 8 "$api_url" 2>/dev/null)"; then
        log_warn "Tidak bisa mengambil status target dari Prometheus API"
        return 0
    fi

    local matched
    matched="$(jq -r --arg target "$target" '
        .data.activeTargets[]?
        | select(.scrapePool == "node-exporter-prod")
        | select(.scrapeUrl | contains($target))
        | "\(.health)|\(.lastError)"
    ' <<<"$payload" | head -n 1 || true)"

    if [[ -z "$matched" ]]; then
        log_warn "Prometheus belum menampilkan target ini sebagai active target: $target"
        return 1
    fi

    local health="${matched%%|*}"
    local last_error="${matched#*|}"

    if [[ "$health" == "up" ]]; then
        log_success "Prometheus melihat target UP: $target"
        return 0
    fi

    log_error "Prometheus melihat target DOWN: $target"
    if [[ -n "$last_error" && "$last_error" != "null" ]]; then
        echo "    lastError: $last_error"
    fi
    return 1
}

main() {
    if [[ ! -f "$PROM_CONFIG" ]]; then
        log_error "Konfigurasi Prometheus tidak ditemukan: $PROM_CONFIG"
        exit 1
    fi

    local targets=()
    if [[ $# -gt 0 ]]; then
        targets=("$@")
    else
        mapfile -t targets < <(discover_targets)
    fi

    if [[ ${#targets[@]} -eq 0 ]]; then
        log_error "Tidak ada target node exporter ditemukan di prometheus.yml"
        exit 1
    fi

    check_dependency curl
    check_dependency grep
    check_dependency awk

    local failures=0

    log_info "Memeriksa target node exporter dari: $PROM_CONFIG"
    log_info "Prometheus API: $PROM_API_URL"
    echo ""

    for target in "${targets[@]}"; do
        local host port
        host="$(extract_host "$target")"
        port="$(extract_port "$target")"

        echo "============================================================"
        echo "Target: $target"

        check_prom_config "$target" || true
        check_port "$host" "$port" || failures=$((failures + 1))
        check_metrics "$target" || failures=$((failures + 1))
        check_prometheus_status "$target" || failures=$((failures + 1))
        echo ""
    done

    echo "============================================================"
    if [[ "$failures" -eq 0 ]]; then
        log_success "Semua target node exporter lulus pengecekan"
    else
        log_error "Ada $failures pengecekan yang gagal"
    fi

    exit "$failures"
}

main "$@"