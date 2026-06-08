#!/bin/bash
####################################################################################################
# Generate snmp.yml from generator.yml using the official snmp-generator
#
# Usage:
#   cd /home/juni/projects/docker/monitoring-server
#   ./snmp/generate.sh
#
# Requirements:
#   - Docker installed
#   - Internet access (to pull prom/snmp-generator image & download MIBs)
#
# Output:
#   ./snmp/snmp.yml  →  generated config file
####################################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GENERATOR_YML="$SCRIPT_DIR/generator.yml"
OUTPUT_YML="$SCRIPT_DIR/snmp.yml"
MIBS_DIR="$SCRIPT_DIR/mibs"
MIB_REPO="https://raw.githubusercontent.com/librenms/librenms/master/mibs"

echo "============================================================"
echo " SNMP Generator - MikroTik"
echo "============================================================"
echo " Generator config : $GENERATOR_YML"
echo " Output           : $OUTPUT_YML"
echo " MIBs dir         : $MIBS_DIR"
echo "============================================================"
echo ""

# ── Validasi file generator.yml ─────────────────────────────────────────────────────────────────
if [ ! -f "$GENERATOR_YML" ]; then
    echo "❌ ERROR: $GENERATOR_YML tidak ditemukan!"
    exit 1
fi

# ── Download standard MIBs dari LibreNMS ───────────────────────────────────────────────────────
mkdir -p "$MIBS_DIR"

echo "📥 Download MIB standar (SNMPv2-SMI, IF-MIB, HOST-RESOURCES-MIB, dll)..."

MIB_FILES=(
    "SNMPv2-SMI"
    "SNMPv2-TC"
    "SNMPv2-CONF"
    "SNMPv2-MIB"
    "IF-MIB"
    "IANAifType-MIB"
    "HOST-RESOURCES-MIB"
    "HOST-RESOURCES-TYPES"
    "INET-ADDRESS-MIB"
    "SNMP-FRAMEWORK-MIB"
    "SNMP-MPD-MIB"
    "SNMP-TARGET-MIB"
    "SNMP-NOTIFICATION-MIB"
    "SNMP-USER-BASED-SM-MIB"
    "SNMP-VIEW-BASED-ACM-MIB"
    "SNMP-COMMUNITY-MIB"
    "SNMP-PROXY-MIB"
)

for mib in "${MIB_FILES[@]}"; do
    filename="$mib.txt"
    if [ ! -f "$MIBS_DIR/$filename" ]; then
        echo "   Downloading $filename..."
        curl -sL "$MIB_REPO/$mib" -o "$MIBS_DIR/$filename"
    fi
done

# ── Copy MIB NET-SNMP tambahan dari image generator ────────────────────────────────────────────
echo "   Copy MIB NET-SNMP tambahan dari image generator..."
docker run --rm \
    --entrypoint sh \
    -v "$MIBS_DIR:/out" \
    prom/snmp-generator:latest \
    -c "cp -rn /usr/share/snmp/mibs/* /out/ 2>/dev/null; echo done"

echo "✅ MIBs siap"
echo ""

# ── Generate snmp.yml ─────────────────────────────────────────────────────────────────────────
echo "🚀 Generating snmp.yml..."
echo ""

docker run --rm \
    -v "$SCRIPT_DIR":/opt \
    prom/snmp-generator:latest \
    generate \
    --output-path /opt/snmp.yml \
    -g /opt/generator.yml \
    -m /opt/mibs \
    --no-fail-on-parse-errors

# ── Validasi hasil ────────────────────────────────────────────────────────────────────────────
if [ -f "$OUTPUT_YML" ]; then
    echo ""
    echo "✅ Berhasil! snmp.yml dihasilkan:"
    echo "   Lokasi : $OUTPUT_YML"
    echo "   Ukuran : $(wc -c < "$OUTPUT_YML") bytes"
    echo "   Baris  : $(wc -l < "$OUTPUT_YML") lines"
    echo ""

    if grep -q "mikrotik:" "$OUTPUT_YML"; then
        echo "✅ Module 'mikrotik' ditemukan di snmp.yml"
    else
        echo "⚠️  Module 'mikrotik' TIDAK ditemukan di snmp.yml!"
        echo "   Cek kembali generator.yml untuk OID entries."
    fi

    echo ""
    echo "👉 Selanjutnya, restart container:"
    echo "   docker compose -f docker-compose-snmp-exporter.yml down && docker compose -f docker-compose-snmp-exporter.yml up -d"
    echo ""
else
    echo "❌ ERROR: snmp.yml gagal dihasilkan!"
    exit 1
fi
