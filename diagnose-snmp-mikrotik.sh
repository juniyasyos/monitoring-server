#!/bin/bash
####################################################################################################
# Diagnose SNMP Mikrotik - Test Script
#
# Gunakan script ini untuk mendiagnosis kenapa metrics tertentu tidak muncul
# dari SNMP exporter untuk Mikrotik.
#
# Cara pakai:
#   ssh ke server production, lalu jalankan:
#     chmod +x diagnose-snmp-mikrotik.sh
#     ./diagnose-snmp-mikrotik.sh
#
# Output akan disimpan ke: /tmp/snmp-diagnose-{timestamp}.log
####################################################################################################

set +e

OUTPUT_FILE="/tmp/snmp-diagnose-$(date +%Y%m%d-%H%M%S).log"
SNMP_CONTAINER="snmp-exporter"
TARGET=${1:-192.168.1.1}   # IP Mikrotik, bisa diganti via argumen
COMMUNITY=${2:-public_v2}

exec 5>&1  # Simpan stdout asli
exec > >(tee -a "$OUTPUT_FILE") 2>&1

echo "============================================================"
echo " SNMP DIAGNOSE SCRIPT"
echo "============================================================"
echo " Tanggal : $(date)"
echo " Target   : $TARGET"
echo " Community: $COMMUNITY"
echo "============================================================"
echo ""

# ==========================================================
# 1. CEK APAKAH SNMP EXPORTER RUNNING
# ==========================================================
echo "============================================================"
echo " [1] CEK STATUS SNMP EXPORTER"
echo "============================================================"
docker ps --filter name="$SNMP_CONTAINER" --format '{{.Names}} {{.Status}}'
echo ""

# ==========================================================
# 2. CEK VERSION SNMP EXPORTER & GENERATOR
# ==========================================================
echo "============================================================"
echo " [2] CEK VERSION SNMP EXPORTER"
echo "============================================================"
docker exec "$SNMP_CONTAINER" /bin/snmp_exporter --version 2>&1 || echo "(snmp_exporter --version tidak tersedia)"
echo ""

# ==========================================================
# 3. LIHAT MODULE MIKROTIK DI snmp.yml
# ==========================================================
echo "============================================================"
echo " [3] ISI MODUL MIKROTIK DI snmp.yml"
echo "============================================================"
echo "--- 3a. Cek apakah module mikrotik ada ---"
docker exec "$SNMP_CONTAINER" sh -c "grep -c '^mikrotik:' /etc/snmp_exporter/snmp.yml" 2>/dev/null && echo "✓ Module mikrotik ditemukan" || echo "✗ Module mikrotik TIDAK ditemukan!"

echo ""
echo "--- 3b. Auth yang tersedia ---"
docker exec "$SNMP_CONTAINER" sh -c "grep -A3 '^auths:' /etc/snmp_exporter/snmp.yml" 2>/dev/null

echo ""
echo "--- 3c. OID walk di module mikrotik ---"
docker exec "$SNMP_CONTAINER" sh -c "grep -n -E '^(  [a-z]|    walk:|    oid:|    lookups:|      oid:|      labels:|      old_index:|      indexes:)' /etc/snmp_exporter/snmp.yml 2>/dev/null | head -120"
echo ""

# ==========================================================
# 4. TEST PROBE VIA SNMP EXPORTER (end-to-end)
# ==========================================================
echo "============================================================"
echo " [4] TEST PROBE VIA SNMP EXPORTER"
echo "============================================================"
echo "Melakukan probe ke $TARGET dengan module=mikrotik..."
echo "(Ini akan memakan waktu ~10-15 detik)"
echo ""

# Simpan hasil probe
docker exec "$SNMP_CONTAINER" wget -qO- "http://localhost:9116/snmp?target=$TARGET&module=mikrotik&auth=$COMMUNITY" > /tmp/snmp-raw-metrics.txt 2>&1

if [ $? -eq 0 ] && [ -s /tmp/snmp-raw-metrics.txt ]; then
    echo "✓ Probe berhasil, $(wc -l < /tmp/snmp-raw-metrics.txt) line metrics diterima"
else
    echo "✗ Probe gagal atau kosong"
    cat /tmp/snmp-raw-metrics.txt
fi

echo ""
echo "--- 4a. Metric names yang muncul ---"
grep -v '^#' /tmp/snmp-raw-metrics.txt 2>/dev/null | awk -F'{' '{print $1}' | sort -u

echo ""
echo "--- 4b. Metric yang berawalan snmp (walk result) ---"
grep -v '^#' /tmp/snmp-raw-metrics.txt 2>/dev/null | awk -F'{' '{print $1}' | grep -v '^$' | sort -u | head -80

echo ""
echo "--- 4c. HELP text (deskripsi OID) ---"
grep '^# HELP' /tmp/snmp-raw-metrics.txt 2>/dev/null | sort -u

