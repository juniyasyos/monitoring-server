#!/bin/bash
####################################################################################################
# Diagnose SNMP Mikrotik - Auto Auth + Executive Summary
#
# Cara pakai:
#   chmod +x diagnose-snmp-mikrotik.sh
#
# Full mode:
#   ./diagnose-snmp-mikrotik.sh 192.168.1.1
#
# Summary mode:
#   ./diagnose-snmp-mikrotik.sh 192.168.1.1 --summary
#
# Jika tetap ingin pakai auth tertentu:
#   ./diagnose-snmp-mikrotik.sh 192.168.1.1 public_v2 --summary
#
# Output lengkap:
#   /tmp/snmp-diagnose-{timestamp}.log
####################################################################################################

set +e

OUTPUT_FILE="/tmp/snmp-diagnose-$(date +%Y%m%d-%H%M%S).log"
RAW_FILE="/tmp/snmp-raw-metrics.txt"

SNMP_CONTAINER="snmp-exporter"
TARGET=${1:-192.168.1.1}

ARG2=${2:-auto}
ARG3=${3:-full}

AUTH_MODE="auto"
SELECTED_AUTH=""

IS_SUMMARY=0

if [ "$ARG2" = "--summary" ] || [ "$ARG2" = "summary" ]; then
    IS_SUMMARY=1
elif [ "$ARG3" = "--summary" ] || [ "$ARG3" = "summary" ]; then
    IS_SUMMARY=1
    AUTH_MODE="manual"
    SELECTED_AUTH="$ARG2"
elif [ "$ARG2" != "auto" ]; then
    AUTH_MODE="manual"
    SELECTED_AUTH="$ARG2"
fi

EXPORTER_RUNNING=0
MODULE_FOUND=0
PROBE_OK=0
DIRECT_SNMP_OK=0
PROMETHEUS_OK=0
PROMETHEUS_TARGET_FOUND=0
PROMETHEUS_TARGET_UP=0

COUNT_INTERFACE=0
COUNT_TRAFFIC=0
COUNT_CPU=0
COUNT_MEMORY=0
COUNT_STORAGE=0
COUNT_SYSTEM=0
COUNT_TEMP=0

DIRECT_CPU_OK=0
DIRECT_MEMORY_OK=0
DIRECT_INTERFACE_OK=0
DIRECT_TRAFFIC_OK=0

exec 5>&1
exec > >(tee -a "$OUTPUT_FILE") 2>&1

print_section() {
    if [ "$IS_SUMMARY" -eq 0 ]; then
        echo "============================================================"
        echo " $1"
        echo "============================================================"
    fi
}

print_line() {
    if [ "$IS_SUMMARY" -eq 0 ]; then
        echo "$@"
    fi
}

status_icon() {
    if [ "$1" -gt 0 ]; then
        echo "✅"
    else
        echo "❌"
    fi
}

count_status() {
    if [ "$1" -gt 0 ]; then
        echo "✅"
    else
        echo "❌"
    fi
}

is_valid_metrics() {
    local file="$1"

    if [ ! -s "$file" ]; then
        return 1
    fi

    if grep -qi "unknown auth\|unknown module\|error\|failed\|timeout\|no such" "$file"; then
        return 1
    fi

    if grep -q "^# HELP\|^[a-zA-Z][a-zA-Z0-9_]*{" "$file"; then
        return 0
    fi

    return 1
}

echo "============================================================"
echo " SNMP DIAGNOSE SCRIPT"
echo "============================================================"
echo " Tanggal  : $(date)"
echo " Target   : $TARGET"
echo " Auth     : $([ "$AUTH_MODE" = "auto" ] && echo "AUTO DETECT" || echo "$SELECTED_AUTH")"
echo " Mode     : $([ "$IS_SUMMARY" -eq 1 ] && echo "SUMMARY" || echo "FULL")"
echo "============================================================"
echo ""

# ==========================================================
# 1. CEK SNMP EXPORTER
# ==========================================================
print_section "[1] CEK STATUS SNMP EXPORTER"

EXPORTER_STATUS=$(docker ps --filter name="$SNMP_CONTAINER" --format '{{.Names}} {{.Status}}')

if echo "$EXPORTER_STATUS" | grep -q "$SNMP_CONTAINER"; then
    EXPORTER_RUNNING=1
fi

print_line "$EXPORTER_STATUS"
print_line ""

# ==========================================================
# 2. VERSION
# ==========================================================
print_section "[2] CEK VERSION SNMP EXPORTER"

