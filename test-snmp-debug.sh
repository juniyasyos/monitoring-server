#!/bin/bash

set +e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0

NETWORK="monitoring-network"
PROM_CONTAINER="prometheus"
SNMP_CONTAINER="snmp-exporter"
PROM_API_PORT=9990
SNMP_PORT=9116
SNMP_TARGET_IP="192.168.1.1"
SNMP_MODULE="mikrotik"
SNMP_AUTH="public_v2"

pass(){ echo -e "${GREEN}✔ $1${NC}"; ((PASS++)); }
fail(){ echo -e "${RED}✖ $1${NC}"; ((FAIL++)); }
warn(){ echo -e "${YELLOW}⚠ $1${NC}"; ((WARN++)); }
section(){ echo -e "\n${BLUE}=== $1 ===${NC}"; }

container_running() {
    docker ps --format '{{.Names}}' | grep -q "^$1$"
}

container_networks() {
    docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' "$1" 2>/dev/null
}

section "DEPENDENCY CHECK"
for cmd in curl jq; do
    command -v "$cmd" >/dev/null 2>&1 && pass "$cmd installed" || fail "$cmd missing"
done

if command -v docker >/dev/null 2>&1; then
    pass "docker installed"
    DOCKER_AVAILABLE=1
else
    warn "docker missing; Docker-based tests will be skipped"
    DOCKER_AVAILABLE=0
fi

section "STACK STATUS"
if [ "$DOCKER_AVAILABLE" -eq 1 ]; then
    docker network inspect "$NETWORK" >/dev/null 2>&1 && pass "Docker network '$NETWORK' exists" || fail "Docker network '$NETWORK' missing"
else
    warn "Skipping network check because docker is unavailable"
fi

done
if [ "$DOCKER_AVAILABLE" -eq 1 ]; then
    for c in "$PROM_CONTAINER" "$SNMP_CONTAINER"; do
        if container_running "$c"; then
            pass "$c running"
        else
            fail "$c NOT running"
        fi
    done
else
    warn "Skipping container status checks because docker is unavailable"
fi

section "NETWORK MEMBERSHIP"
if [ "$DOCKER_AVAILABLE" -eq 1 ]; then
    PROM_NETWORKS=$(container_networks "$PROM_CONTAINER")
    SNMP_NETWORKS=$(container_networks "$SNMP_CONTAINER")

    echo "prometheus networks: $PROM_NETWORKS"
    echo "snmp-exporter networks: $SNMP_NETWORKS"

    echo "$PROM_NETWORKS $SNMP_NETWORKS" | grep -q "$NETWORK" && pass "Both containers attached to $NETWORK" || fail "Containers are not on the same network"
else
    warn "Skipping network membership check because docker is unavailable"
fi

section "HOST PORT CHECK"
HOST_PORT_LINE=$(ss -tulnp 2>/dev/null | grep ":$SNMP_PORT" | head -n 1)
if [ -n "$HOST_PORT_LINE" ]; then
    echo "$HOST_PORT_LINE"
    pass "Port $SNMP_PORT is listening on host"
else
    warn "Port $SNMP_PORT not exposed on host or ss unavailable"
fi

section "PROMETHEUS -> SNMP EXPORTER DNS"
if [ "$DOCKER_AVAILABLE" -eq 1 ] && container_running "$PROM_CONTAINER"; then
    DNS_OUTPUT=$(docker exec "$PROM_CONTAINER" sh -lc "getent hosts $SNMP_CONTAINER 2>/dev/null || nslookup $SNMP_CONTAINER 2>/dev/null || true")
    if [ -n "$DNS_OUTPUT" ]; then
        echo "$DNS_OUTPUT"
        pass "Prometheus container can resolve $SNMP_CONTAINER"
    else
        fail "Prometheus container cannot resolve $SNMP_CONTAINER"
    fi
else
    warn "Skipping DNS test because docker/prometheus is unavailable"
fi

