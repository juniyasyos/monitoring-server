# Monitoring Stack: Prometheus & Grafana

Dokumentasi lengkap untuk setup monitoring infrastructure menggunakan Prometheus + Grafana.

## 📋 Struktur Setup

```
Production Server (siimut-docker)          Monitoring Server
┌─────────────────────────────┐            ┌──────────────────────────┐
│ docker-compose-multi-apps   │            │ docker-compose-monitoring│
│ - SIIMUT App                │            │ - Prometheus (9990)      │
│ - IKP App                   │──scrape─→   │ - Grafana (3000)         │
│ - IAM App                   │  targets   │ - AlertManager (opt)     │
│                             │            │                          │
│ docker-compose-node-exporter│            │ Stores metrics (30 days) │
│ - Node Exporter (9100)      │            │ Visualizes dashboards    │
└─────────────────────────────┘            └──────────────────────────┘
```

## 🚀 Quick Start

### 0. Otomatisasi Setup dengan Bash

Jika Anda ingin setup lebih cepat, pakai skrip berikut dari root repo:

```bash
# Di monitoring server: update target IP lalu start Prometheus + Grafana
bash setup-monitoring.sh monitoring <TARGET_SERVER_IP>

# Di target/production server: start Node Exporter dan buka akses ke monitoring server
bash setup-monitoring.sh target-server <MONITORING_SERVER_IP>
```

Automasi tambahan:

- Skrip provisioning Grafana otomatis akan mencoba mengunduh dashboard populer (Node Exporter Full) dan menyimpannya di `monitoring/grafana/provisioning/dashboards/`.
- Password Grafana tetap `admin/admin` karena ini hanya untuk server lokal.

Contoh pemakaian:

```bash
bash setup-monitoring.sh monitoring 192.168.1.4
```

### 1. Production Server - Deploy Node Exporter

```bash
# Di server production (tempat SIIMUT, IKP, IAM berjalan)
docker-compose -f docker-compose-node-exporter.yml up -d

# Verify metrics
curl http://localhost:9100/metrics | head -20
```

### 2. Monitoring Server - Deploy Prometheus + Grafana

```bash
# Di server monitoring (terpisah atau lokal)
# PENTING: Edit monitoring/prometheus.yml terlebih dahulu!

# Ganti <PROD_SERVER_IP> dengan IP address production server
nano monitoring/prometheus.yml

# Start services
docker-compose -f docker-compose-monitoring.yml up -d

# Verify
curl http://localhost:9990/api/v1/targets
curl http://localhost:3000/api/health
```

### 3. Access Web UI

```
Prometheus:  http://localhost:9990
Grafana:     http://localhost:3000
```

---

## 📝 Konfigurasi

### prometheus.yml - Scrape Targets

Edit `monitoring/prometheus.yml` dan sesuaikan dengan environment Anda:

```yaml
scrape_configs:
  - job_name: "node-exporter-prod"
    static_configs:
      - targets: ["192.168.1.100:9100"] # ← Ganti dengan IP production server
        labels:
          server: "production"
```

**Available scrape job templates:**

- `node-exporter-prod` - System metrics (CPU, Memory, Disk, Network)
- `cadvisor` - Docker container metrics (optional)
- `laravel-siimut`, `laravel-ikp`, `laravel-iam` - App metrics (optional)
- `mysql-exporter` - Database metrics (optional)
- `nginx-exporter` - Nginx metrics (optional)
- `redis-exporter` - Redis cache metrics (optional)

---

## 🔧 Production Server - Optional Exporters

Untuk monitoring yang lebih comprehensive, deploy additional exporters di production server:

### Docker Compose Extension (Tambahan)

```yaml
# Tambahkan ke docker-compose-node-exporter.yml

services:
  # cAdvisor - Docker Container Metrics
  cadvisor:
    image: gcr.io/cadvisor/cadvisor:latest
    container_name: cadvisor
    ports:
      - "8080:8080"
    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:ro
      - /sys:/sys:ro
      - /var/lib/docker/:/var/lib/docker:ro
    command:
      - --housekeeping_interval=30s
      - --docker_only

  # MySQL Exporter (jika pakai MySQL)
  mysql-exporter:
    image: prom/mysqld-exporter
    container_name: mysql-exporter
    ports:
      - "9104:9104"
    environment:
      DATA_SOURCE_NAME: "root:password@tcp(database-service:3306)/"
    command:
      - --collect.auto_increment.columns
      - --collect.perf_schema.tableio_waits
      - --collect.info_schema.processlist

  # Nginx Prometheus Exporter
  nginx-exporter:
    image: nginx/nginx-prometheus-exporter
    container_name: nginx-exporter
    ports:
      - "9113:9113"
    command:
      - -nginx.scrape-uri=http://web:8000/nginx_status
```

---

## 📊 Import Pre-built Dashboards

### Grafana Dashboard Library

1. Login ke Grafana: `http://localhost:3000`
   - Username: `admin`
   - Password: `admin` (ubah di login pertama!)

2. Go to: **+ (Create) → Import**

