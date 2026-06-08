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
#   - Internet access (to pull prom/snmp-generator image)
#
# Output:
#   ./snmp/snmp.yml  →  generated config file
####################################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
GENERATOR_YML="$SCRIPT_DIR/generator.yml"
OUTPUT_YML="$SCRIPT_DIR/snmp.yml"

echo "============================================================"
echo " SNMP Generator - MikroTik"
echo "============================================================"
echo " Generator config : $GENERATOR_YML"
echo " Output           : $OUTPUT_YML"
echo "============================================================"
echo ""

# ── Validasi file generator.yml ─────────────────────────────────────────────────────────────────
if [ ! -f "$GENERATOR_YML" ]; then
    echo "❌ ERROR: $GENERATOR_YML tidak ditemukan!"
    exit 1
fi

# ── Generate snmp.yml ───────────────────────────────────────────────────────────────────────────
echo "🚀 Generating snmp.yml..."
echo ""

docker run --rm \
    -v "$PROJECT_DIR/snmp":/opt \
    prom/snmp-generator:latest \
    generate --output-directory /opt \
    -m /opt/generator.yml

# ── Validasi hasil ──────────────────────────────────────────────────────────────────────────────
if [ -f "$OUTPUT_YML" ]; then
    echo ""
    echo "✅ Berhasil! snmp.yml dihasilkan:"
    echo "   Lokasi : $OUTPUT_YML"
    echo "   Ukuran : $(wc -c < "$OUTPUT_YML") bytes"
    echo "   Baris  : $(wc -l < "$OUTPUT_YML") lines"
    echo ""

    # Cek apakah module mikrotik ada di output
    if grep -q "mikrotik:" "$OUTPUT_YML"; then
        echo "✅ Module 'mikrotik' ditemukan di snmp.yml"
    else
        echo "⚠️  Module 'mikrotik' TIDAK ditemukan di snmp.yml!"
        echo "   Cek kembali generator.yml untuk OID entries."
    fi

    echo ""
    echo "👉 Selanjutnya, restart container:"
    echo "   docker compose -f docker-compose-snmp-exporter.yml down"
    echo "   docker compose -f docker-compose-snmp-exporter.yml up -d"
    echo ""
else
    echo "❌ ERROR: snmp.yml gagal dihasilkan!"
    exit 1
fi
