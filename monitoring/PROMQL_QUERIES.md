####################################################################################################
# PromQL Query Examples untuk Grafana Panels
#
# Common queries untuk membuat dashboard panels
# Gunakan queries ini di Grafana → Add Panel → Prometheus
####################################################################################################

## System Metrics

### CPU Metrics
# Total CPU usage percentage (all cores)
100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Per-core CPU usage
(1 - avg by (instance, cpu) (rate(node_cpu_seconds_total{mode="idle"}[5m]))) * 100

# CPU by mode (user, system, iowait, etc)
sum by (mode) (rate(node_cpu_seconds_total[5m])) * 100

# Context switches per second
rate(node_context_switches_total[5m])

### Memory Metrics
# Memory usage percentage
(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100

# Memory used vs available
{__name__=~"node_memory_(MemTotal|MemAvailable|MemFree|Cached|Buffers|Slab)_bytes"}

# Swap usage percentage
(1 - (node_memory_SwapFree_bytes / node_memory_SwapTotal_bytes)) * 100 > 0

# Memory pressure (MemAvailable / MemTotal)
node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes

### Disk Metrics
# Disk usage percentage (root filesystem)
(1 - (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"})) * 100

# Disk usage per mountpoint
(1 - (node_filesystem_avail_bytes / node_filesystem_size_bytes)) * 100

# Disk I/O read rate (bytes/sec)
rate(node_disk_read_bytes_total[5m])

# Disk I/O write rate (bytes/sec)
rate(node_disk_written_bytes_total[5m])

# Disk I/O operations per second
sum by (device) (rate(node_disk_reads_completed_total[5m])) + sum by (device) (rate(node_disk_writes_completed_total[5m]))

# Disk I/O time percentage
rate(node_disk_io_time_seconds_total[5m]) * 100

### Load Average Metrics
# 1-minute load average
node_load1

# 5-minute load average
node_load5

# 15-minute load average
node_load15

# Load average relative to CPU count
node_load5 / count(node_cpu_seconds_total{mode="system"})

### Uptime Metrics
# System uptime in days
node_boot_time_seconds | (node_time_seconds - node_boot_time_seconds) / 86400

# System uptime in hours
(node_time_seconds - node_boot_time_seconds) / 3600

---

## Network Metrics

### Network Traffic
# Bytes received per second (all interfaces except docker/lo)
sum by (instance) (rate(node_network_receive_bytes_total{device!~"lo|docker.*|veth.*|br.*"}[5m]))

# Bytes transmitted per second
sum by (instance) (rate(node_network_transmit_bytes_total{device!~"lo|docker.*|veth.*|br.*"}[5m]))

# Packets received per second
sum by (instance) (rate(node_network_receive_packets_total{device!~"lo|docker.*"}[5m]))

# Packets transmitted per second
sum by (instance) (rate(node_network_transmit_packets_total{device!~"lo|docker.*"}[5m]))

# Network errors in
sum by (instance) (rate(node_network_receive_errs_total[5m]))

# Network errors out
sum by (instance) (rate(node_network_transmit_errs_total[5m]))

# Network dropped packets
sum by (instance, direction) (rate(node_network_receive_drop_total[5m])) + sum by (instance) (rate(node_network_transmit_drop_total[5m]))

---

## File Descriptor Metrics

# Open file descriptors
node_filefd_allocated

# Maximum file descriptors
node_filefd_maximum

# File descriptor usage percentage
(node_filefd_allocated / node_filefd_maximum) * 100

---

## Processes & Threads

# Total processes running
node_processes_running

# Total processes blocked
node_processes_blocked

# Number of file descriptors open
node_filefd_allocated

---

## System Misc

# TCP connections
node_netstat_Tcp_CurrEstab

# Network sockets
node_sockstat_sockets_used

# VM Page activity
rate(node_vmstat_pgpgin[5m]) + rate(node_vmstat_pgpgout[5m])

# Entropy available
node_entropy_available_bits

---

## Docker/Container Metrics (requires cAdvisor)

### Container CPU
# CPU usage percentage per container
(sum by (name) (rate(container_cpu_usage_seconds_total[5m])) * 100)

### Container Memory
# Memory usage bytes per container
container_memory_usage_bytes

# Memory usage percentage (vs limit)
(container_memory_usage_bytes / container_spec_memory_limit_bytes) * 100

### Container Network
# Network bytes in
sum by (name) (rate(container_network_receive_bytes_total[5m]))

# Network bytes out
sum by (name) (rate(container_network_transmit_bytes_total[5m]))

---

## Application-Specific Metrics

### Laravel / PHP-FPM (if using php-fpm-exporter)
# PHP-FPM active processes
phpfpm_processes_active

# PHP-FPM idle processes
phpfpm_processes_idle

# PHP-FPM requests per second
rate(phpfpm_requests_total[5m])

---

## Multi-Instance Queries

### Top N instances by metric
# Top 5 instances by CPU usage
topk(5, (100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)))

# Top 5 instances by memory usage
topk(5, ((1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100))

# Top 5 instances by disk usage
topk(5, ((1 - (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"})) * 100))

---

## Time-Series Calculations

### Rates of Change
# CPU usage change (5m average)
rate(node_cpu_seconds_total{mode!="idle"}[5m])

# Memory growth per minute
increase(node_memory_MemTotal_bytes[1m])

### Predictions (basic)
# Predict when disk will be full (linear extrapolation)
predict_linear(node_filesystem_avail_bytes{mountpoint="/"}[1h], 24*3600)

---

## Alerting Queries

### Critical Conditions
# System CPU >80% for 5 minutes
(100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)) > 80

# Memory usage >85%
((1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100) > 85

# Disk usage >90%
((1 - (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"})) * 100) > 90

# Load average > 4 (on 4-core system)
node_load15 > 4

# High network errors
(sum by (instance) (rate(node_network_receive_errs_total[5m])) + sum by (instance) (rate(node_network_transmit_errs_total[5m]))) > 10

---

## Grafana Panel Tips

### Single Stat Panel
# Format as percentage
Calculation: Last value
Unit: Percent (0-100)

### Graph Panel
# Show multiple lines
Legend: Show
Y-axis: Auto
Stack: Off (default)

### Gauge Panel
# Thresholds: 0,70,90
# Colors: Green, Yellow, Red
# Unit: Percent (0-100)

### Table Panel
# Instant query (no time range)
Example: sort_desc(topk(10, node_memory_MemTotal_bytes))

---

## Pro Tips

1. **Label matching**: Gunakan `{label="value"}` untuk filter metrics
2. **Operator**: 
   - `+` add, `-` subtract, `*` multiply, `/` divide
   - `==`, `!=`, `>`, `<`, `>=`, `<=` comparisons
   - `and`, `or`, `unless` logical operators
3. **Functions**: `rate()`, `increase()`, `avg()`, `sum()`, `max()`, `min()`, `topk()`, etc.
4. **Time ranges**: `[5m]`, `[1h]`, `[1d]` untuk duration
5. **Aggregation**: `by (instance)`, `without (cpu)` untuk grouping

---

## Reference Links

- [PromQL Documentation](https://prometheus.io/docs/prometheus/latest/querying/basics/)
- [PromQL Functions](https://prometheus.io/docs/prometheus/latest/querying/functions/)
- [Node Exporter Metrics](https://github.com/prometheus/node_exporter/blob/master/README.md)