3. Import pre-built dashboards:

| Dashboard                   | ID    | Deskripsi                                   |
| --------------------------- | ----- | ------------------------------------------- |
| **Node Exporter Full**      | 1860  | System metrics (CPU, Memory, Disk, Network) |
| **Docker and Host Metrics** | 893   | Docker container dan host metrics           |
| **Prometheus 2.0 Stats**    | 3662  | Prometheus performance metrics              |
| **MySQL Overview**          | 7362  | MySQL database metrics                      |
| **Redis Dashboard**         | 11835 | Redis cache metrics                         |

### Manual Dashboard Import

```bash
# Download dashboard JSON
curl https://grafana.com/api/dashboards/1860/revisions/21/download -o node-exporter.json

# Upload ke Grafana via UI
```

---

## ⚠️ Alerting Setup (Optional)

### Enable Alerts

1. Uncomment alerting rules di `monitoring/prometheus.yml`:

```yaml
alerting:
  alertmanagers:
    - static_configs:
        - targets:
            - alertmanager:9093

rule_files:
  - /etc/prometheus/alerts.yml
```

2. Deploy AlertManager (optional):

```bash
docker-compose -f docker-compose-monitoring.yml up -d alertmanager
```

3. Pre-defined alert rules tersedia di `monitoring/alerts.yml`:
   - High CPU/Memory/Disk usage
   - Network errors
   - Container restarts
   - Service down detection

---

## 🔐 Security Hardening

### Grafana Password Change

```bash
# Via CLI
docker-compose exec grafana grafana-cli admin reset-admin-password newpassword

# Via API
curl -X POST http://admin:admin@localhost:3000/api/user/password \
  -d '{"oldPassword":"admin","newPassword":"newpassword"}'
```

### Prometheus Access Control (Reverse Proxy)

Setup Caddy/Nginx reverse proxy dengan authentication:

```nginx
# Nginx example
location /prometheus {
    auth_basic "Restricted Access";
    auth_basic_user_file /etc/nginx/.htpasswd;
    proxy_pass http://localhost:9990;
}
```

### Network Isolation

```bash
# Hanya allow monitoring server scrape production metrics
# Di production server firewall:
ufw allow from <MONITORING_SERVER_IP> to any port 9100
```

---

## 📈 Data Retention

### Prometheus Storage

Edit `docker-compose-monitoring.yml`:

```yaml
services:
  prometheus:
    command:
      - "--storage.tsdb.retention.time=30d" # Keep 30 days
      - "--storage.tsdb.retention.size=50GB" # Or max 50GB
```

### Estimated Storage Usage

```
Node Exporter metrics: ~1-2 MB per day
1000s metrics/min scrape rate: ~10-50 MB per day
30 days retention: ~300MB - 1.5GB
```

---

## 🔍 Debugging & Troubleshooting

### Check Scrape Targets

```bash
curl http://localhost:9990/api/v1/targets | jq '.data.activeTargets'
```

### View Prometheus Logs

```bash
docker-compose -f docker-compose-monitoring.yml logs -f prometheus
```

### Test Metric Queries

```bash
# Open http://localhost:9990/graph
# Query examples:
up                                    # All targets status
node_cpu_seconds_total               # CPU metrics
node_memory_MemAvailable_bytes       # Memory available
rate(node_network_receive_bytes_total[5m])  # Network traffic
```

### Reload Prometheus Config

```bash
curl -X POST http://localhost:9990/-/reload
```

---

## 📦 Docker Volumes

```bash
# View stored data
docker volume ls | grep monitoring

# Backup Prometheus data
docker run --rm -v prometheus_data:/data -v $(pwd):/backup \
  busybox tar czf /backup/prometheus-backup.tar.gz /data

# Backup Grafana data
docker run --rm -v grafana_storage:/data -v $(pwd):/backup \
  busybox tar czf /backup/grafana-backup.tar.gz /data
```

---

## 🛑 Stop & Cleanup

```bash
# Stop services
docker-compose -f docker-compose-monitoring.yml down

# Remove volumes (WARNING: deletes all data)
docker-compose -f docker-compose-monitoring.yml down -v

# Production server - stop node exporter
docker-compose -f docker-compose-node-exporter.yml down
```

---

## 📚 Additional Resources

- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/)
- [Node Exporter Metrics](https://github.com/prometheus/node_exporter#collectors)
- [PromQL Query Language](https://prometheus.io/docs/prometheus/latest/querying/basics/)
- [Grafana Dashboard Library](https://grafana.com/grafana/dashboards/)

---

## 🎯 Next Steps

1. ✅ Deploy Node Exporter pada production server
2. ✅ Deploy Prometheus + Grafana di monitoring server
3. ✅ Import pre-built dashboards
4. ⚠️ Configure alerts & notification channels (PagerDuty, Slack, Email)
5. 🔐 Setup reverse proxy dengan SSL/TLS
6. 📊 Create custom dashboards untuk app-specific metrics
7. 🔄 Setup automated backups untuk Prometheus & Grafana data