echo ""

# ==========================================================
# 5. HITUNG JUMLAH PER KATEGORI METRIC
# ==========================================================
echo "============================================================"
echo " [5] STATISTIK METRIK PER KATEGORI"
echo "============================================================"
RAW_FILE="/tmp/snmp-raw-metrics.txt"

echo "--- 5a. Interfaces ---"
grep -c 'ifName\|ifIndex\|ifDescr\|ifAlias\|ifSpeed\|ifType\|ifMtu\|ifAdminStatus\|ifOperStatus' "$RAW_FILE" 2>/dev/null || echo "0"

echo "--- 5b. Interface Traffic ---"
grep -c 'ifHCInOctets\|ifHCOutOctets\|ifInOctets\|ifOutOctets\|ifInUcastPkts\|ifOutUcastPkts\|ifInErrors\|ifOutErrors' "$RAW_FILE" 2>/dev/null || echo "0"

echo "--- 5c. CPU ---"
grep -c 'cpu\|CPU\|processor\|laLoad\|cpuTemperature\|cpuLoad\|1.3.6.1.4.1.14988.1.1.1.2' "$RAW_FILE" 2>/dev/null || echo "0"

echo "--- 5d. Memory ---"
grep -c 'memory\|Memory\|totalMemory\|freeMemory\|usedMemory' "$RAW_FILE" 2>/dev/null || echo "0"

echo "--- 5e. Storage/Disk ---"
grep -c 'storage\|Storage\|disk\|Disk\|partition\|Partition\|totalSpace\|usedSpace\|freeSpace\|1.3.6.1.4.1.14988.1.1.1.1' "$RAW_FILE" 2>/dev/null || echo "0"

echo "--- 5f. System/Uptime ---"
grep -c 'sysUp\|sysName\|sysDescr\|sysLocation\|uptime\|systemUptime' "$RAW_FILE" 2>/dev/null || echo "0"

echo "--- 5g. Temperature ---"
grep -c 'temperature\|Temperature\|temp' "$RAW_FILE" 2>/dev/null || echo "0"

echo ""

# ==========================================================
# 6. TEST SNMP DIRECT KE MIKROTIK (OID level)
# ==========================================================
echo "============================================================"
echo " [6] TEST SNMP DIRECT KE MIKROTIK (via container)"
echo "============================================================"

# Cek apakah snmpwalk/snmpget tersedia di container
SNMPGET_AVAILABLE=0
docker exec "$SNMP_CONTAINER" which snmpget >/dev/null 2>&1 && SNMPGET_AVAILABLE=1

if [ "$SNMPGET_AVAILABLE" -eq 1 ]; then
    echo "✓ snmpget/snmpwalk tersedia di container"
    echo ""

    # 6a. System info
    echo "--- 6a. System Info OID (1.3.6.1.2.1.1) ---"
    docker exec "$SNMP_CONTAINER" snmpget -v2c -c "$COMMUNITY" "$TARGET" 1.3.6.1.2.1.1.1.0 2>&1 | head -3
    docker exec "$SNMP_CONTAINER" snmpget -v2c -c "$COMMUNITY" "$TARGET" 1.3.6.1.2.1.1.5.0 2>&1 | head -3
    docker exec "$SNMP_CONTAINER" snmpget -v2c -c "$COMMUNITY" "$TARGET" 1.3.6.1.2.1.1.3.0 2>&1 | head -3
    echo ""

    # 6b. CPU (Mikrotik specific OID)
    echo "--- 6b. CPU - Mikrotik OID (1.3.6.1.4.1.14988.1.1.1.2) ---"
    docker exec "$SNMP_CONTAINER" snmpwalk -v2c -c "$COMMUNITY" -On "$TARGET" 1.3.6.1.4.1.14988.1.1.1.2 2>&1 | head -15
    echo ""

    # 6c. Memory/Storage (Mikrotik specific OID)
    echo "--- 6c. Memory/Storage - Mikrotik OID (1.3.6.1.4.1.14988.1.1.1.1) ---"
    docker exec "$SNMP_CONTAINER" snmpwalk -v2c -c "$COMMUNITY" -On "$TARGET" 1.3.6.1.4.1.14988.1.1.1.1 2>&1 | head -15
    echo ""

    # 6d. Interfaces
    echo "--- 6d. Interfaces (1.3.6.1.2.1.2.2.1.2) ---"
    docker exec "$SNMP_CONTAINER" snmpwalk -v2c -c "$COMMUNITY" -On "$TARGET" 1.3.6.1.2.1.2.2.1.2 2>&1 | head -20
    echo ""

    # 6e. Interface Traffic (ifHCInOctets)
    echo "--- 6e. Interface Traffic - ifHCInOctets (1.3.6.1.2.1.31.1.1.1.6) ---"
    docker exec "$SNMP_CONTAINER" snmpwalk -v2c -c "$COMMUNITY" -On "$TARGET" 1.3.6.1.2.1.31.1.1.1.6 2>&1 | head -10
    echo ""

    # 6f. Interface Traffic (ifHCOutOctets)
    echo "--- 6f. Interface Traffic - ifHCOutOctets (1.3.6.1.2.1.31.1.1.1.10) ---"
    docker exec "$SNMP_CONTAINER" snmpwalk -v2c -c "$COMMUNITY" -On "$TARGET" 1.3.6.1.2.1.31.1.1.1.10 2>&1 | head -10
    echo ""

    # 6g. CPU Temperature
    echo "--- 6g. CPU Temperature - Mikrotik OID (1.3.6.1.4.1.14988.1.1.1.3) ---"
    docker exec "$SNMP_CONTAINER" snmpwalk -v2c -c "$COMMUNITY" -On "$TARGET" 1.3.6.1.4.1.14988.1.1.1.3 2>&1 | head -10
    echo ""

    # 6h. Health/Voltage
    echo "--- 6h. Health/Voltage (1.3.6.1.4.1.14988.1.1.1.4) ---"
    docker exec "$SNMP_CONTAINER" snmpwalk -v2c -c "$COMMUNITY" -On "$TARGET" 1.3.6.1.4.1.14988.1.1.1.4 2>&1 | head -10
    echo ""

    # 6i. Uptime
    echo "--- 6i. System Uptime (1.3.6.1.2.1.25.1.1) ---"
    docker exec "$SNMP_CONTAINER" snmpget -v2c -c "$COMMUNITY" "$TARGET" 1.3.6.1.2.1.25.1.1.0 2>&1 | head -3
    echo ""

