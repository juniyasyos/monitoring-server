#!/bin/bash

set +e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== SNMP NETWORK DEBUG ===${NC}\n"

# 1. Check networks
echo -e "${BLUE}1️⃣ CHECK DOCKER NETWORKS${NC}"
echo "Networks dengan 'monitoring':"
docker network ls | grep monitoring || echo "❌ Network monitoring-network tidak ditemukan!"
echo ""

# 2. Check network details
echo -e "${BLUE}2️⃣ CHECK NETWORK DETAILS${NC}"
echo "Containers dalam monitoring-network:"
docker network inspect monitoring-network 2>/dev/null | jq '.Containers | keys[]' || echo "❌ Gagal inspect network"
echo ""

# 3. Check container networks
echo -e "${BLUE}3️⃣ CHECK CONTAINER ATTACHMENT${NC}"
echo "Prometheus networks:"
docker inspect prometheus 2>/dev/null | jq '.NetworkSettings.Networks | keys[]' || echo "❌ Prometheus tidak found"
echo ""
echo "SNMP Exporter networks:"
docker inspect snmp-exporter 2>/dev/null | jq '.NetworkSettings.Networks | keys[]' || echo "❌ SNMP Exporter tidak found"
echo ""

# 4. Check DNS resolution
echo -e "${BLUE}4️⃣ CHECK DNS RESOLUTION (from Prometheus)${NC}"
echo "Prometheus resolve 'snmp-exporter':"
docker exec prometheus getent hosts snmp-exporter 2>/dev/null || echo "❌ DNS resolve failed"
echo ""

# 5. Check HTTP connectivity (Prometheus -> SNMP)
echo -e "${BLUE}5️⃣ CHECK HTTP CONNECTIVITY (Prometheus -> SNMP)${NC}"
echo "Prometheus curl http://snmp-exporter:9116/metrics:"
docker exec prometheus wget -qO- http://snmp-exporter:9116/metrics 2>&1 | head -5 || echo "❌ HTTP request failed"
echo ""

# 6. Check from host
echo -e "${BLUE}6️⃣ CHECK FROM HOST${NC}"
echo "Host curl http://localhost:9116/metrics:"
curl -s http://localhost:9116/metrics | head -5 || echo "❌ Host cannot reach SNMP"
echo ""

# 7. Check SNMP connectivity to Mikrotik
echo -e "${BLUE}7️⃣ CHECK SNMP CONNECTIVITY (SNMP -> Mikrotik)${NC}"
echo "SNMP Exporter ping 192.168.1.1:"
docker exec snmp-exporter ping -c 1 -w 5 192.168.1.1 2>&1 || echo "❌ Cannot reach 192.168.1.1"
echo ""
echo "SNMP Exporter ping 192.168.1.100:"
docker exec snmp-exporter ping -c 1 -w 5 192.168.1.100 2>&1 || echo "❌ Cannot reach 192.168.1.100"
echo ""

# 8. Check SNMP port accessibility
echo -e "${BLUE}8️⃣ CHECK SNMP PORT (UDP 161)${NC}"
echo "From SNMP container test port 161 to 192.168.1.1:"
docker exec snmp-exporter bash -c 'timeout 3 bash -c "</dev/tcp/192.168.1.1/161"' 2>&1 && echo "✓ Port open" || echo "❌ Port closed/unreachable (note: TCP test, SNMP is UDP)"
echo ""

# 9. Check Prometheus config
echo -e "${BLUE}9️⃣ CHECK PROMETHEUS CONFIG${NC}"
echo "Validate prometheus.yml:"
docker exec prometheus promtool check config /etc/prometheus/prometheus.yml 2>&1 | tail -5 || echo "❌ Config validation failed"
echo ""

# 10. Check Prometheus targets status
echo -e "${BLUE}🔟 CHECK PROMETHEUS TARGETS STATUS${NC}"
echo "SNMP Mikrotik targets:"
curl -s http://localhost:9990/api/v1/targets 2>/dev/null | jq '.data.activeTargets[] | select(.labels.job == "snmp-mikrotik") | {instance: .labels.instance, health, lastError}' || echo "❌ Cannot query targets"
echo ""

# 11. Summary
echo -e "${BLUE}=== SUMMARY ===${NC}"
echo "✓ Prometheus container: $(docker ps --filter name=prometheus --format '{{.State.Status}}' 2>/dev/null || echo "❌")"
echo "✓ SNMP container: $(docker ps --filter name=snmp-exporter --format '{{.State.Status}}' 2>/dev/null || echo "❌")"
echo "✓ Network 'monitoring-network': $(docker network ls --filter name=monitoring-network --format '{{.Name}}' 2>/dev/null || echo "❌")"
echo ""
echo -e "${YELLOW}📝 NOTES:${NC}"
echo "- Jika DNS resolve berhasil tapi HTTP failed: check firewall/network isolasi"
echo "- Jika ping ke Mikrotik failed: network 192.168.x.x tidak accessible dari container"
echo "- Jika SNMP port failed: Mikrotik mungkin tidak enabled SNMP atau firewall block port 161/UDP"
echo "- Default SNMP community: public_v2 (check di Mikrotik config)"