if [ "$EXPORTER_RUNNING" -eq 1 ]; then
    docker exec "$SNMP_CONTAINER" /bin/snmp_exporter --version 2>&1 || print_line "(snmp_exporter --version tidak tersedia)"
else
    print_line "Container $SNMP_CONTAINER tidak berjalan."
fi

print_line ""

# ==========================================================
# 3. MODULE & AUTHS
# ==========================================================
print_section "[3] CEK MODULE DAN AUTHS DI snmp.yml"

AUTHS=""

if [ "$EXPORTER_RUNNING" -eq 1 ]; then
    MODULE_COUNT=$(docker exec "$SNMP_CONTAINER" sh -c "grep -c '  mikrotik:' /etc/snmp_exporter/snmp.yml" 2>/dev/null)

    if [ "$MODULE_COUNT" -gt 0 ] 2>/dev/null; then
        MODULE_FOUND=1
        print_line "✓ Module mikrotik ditemukan"
    else
        print_line "✗ Module mikrotik TIDAK ditemukan!"
    fi

    AUTHS=$(docker exec "$SNMP_CONTAINER" sh -c "
        awk '
            /^auths:/ {in_auths=1; next}
            /^[a-zA-Z0-9_-]+:/ && in_auths {exit}
            in_auths && /^  [a-zA-Z0-9_-]+:/ {
                gsub(\":\", \"\", \$1);
                print \$1;
            }
        ' /etc/snmp_exporter/snmp.yml
    " 2>/dev/null)

    print_line ""
    print_line "--- Auth yang ditemukan ---"
    if [ -n "$AUTHS" ]; then
        echo "$AUTHS"
    else
        print_line "Tidak ada auth ditemukan."
    fi

    print_line ""
    print_line "--- OID walk di module mikrotik ---"
    docker exec "$SNMP_CONTAINER" sh -c "grep -n -E '^(  [a-z]|    walk:|    oid:|    lookups:|      oid:|      labels:|      old_index:|      indexes:)' /etc/snmp_exporter/snmp.yml 2>/dev/null | head -120"
else
    print_line "Lewati. Container tidak berjalan."
fi

print_line ""

# ==========================================================
# 4. AUTO TEST AUTH / MANUAL AUTH
# ==========================================================
print_section "[4] TEST PROBE VIA SNMP EXPORTER"

if [ "$EXPORTER_RUNNING" -eq 1 ] && [ "$MODULE_FOUND" -eq 1 ]; then

    if [ "$AUTH_MODE" = "manual" ]; then
        print_line "Menguji auth manual: $SELECTED_AUTH"
        docker exec "$SNMP_CONTAINER" wget -qO- "http://localhost:9116/snmp?target=$TARGET&module=mikrotik&auth=$SELECTED_AUTH" > "$RAW_FILE" 2>&1

        if is_valid_metrics "$RAW_FILE"; then
            PROBE_OK=1
            print_line "✓ Probe berhasil dengan auth: $SELECTED_AUTH"
        else
            print_line "✗ Probe gagal dengan auth: $SELECTED_AUTH"
            cat "$RAW_FILE"
        fi

    else
        print_line "Auto-detect auth dari snmp.yml..."
        print_line ""

        if [ -z "$AUTHS" ]; then
            print_line "✗ Tidak ada auth ditemukan di snmp.yml"
        else
            for AUTH in $AUTHS; do
                TMP_FILE="/tmp/snmp-test-$AUTH.txt"

                print_line "Testing auth: $AUTH"
                docker exec "$SNMP_CONTAINER" wget -qO- "http://localhost:9116/snmp?target=$TARGET&module=mikrotik&auth=$AUTH" > "$TMP_FILE" 2>&1

                if is_valid_metrics "$TMP_FILE"; then
                    PROBE_OK=1
                    SELECTED_AUTH="$AUTH"
                    cp "$TMP_FILE" "$RAW_FILE"
                    print_line "✓ Auth berhasil: $AUTH"
                    break
                else
                    print_line "✗ Auth gagal: $AUTH"
                fi
            done
        fi
    fi

    if [ "$PROBE_OK" -eq 1 ]; then
        print_line ""
        print_line "Auth terpilih: $SELECTED_AUTH"
        print_line "Metrics diterima: $(wc -l < "$RAW_FILE") line"

        print_line ""
        print_line "--- Metric names yang muncul ---"
        grep -v '^#' "$RAW_FILE" 2>/dev/null | awk -F'{' '{print $1}' | grep -v '^$' | sort -u | head -120

        print_line ""
        print_line "--- HELP text ---"
        grep '^# HELP' "$RAW_FILE" 2>/dev/null | sort -u | head -120
    fi

else
    print_line "Lewati probe. Container tidak berjalan atau module mikrotik tidak ditemukan."
fi

print_line ""

# ==========================================================
# 5. HITUNG METRIC
# ==========================================================
print_section "[5] STATISTIK METRIK PER KATEGORI"

if [ -f "$RAW_FILE" ]; then
    COUNT_INTERFACE=$(grep -c 'ifName\|ifIndex\|ifDescr\|ifAlias\|ifSpeed\|ifType\|ifMtu\|ifAdminStatus\|ifOperStatus' "$RAW_FILE" 2>/dev/null)
    COUNT_TRAFFIC=$(grep -c 'ifHCInOctets\|ifHCOutOctets\|ifInOctets\|ifOutOctets\|ifInUcastPkts\|ifOutUcastPkts\|ifInErrors\|ifOutErrors' "$RAW_FILE" 2>/dev/null)
    COUNT_CPU=$(grep -ci 'cpu\|processor\|laLoad\|cpuTemperature\|cpuLoad\|1.3.6.1.4.1.14988.1.1.1.2' "$RAW_FILE" 2>/dev/null)
    COUNT_MEMORY=$(grep -ci 'memory\|totalMemory\|freeMemory\|usedMemory' "$RAW_FILE" 2>/dev/null)
    COUNT_STORAGE=$(grep -ci 'storage\|disk\|partition\|totalSpace\|usedSpace\|freeSpace\|1.3.6.1.4.1.14988.1.1.1.1' "$RAW_FILE" 2>/dev/null)
    COUNT_SYSTEM=$(grep -ci 'sysUp\|sysName\|sysDescr\|sysLocation\|uptime\|systemUptime' "$RAW_FILE" 2>/dev/null)
    COUNT_TEMP=$(grep -ci 'temperature\|temp' "$RAW_FILE" 2>/dev/null)
fi

print_line "Interface metrics : $COUNT_INTERFACE"
print_line "Traffic metrics   : $COUNT_TRAFFIC"
print_line "CPU metrics       : $COUNT_CPU"
print_line "Memory metrics    : $COUNT_MEMORY"
print_line "Storage metrics   : $COUNT_STORAGE"
print_line "System metrics    : $COUNT_SYSTEM"
print_line "Temperature       : $COUNT_TEMP"
print_line ""

# ==========================================================
# 6. TEST SNMP DIRECT VIA CONTAINER
# ==========================================================
print_section "[6] TEST SNMP DIRECT KE MIKROTIK"

if [ "$EXPORTER_RUNNING" -eq 1 ] && [ "$PROBE_OK" -eq 1 ] && docker exec "$SNMP_CONTAINER" which snmpget >/dev/null 2>&1; then
    DIRECT_SNMP_OK=1

    print_line "✓ snmpget/snmpwalk tersedia di container"
    print_line "Menggunakan auth terpilih sebagai community: $SELECTED_AUTH"
    print_line ""

    SYSTEM_RESULT=$(docker exec "$SNMP_CONTAINER" snmpget -v2c -c "$SELECTED_AUTH" "$TARGET" 1.3.6.1.2.1.1.1.0 2>&1)
    CPU_RESULT=$(docker exec "$SNMP_CONTAINER" snmpwalk -v2c -c "$SELECTED_AUTH" -On "$TARGET" 1.3.6.1.4.1.14988.1.1.1.2 2>&1)
    MEMORY_RESULT=$(docker exec "$SNMP_CONTAINER" snmpwalk -v2c -c "$SELECTED_AUTH" -On "$TARGET" 1.3.6.1.4.1.14988.1.1.1.1 2>&1)
    INTERFACE_RESULT=$(docker exec "$SNMP_CONTAINER" snmpwalk -v2c -c "$SELECTED_AUTH" -On "$TARGET" 1.3.6.1.2.1.2.2.1.2 2>&1)
    TRAFFIC_RESULT=$(docker exec "$SNMP_CONTAINER" snmpwalk -v2c -c "$SELECTED_AUTH" -On "$TARGET" 1.3.6.1.2.1.31.1.1.1.6 2>&1)

    echo "$CPU_RESULT" | grep -q "1.3.6.1.4.1.14988" && DIRECT_CPU_OK=1
    echo "$MEMORY_RESULT" | grep -q "1.3.6.1.4.1.14988" && DIRECT_MEMORY_OK=1
    echo "$INTERFACE_RESULT" | grep -q "1.3.6.1.2.1.2.2.1.2" && DIRECT_INTERFACE_OK=1
    echo "$TRAFFIC_RESULT" | grep -q "1.3.6.1.2.1.31.1.1.1.6" && DIRECT_TRAFFIC_OK=1

    print_line "--- System Info ---"
    echo "$SYSTEM_RESULT" | head -3

    print_line ""
    print_line "--- CPU OID ---"
    echo "$CPU_RESULT" | head -15

    print_line ""
    print_line "--- Memory/Storage OID ---"
    echo "$MEMORY_RESULT" | head -15

    print_line ""
    print_line "--- Interface OID ---"
    echo "$INTERFACE_RESULT" | head -20

    print_line ""
    print_line "--- Traffic OID ---"
    echo "$TRAFFIC_RESULT" | head -10

else
    print_line "⚠ Direct SNMP dilewati."
    print_line "  Alasan umum:"
    print_line "  - snmpget/snmpwalk tidak tersedia di container"
    print_line "  - probe exporter belum berhasil"
    print_line "  - auth exporter belum tentu sama dengan community asli"
fi

print_line ""

# ==========================================================
# 7. PROMETHEUS
# ==========================================================
print_section "[7] STATUS TARGET DI PROMETHEUS"

PROMETHEUS_PORT=$(docker ps --filter name=prometheus --format '{{.Ports}}' | grep -oP ':(\K[0-9]+)(?=->9090)' | head -1)
PROM_PORT=${PROMETHEUS_PORT:-9090}

PROM_RESULT=$(curl -s "http://localhost:$PROM_PORT/api/v1/targets" 2>/dev/null)

if echo "$PROM_RESULT" | grep -q '"status":"success"'; then
    PROMETHEUS_OK=1
fi

if [ "$PROMETHEUS_OK" -eq 1 ]; then
    PROM_SUMMARY=$(echo "$PROM_RESULT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    targets = [t for t in data['data']['activeTargets'] if t['labels'].get('job') == 'snmp-mikrotik']

    if not targets:
        print('TARGET_FOUND=0')
    else:
        print('TARGET_FOUND=1')
        for t in targets:
            print(f\"Instance: {t['labels'].get('instance', '?')}\")
            print(f\"Health: {t['health']}\")
            print(f\"Scrape URL: {t.get('scrapeUrl', '?')}\")
            print(f\"Last Error: {t.get('lastError', 'none')}\")
            print(f\"Last Scrape: {t.get('lastScrape', '?')}\")
            print(f\"Scrape Duration: {t.get('lastScrapeDuration', '?')}\")
            print()
except Exception as e:
    print(f'ERROR={e}')
")

    echo "$PROM_SUMMARY" | grep -q "TARGET_FOUND=1" && PROMETHEUS_TARGET_FOUND=1
    echo "$PROM_SUMMARY" | grep -q "Health: up" && PROMETHEUS_TARGET_UP=1

    print_line "$PROM_SUMMARY"
else
    print_line "✗ Prometheus API tidak reachable di port $PROM_PORT"
fi

print_line ""

# ==========================================================
# 8. EXECUTIVE SUMMARY
# ==========================================================
echo "============================================================"
echo " EXECUTIVE SUMMARY"
echo "============================================================"

echo "Target                : $TARGET"
echo "Auth mode             : $AUTH_MODE"
echo "Selected auth         : ${SELECTED_AUTH:-N/A}"
echo ""

echo "Core Check:"
echo "Exporter running      : $(status_icon "$EXPORTER_RUNNING")"
echo "Module mikrotik       : $(status_icon "$MODULE_FOUND")"
echo "Exporter probe        : $(status_icon "$PROBE_OK")"
echo "Prometheus reachable  : $(status_icon "$PROMETHEUS_OK")"
echo "Prometheus target     : $(status_icon "$PROMETHEUS_TARGET_FOUND")"
echo "Prometheus target UP  : $(status_icon "$PROMETHEUS_TARGET_UP")"
echo ""

echo "Metric Availability:"
echo "Interface metrics     : $COUNT_INTERFACE $(count_status "$COUNT_INTERFACE")"
echo "Traffic metrics       : $COUNT_TRAFFIC $(count_status "$COUNT_TRAFFIC")"
echo "CPU metrics           : $COUNT_CPU $(count_status "$COUNT_CPU")"
echo "Memory metrics        : $COUNT_MEMORY $(count_status "$COUNT_MEMORY")"
echo "Storage/Disk metrics  : $COUNT_STORAGE $(count_status "$COUNT_STORAGE")"
echo "System/Uptime metrics : $COUNT_SYSTEM $(count_status "$COUNT_SYSTEM")"
echo "Temperature metrics   : $COUNT_TEMP $(count_status "$COUNT_TEMP")"
echo ""

echo "Direct OID Check:"
echo "Direct SNMP available : $(status_icon "$DIRECT_SNMP_OK")"
echo "CPU OID direct        : $(status_icon "$DIRECT_CPU_OK")"
echo "Memory OID direct     : $(status_icon "$DIRECT_MEMORY_OK")"
echo "Interface OID direct  : $(status_icon "$DIRECT_INTERFACE_OK")"
echo "Traffic OID direct    : $(status_icon "$DIRECT_TRAFFIC_OK")"
echo ""

echo "Diagnosis:"

EXIT_CODE=0

if [ "$EXPORTER_RUNNING" -eq 0 ]; then
    echo "❌ SNMP exporter container tidak berjalan."
    echo "   Cek: docker ps -a | grep $SNMP_CONTAINER"
    EXIT_CODE=2

elif [ "$MODULE_FOUND" -eq 0 ]; then
    echo "❌ Module 'mikrotik' tidak ditemukan di snmp.yml."
    echo "   Kemungkinan snmp.yml belum benar atau belum dimount ke container."
    EXIT_CODE=2

elif [ "$PROBE_OK" -eq 0 ]; then
    echo "❌ Tidak ada auth SNMP Exporter yang berhasil melakukan scrape."
    echo "   Kemungkinan:"
    echo "   - auth di snmp.yml salah"
    echo "   - target $TARGET tidak reachable dari container"
    echo "   - module mikrotik tidak cocok"
    echo "   - SNMP MikroTik menolak request"
    EXIT_CODE=2

elif [ "$COUNT_INTERFACE" -eq 0 ] && [ "$COUNT_TRAFFIC" -eq 0 ] && [ "$COUNT_CPU" -eq 0 ] && [ "$COUNT_MEMORY" -eq 0 ]; then
    echo "⚠️ Probe berhasil, tapi metrics penting kosong."
    echo "   Kemungkinan module mikrotik terlalu minimal atau OID belum masuk snmp.yml."
    EXIT_CODE=1

elif [ "$COUNT_INTERFACE" -gt 0 ] && [ "$COUNT_TRAFFIC" -eq 0 ]; then
    echo "⚠️ Interface terdeteksi, tapi traffic metrics kosong."
    echo "   Kemungkinan OID ifHCInOctets/ifHCOutOctets belum masuk module."
    EXIT_CODE=1

elif [ "$COUNT_INTERFACE" -gt 0 ] && [ "$COUNT_CPU" -eq 0 ] && [ "$COUNT_MEMORY" -eq 0 ]; then
    echo "⚠️ Interface metrics muncul, tapi CPU/Memory kosong."
    echo "   Ini sering terjadi kalau module hanya scrape interface, belum OID khusus MikroTik."
    EXIT_CODE=1

elif [ "$PROMETHEUS_OK" -eq 1 ] && [ "$PROMETHEUS_TARGET_FOUND" -eq 0 ]; then
    echo "⚠️ Prometheus reachable, tapi target job 'snmp-mikrotik' tidak ditemukan."
    echo "   Cek scrape_config Prometheus."
    EXIT_CODE=1

elif [ "$PROMETHEUS_TARGET_FOUND" -eq 1 ] && [ "$PROMETHEUS_TARGET_UP" -eq 0 ]; then
    echo "⚠️ Target Prometheus ditemukan, tapi statusnya DOWN."
    echo "   Cek last error di bagian Prometheus target."
    EXIT_CODE=1

else
    echo "✅ Secara umum konfigurasi terlihat sehat."
fi

echo ""

if [ "$EXIT_CODE" -eq 0 ]; then
    echo "Overall Status: ✅ HEALTHY"
elif [ "$EXIT_CODE" -eq 1 ]; then
    echo "Overall Status: ⚠️ PARTIAL"
else
    echo "Overall Status: ❌ BROKEN"
fi

echo ""
echo "Log lengkap tersimpan di: $OUTPUT_FILE"
echo "============================================================"

exec >&5
echo "✅ Selesai! Hasil tersimpan di: $OUTPUT_FILE"

exit "$EXIT_CODE"