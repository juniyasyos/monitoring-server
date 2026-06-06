# 📊 Monitoring Server - Prometheus & Grafana Stack

Stack monitoring mandiri untuk Prometheus dan Grafana — dipisah dari kode aplikasi.

**Tujuan**: Menyediakan konfigurasi siap pakai untuk memantau host, exporter, dan layanan jaringan Mikrotik.

---

## 📋 Daftar Isi

- [Persyaratan](#persyaratan)
- [Struktur Proyek](#struktur-proyek)
- [Quick Start](#quick-start)
- [Komponen](#komponen)
- [Konfigurasi](#konfigurasi)
- [Monitoring Mikrotik dengan SNMP](#monitoring-mikrotik-dengan-snmp)
- [Provisioning Dashboard](#provisioning-dashboard)
- [Tips & Troubleshooting](#tips--troubleshooting)

---

## 💻 Persyaratan

- Docker dan Docker Compose v2+
- Koneksi jaringan ke target devices:
  - **Node Exporter**: port `9100`
  - **SNMP Exporter**: port `161` (UDP)
  - **Prometheus**: port `9090` (internal)
  - **Grafana**: port `3000`

---

## 📁 Struktur Proyek

```
monitoring-server/
├── docker-compose-monitoring.yml      # Stack utama (Prometheus + Grafana)
├── docker-compose-node-exporter.yml   # Node Exporter untuk target servers
├── docker-compose-snmp-exporter.yml   # SNMP Exporter untuk Mikrotik
├── setup-monitoring.sh                # Script setup otomatis
├── test-snmp-debug.sh                 # Debug script SNMP
├── monitoring/
│   ├── prometheus.yml                 # Konfigurasi Prometheus scrape
│   ├── alerts.yml                     # Alert rules
│   ├── alertmanager.yml               # AlertManager config
│   ├── PROMQL_QUERIES.md              # Contoh PromQL queries
│   ├── provision-grafana.sh           # Script provisioning dashboard
│   └── grafana/
│       └── provisioning/
│           ├── dashboards/
│           │   ├── dashboards.yml
│           │   ├── node-exporter-basic.json
│           │   ├── nginx.json
│           │   └── mikrotik.json
│           └── datasources/
│               └── prometheus.yml
├── README.md
├── MONITORING-SETUP.md
└── check-node-exporter-targets.sh
```

---

## 🚀 Quick Start

### 1️⃣ **Setup Stack Monitoring** (Prometheus + Grafana)

```bash
# Jalankan dengan auto-setup
MONITORING_TARGET_IPS=192.168.1.4,192.168.1.99 bash setup-monitoring.sh monitoring

# Atau manual
docker compose -f docker-compose-monitoring.yml up -d
```

### 2️⃣ **Setup Node Exporter** (di Production Server)

```bash
# Di server production Anda
bash setup-monitoring.sh target-server <MONITORING_SERVER_IP>

# Atau manual
docker compose -f docker-compose-node-exporter.yml up -d
```

### 3️⃣ **Setup SNMP Exporter** (untuk Mikrotik)

```bash
# Di monitoring server
docker compose -f docker-compose-snmp-exporter.yml up -d
```

### 4️⃣ **Akses Web UI**

| Layanan    | URL                      | Kredensial        |
|------------|--------------------------|-------------------|
| Prometheus | http://localhost:9990    | Tidak ada         |
| Grafana    | http://localhost:3000    | `admin` / `admin` |

---

## 🔧 Komponen

### **Prometheus** (Port 9990)
- Time-series database untuk metrics
- Scrape interval: 15 detik (default)
- Data retention: 30 hari (default)
- Ekspor metrics untuk alerting

### **Grafana** (Port 3000)
- Visualisasi dashboards
- Pre-built dashboards tersedia
- Datasource: Prometheus

### **Node Exporter** (Port 9100)
- Metrics sistem (CPU, Memory, Disk, Network)
- Jalan di setiap target server
- Lightweight (~5MB)

### **SNMP Exporter** (Port 9116)
- Translator SNMP → Prometheus
- Support Mikrotik (built-in)
- Module config: `/etc/snmp_exporter/snmp.yml`

---

## ⚙️ Konfigurasi

### **Prometheus Targets** (`monitoring/prometheus.yml`)

#### 1. Node Exporter (Sistem Metrics)
```yaml
- job_name: 'node-exporter-prod'
  static_configs:
    - targets: ['192.168.1.4:9100']
      labels:
        instance: 'server-production'
        server: 'production'
    - targets: ['192.168.1.99:9100']
      labels:
        instance: 'server-tilaka'
        server: 'tilaka'
```

#### 2. SNMP Exporter (Mikrotik)
```yaml
- job_name: 'snmp-mikrotik'
  metrics_path: /snmp
  params:
    auth: [public_v2]
    module: [mikrotik]
  static_configs:
    - targets: ['192.168.1.1']      # IP Mikrotik Router
    - targets: ['192.168.1.100']    # IP Mikrotik Switch
  relabel_configs:
    - source_labels: [__address__]
      target_label: __param_target
    - source_labels: [__param_target]
      target_label: instance
    - target_label: __address__
      replacement: snmp-exporter:9116
```

### **Data Retention**

Edit `docker-compose-monitoring.yml`:

```yaml
services:
  prometheus:
    command:
      - "--storage.tsdb.retention.time=30d"   # Simpan 30 hari
      - "--storage.tsdb.retention.size=50GB"  # Atau max 50GB
```

### **Ganti Password Grafana**

```bash
# Via Grafana CLI
docker compose exec grafana grafana-cli admin reset-admin-password newpassword

# Via API
curl -X POST http://admin:admin@localhost:3000/api/user/password \
  -H "Content-Type: application/json" \
  -d '{"oldPassword":"admin","newPassword":"newpassword"}'
```

---

## 🌐 Monitoring Mikrotik dengan SNMP

### **Setup Prerequisites**

1. **Enable SNMP di Mikrotik**
   ```
   IP → SNMP
   Enabled: ✓
   Community: public_v2 (atau sesuaikan)
   ```

2. **Koneksi Network**
   - Monitoring server harus bisa reach Mikrotik port 161 (UDP)
   - Firewall: `allow from <MONITORING_SERVER> to <MIKROTIK_IP> port 161/udp`

### **Konfigurasi SNMP di Prometheus**

Edit `monitoring/prometheus.yml`:

```yaml
- job_name: 'snmp-mikrotik'
  metrics_path: /snmp
  params:
    auth: [public_v2]              # Ganti jika community berbeda
    module: [mikrotik]
  static_configs:
    - targets: ['192.168.1.1']     # IP Mikrotik Anda
  relabel_configs:
    - source_labels: [__address__]
      target_label: __param_target
    - source_labels: [__param_target]
      target_label: instance
    - target_label: __address__
      replacement: snmp-exporter:9116
```

### **Cara Kerja SNMP Exporter**

```
┌─────────────┐       ┌──────────────────┐       ┌─────────────┐
│ Prometheus  │ ---→  │ SNMP Exporter    │ ---→  │  Mikrotik   │
│ (scrape)    │       │ (localhost:9116) │       │ (SNMP 161)  │
└─────────────┘       └──────────────────┘       └─────────────┘
```

1. Prometheus request metrics ke `/snmp?target=192.168.1.1&module=mikrotik`
2. SNMP Exporter translate query menjadi SNMP request
3. Mikrotik respond dengan data SNMP
4. SNMP Exporter convert ke Prometheus format
5. Metrics dikembalikan ke Prometheus

### **Testing SNMP**

```bash
# 1. Cek SNMP Exporter berjalan
curl http://localhost:9116/metrics | head -5

# 2. Test query Prometheus
curl "http://localhost:9990/api/v1/query?query=up{job=\"snmp-mikrotik\"}"

# 3. Debug dengan script
bash test-snmp-debug.sh
```

### **Metrics Mikrotik Tersedia**

| Metric | Deskripsi |
|--------|-----------|
| `sysUptime` | Uptime device |
| `sysDescr` | Deskripsi sistem |
| `ifInOctets` | Interface RX bytes |
| `ifOutOctets` | Interface TX bytes |
| `hrProcessorLoad` | CPU usage |
| `hrStorageUsed` | Storage/Memory used |

Query example:
```promql
# CPU usage Mikrotik
hrProcessorLoad{job="snmp-mikrotik"}

# Interface traffic
rate(ifInOctets{job="snmp-mikrotik"}[5m])

# Uptime
sysUpTimeInstance{job="snmp-mikrotik"}
```

---

## 📊 Provisioning Dashboard

### **Auto-Provision Built-in Dashboards**

```bash
bash monitoring/provision-grafana.sh
```

Script akan:
- Import dashboard Node Exporter
- Import dashboard Mikrotik (jika JSON ada)
- Setup datasource Prometheus

### **Import Custom Dashboards**

1. Buka Grafana: http://localhost:3000
2. Klik **+ (Create) → Import**
3. Pilih salah satu:

| Dashboard | ID | Type |
|-----------|----|----|
| Node Exporter Full | 1860 | Host metrics |
| Docker & Host | 893 | Container metrics |
| Mikrotik | - | SNMP (custom) |
| MySQL Overview | 7362 | Database |
| Redis | 11835 | Cache |

---

## 🔒 Security

### **Password Management**

```bash
# Ganti Grafana password
docker compose exec grafana grafana-cli admin reset-admin-password newpass

# Ganti Prometheus alert credentials
# Edit docker-compose-monitoring.yml env vars
```

### **Network Security**

```bash
# Restrict port 3000 hanya dari office IP
ufw allow from 192.168.1.0/24 to any port 3000

# Restrict SNMP ke monitoring server saja
ufw allow from <MONITORING_SERVER> to any port 161/udp
```

### **Reverse Proxy (Optional)**

Setup Nginx untuk authentication:

```nginx
location /prometheus {
    auth_basic "Restricted";
    auth_basic_user_file /etc/nginx/.htpasswd;
    proxy_pass http://localhost:9990;
}

location /grafana {
    auth_basic "Restricted";
    auth_basic_user_file /etc/nginx/.htpasswd;
    proxy_pass http://localhost:3000;
}
```

---

## 🆘 Tips & Troubleshooting

### **Port Sudah Digunakan**

```bash
# Cek port 3000
lsof -i :3000

# Cek port 9990
lsof -i :9990

# Kill process jika perlu
kill -9 <PID>
```

### **Prometheus Tidak Bisa Scrape Target**

```bash
# Cek target status di Prometheus
curl http://localhost:9990/api/v1/targets | jq '.data.activeTargets'

# Cek connection ke target
docker exec prometheus curl http://node-exporter-ip:9100/metrics

# Lihat error log
docker compose logs -f prometheus
```

### **SNMP Exporter Gagal**

```bash
# 1. Cek container berjalan
docker compose -f docker-compose-snmp-exporter.yml ps

# 2. Cek koneksi dari container
docker exec snmp-exporter ping 192.168.1.1

# 3. Test SNMP manual (jika snmp-tools installed)
snmpget -v 2c -c public_v2 192.168.1.1 sysUpTime.0

# 4. Debug dengan test script
bash test-snmp-debug.sh
```

### **Grafana Dashboard Blank**

```bash
# 1. Cek datasource connected
# Settings → Data Sources → Prometheus → Test

# 2. Cek PromQL queries valid
# Di Prometheus: http://localhost:9990/graph

# 3. Restart Grafana
docker compose restart grafana
```

### **Storage Full**

```bash
# Kurangi retention
docker compose down
# Edit docker-compose-monitoring.yml
# Ganti: "--storage.tsdb.retention.time=7d" (7 hari)
docker compose up -d

# Atau hapus old data
docker volume rm monitoring-server_prometheus-data
```

### **Logs Monitoring**

```bash
# Real-time logs
docker compose logs -f

# Specific service
docker compose logs -f prometheus
docker compose logs -f grafana
docker compose -f docker-compose-snmp-exporter.yml logs -f snmp-exporter
```

---

## 📚 File Penting

| File | Tujuan |
|------|--------|
| [monitoring/prometheus.yml](monitoring/prometheus.yml) | Konfigurasi scrape targets |
| [monitoring/alerts.yml](monitoring/alerts.yml) | Alert rules |
| [monitoring/alertmanager.yml](monitoring/alertmanager.yml) | AlertManager config |
| [monitoring/PROMQL_QUERIES.md](monitoring/PROMQL_QUERIES.md) | Contoh PromQL |
| [MONITORING-SETUP.md](MONITORING-SETUP.md) | Setup detail lengkap |

---

## 📝 Checklist Setup

- [ ] Docker & Docker Compose installed
- [ ] `docker-compose-monitoring.yml` configured
- [ ] `monitoring/prometheus.yml` targets updated
- [ ] Node Exporter running di production servers
- [ ] SNMP enabled di Mikrotik devices
- [ ] SNMP Exporter running
- [ ] Prometheus targets UP
- [ ] Grafana password changed
- [ ] Dashboards imported
- [ ] Alert rules configured (optional)

---

## 🎯 Selanjutnya

1. **Setup production servers** → Run Node Exporter
2. **Add more targets** → Edit `prometheus.yml`
3. **Import dashboards** → Use provisioning script atau manual import
4. **Configure alerts** → Uncomment `alerting` section di `prometheus.yml`
5. **Monitor Mikrotik** → Setup SNMP community dan enable di router

---

**Butuh bantuan?** Lihat [MONITORING-SETUP.md](MONITORING-SETUP.md) untuk dokumentasi lebih detail.

**Terakhir diupdate**: Juni 2026