section "PROMETHEUS -> SNMP EXPORTER HTTP"
if [ "$DOCKER_AVAILABLE" -eq 1 ] && container_running "$PROM_CONTAINER"; then
    HTTP_OUTPUT=$(docker exec "$PROM_CONTAINER" sh -lc "wget -qO- http://$SNMP_CONTAINER:$SNMP_PORT/metrics 2>&1 | head -n 5")
    HTTP_STATUS=$?
    if [ $HTTP_STATUS -eq 0 ] && [ -n "$HTTP_OUTPUT" ]; then
        echo "$HTTP_OUTPUT"
        pass "Prometheus container can reach http://$SNMP_CONTAINER:$SNMP_PORT/metrics"
    else
        fail "Prometheus container cannot reach SNMP exporter over HTTP"
        echo "$HTTP_OUTPUT"
    fi
else
    warn "Skipping HTTP probe from Prometheus because docker/prometheus is unavailable"
fi

section "HOST -> SNMP EXPORTER HTTP"
HOST_METRICS=$(curl -s "http://localhost:$SNMP_PORT/metrics" | head -n 5)
if [ -n "$HOST_METRICS" ]; then
    echo "$HOST_METRICS"
    pass "Host can reach SNMP exporter on localhost:$SNMP_PORT"
else
    fail "Host cannot reach SNMP exporter on localhost:$SNMP_PORT"
fi

section "PROMETHEUS TARGETS"
TARGETS=$(curl -s "http://localhost:$PROM_API_PORT/api/v1/targets")
if echo "$TARGETS" | jq -e . >/dev/null 2>&1; then
    pass "Prometheus API reachable"
else
    fail "Prometheus API unreachable"
fi

SNMP_TARGET=$(echo "$TARGETS" | jq '.data.activeTargets[]? | select(.labels.job == "snmp-mikrotik")' 2>/dev/null)
if [ -n "$SNMP_TARGET" ]; then
    echo "$SNMP_TARGET" | jq '{health: .health, scrapeUrl: .scrapeUrl, lastError: .lastError, labels: .labels}' 2>/dev/null
    echo "$SNMP_TARGET" | jq -e '.health == "up"' >/dev/null 2>&1 && pass "Prometheus reports snmp-mikrotik UP" || fail "Prometheus reports snmp-mikrotik DOWN"
else
    fail "snmp-mikrotik target not found in Prometheus"
fi

section "PROMETHEUS QUERY"
UP_QUERY=$(curl -s --get --data-urlencode 'query=up{job="snmp-mikrotik"}' "http://localhost:$PROM_API_PORT/api/v1/query")
if echo "$UP_QUERY" | jq -e '.status == "success"' >/dev/null 2>&1; then
    echo "$UP_QUERY" | jq '.data.result'
    if echo "$UP_QUERY" | jq -e '.data.result[]? | select(.value[1] == "1")' >/dev/null 2>&1; then
        pass "Prometheus query up{job=\"snmp-mikrotik\"} returned 1"
    else
        fail "Prometheus query up{job=\"snmp-mikrotik\"} did not return 1"
    fi
else
    fail "Prometheus query failed"
fi

section "SNMP END-TO-END (OPTIONAL DEVICE PROBE)"
if [ "$DOCKER_AVAILABLE" -eq 1 ] && container_running "$SNMP_CONTAINER"; then
    DEVICE_PROBE=$(docker exec "$SNMP_CONTAINER" sh -lc "wget -qO- 'http://localhost:$SNMP_PORT/snmp?target=$SNMP_TARGET_IP&module=$SNMP_MODULE&auth=$SNMP_AUTH' 2>&1 | head -n 5")
    if [ -n "$DEVICE_PROBE" ]; then
        echo "$DEVICE_PROBE"
        pass "SNMP exporter accepted probe for $SNMP_TARGET_IP"
    else
        warn "Device probe returned no output; this can still be OK if the exporter waits for device response"
    fi
else
    warn "Skipping device probe because docker/snmp-exporter is unavailable"
fi

section "SUMMARY"
echo -e "✔ PASS : $PASS"
echo -e "✖ FAIL : $FAIL"
echo -e "⚠ WARN : $WARN"

section "CONCLUSION"
if [ $FAIL -eq 0 ]; then
    echo -e "${GREEN}Prometheus can communicate with snmp-exporter.${NC}"
elif [ "$PASS" -gt 0 ] && [ "$FAIL" -le 2 ]; then
    echo -e "${YELLOW}Communication is partially working, but there is still a target/query issue.${NC}"
else
    echo -e "${RED}Prometheus cannot communicate with snmp-exporter yet.${NC}"
fi

echo