else
    echo "⚠ snmpget/snmpwalk tidak tersedia di dalam container"
    echo "  Alternatif: install paket snmp di container atau gunakan host"
    echo ""
    echo "  Untuk install snmp tools di container (sementara):"
    echo "    docker exec $SNMP_CONTAINER apk add --no-cache net-snmp-tools"
    echo ""
fi

# ==========================================================
# 7. CEK STATUS DARI PROMETHEUS
# ==========================================================
echo "============================================================"
echo " [7] STATUS TARGET DI PROMETHEUS"
echo "============================================================"

PROMETHEUS_PORT=$(docker ps --filter name=prometheus --format '{{.Ports}}' | grep -oP '([0-9]+)' | head -1)
PROM_PORT=${PROMETHEUS_PORT:-9090}

echo "Menggunakan port: $PROM_PORT"
echo ""

# Cek target
curl -s "http://localhost:$PROM_PORT/api/v1/targets" 2>/dev/null | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    targets = [t for t in data['data']['activeTargets'] if t['labels'].get('job') == 'snmp-mikrotik']
    if targets:
        for t in targets:
            print(f\"Instance: {t['labels'].get('instance', '?')}\")
            print(f\"Health:   {t['health']}\")
            print(f\"Scrape URL: {t.get('scrapeUrl', '?')}\")
            print(f\"Last Error: {t.get('lastError', 'none')}\")
            print(f\"Last Scrape: {t.get('lastScrape', '?')}\")
            print(f\"Scrape Duration: {t.get('lastScrapeDuration', '?')}\")
            print()
    else:
        print('Target snmp-mikrotik tidak ditemukan di Prometheus!')
except Exception as e:
    print(f'Gagal parse response: {e}')
" 2>&1 || echo "✗ Prometheus API tidak reachable di port $PROM_PORT"

echo ""

# ==========================================================
# 8. REKOMENDASI
# ==========================================================
echo "============================================================"
echo " [8] REKOMENDASI AWAL"
echo "============================================================"
echo ""
echo "Jika CPU/Memory/Disk/System metrics tidak muncul, kemungkinan:"
echo ""
echo "  1️⃣ SNMP exporter bawaan tidak memiliki OID khusus Mikrotik"
echo "     → Perlu generate snmp.yml kustom dengan generator"
echo ""
echo "  2️⃣ Community string tidak memiliki akses ke OID tertentu"
echo "     → Cek SNMP settings di Mikrotik (/snmp community print)"
echo ""
echo "  3️⃣ Firewall Mikrotik memblokir OID tertentu"
echo "     → Cek /ip firewall filter"
echo ""
echo "  4️⃣ Versi SNMP (v1/v2c/v3) tidak kompatibel"
echo "     → Cek /snmp print di Mikrotik"
echo ""
echo "============================================================"
echo ""
echo "Hasil diagnose lengkap tersimpan di: $OUTPUT_FILE"
echo ""
exec >&5  # Kembalikan stdout ke terminal
echo "✅ Selesai! Hasil tersimpan di: $OUTPUT_FILE"
