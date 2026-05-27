# Monitoring Configuration Files

Directory untuk Prometheus dan Grafana configuration files.

## 📁 Structure

```
monitoring/
├── prometheus.yml                    # Prometheus configuration (EDIT THIS!)
├── alerts.yml                        # Alert rules (optional)
├── alertmanager.yml                  # AlertManager config (optional)
├── PROMQL_QUERIES.md                 # Common PromQL query examples
├── grafana/
│   └── provisioning/
│       ├── datasources/
│       │   └── prometheus.yml       # Auto-provision Prometheus as datasource
│       └── dashboards/
│           └── dashboards.yml       # Auto-load dashboard configs
└── README.md                         # This file
```

## ⚙️ Configuration Files

### prometheus.yml
**YANG PALING PENTING!** File ini mendefinisikan apa yang di-scrape oleh Prometheus.

**Harus dikonfigurasi:**
```yaml
scrape_configs:
  - job_name: 'node-exporter-prod'
    static_configs:
      - targets: ['<PROD_SERVER_IP>:9100']  # ← Ganti dengan IP production server
```

**Contoh IP configurations:**
- Local: `localhost:9100`
- LAN: `192.168.1.100:9100`
- Remote: `prod-server.example.com:9100`

### alerts.yml
Optional file untuk mendefinisikan alert rules. 

**Format:**
```yaml
groups:
  - name: group_name
    rules:
      - alert: AlertName
        expr: PromQL expression
        for: 5m
        labels:
          severity: warning
```

### alertmanager.yml
Optional file untuk konfigurasi notification channels.

**Supported channels:**
- Slack
- Email
- PagerDuty
- Webhook
- Discord

## 🔧 How to Configure

### 1. Edit prometheus.yml
```bash
nano monitoring/prometheus.yml
```

Cari section `scrape_configs` dan update `<PROD_SERVER_IP>`:

```yaml
- job_name: 'node-exporter-prod'
  static_configs:
    - targets: ['your-server-ip:9100']
```

### 2. Optional: Enable Alerts

Uncomment section `alerting` dan `rule_files` di prometheus.yml:

```yaml
alerting:
  alertmanagers:
    - static_configs:
        - targets:
            - alertmanager:9093

rule_files:
  - /etc/prometheus/alerts.yml
```

### 3. Optional: Configure Notifications

Edit `alertmanager.yml` untuk setup notification channels.

## 📊 Grafana Provisioning

### Auto-provision Datasource
File `grafana/provisioning/datasources/prometheus.yml` akan auto-add Prometheus sebagai datasource.

Jika ingin change connection details:
```yaml
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090  # ← Change this if needed
```

### Auto-load Dashboards
Uncomment di `grafana/provisioning/dashboards/dashboards.yml` untuk auto-import dashboard dari Grafana Dashboard Library.

## 🚀 Quick Start

```bash
# 1. Konfigurasi IP production server
./monitoring-helper.sh configure

# 2. Start services
./monitoring-helper.sh start

# 3. Verify
./monitoring-helper.sh health-check

# 4. Access
# Prometheus: http://localhost:9990
# Grafana:    http://localhost:3000
```

## 📝 Common Configuration Changes

### Change Scrape Interval
```yaml
global:
  scrape_interval: 15s  # Change to desired interval (default: 15s)
```

### Add More Scrape Targets
```yaml
scrape_configs:
  # Existing target
  - job_name: 'node-exporter-prod'
    static_configs:
      - targets: ['192.168.1.100:9100']
  
  # Add new target
  - job_name: 'mysql-prod'
    static_configs:
      - targets: ['192.168.1.100:9104']
```

### Disable Alert Rules
```yaml
# Comment out atau delete rule_files section
# rule_files:
#   - /etc/prometheus/alerts.yml
```

## 🔄 Reload Configuration

Tanpa restart services:

```bash
# Method 1: Using helper script (automatic)
./monitoring-helper.sh configure

# Method 2: Manual curl
curl -X POST http://localhost:9990/-/reload

# Method 3: Via docker-compose
docker-compose -f docker-compose-monitoring.yml restart prometheus
```

## 🧪 Verify Configuration

```bash
# Check Prometheus config syntax
docker-compose -f docker-compose-monitoring.yml exec prometheus \
  promtool check config /etc/prometheus/prometheus.yml

# Check alert rules
docker-compose -f docker-compose-monitoring.yml exec prometheus \
  promtool check rules /etc/prometheus/alerts.yml

# View active scrape targets
curl http://localhost:9990/api/v1/targets | jq '.data.activeTargets'
```

## 📚 Reference

- [Prometheus Configuration](https://prometheus.io/docs/prometheus/latest/configuration/configuration/)
- [Alert Rules Format](https://prometheus.io/docs/prometheus/latest/configuration/alerting_rules/)
- [AlertManager Configuration](https://prometheus.io/docs/alerting/latest/configuration/)
- [Grafana Provisioning](https://grafana.com/docs/grafana/latest/administration/provisioning/)

## 💡 Tips

1. **Backup before changes**: `./monitoring-helper.sh backup`
2. **Check logs**: `./monitoring-helper.sh logs prometheus`
3. **Monitor changes**: `docker-compose -f docker-compose-monitoring.yml logs -f`
4. **Test PromQL**: Use Prometheus web UI (http://localhost:9990/graph)
