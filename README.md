# Monitoring Server

Stack monitoring mandiri untuk Prometheus dan Grafana — dipisah dari kode aplikasi.

**Tujuan**: Menyediakan konfigurasi siap pakai untuk memantau host, exporter, dan layanan jaringan.

**Struktur proyek (ringkas)**

```text
monitoring-server/
├── docker-compose-monitoring.yml
└── monitoring/
    ├── alerts.yml
    ├── alertmanager.yml
    ├── prometheus.yml
    └── grafana/
        └── provisioning/
            ├── dashboards/
            └── datasources/
```

## Persyaratan

- Docker dan Docker Compose (kompatibel dengan `docker compose` v2).
- Port yang digunakan: Prometheus (9990), Grafana (3000).

## Jalankan (Quickstart)

Jalankan stack monitoring dengan file compose bawaan:

```bash
docker compose -f docker-compose-monitoring.yml up -d
```

Jika ingin menulis target node exporter secara otomatis ke Prometheus, set env lalu jalankan:

```bash
MONITORING_TARGET_IPS=192.168.1.4,192.168.1.99 ./setup-monitoring.sh monitoring
```

Kalau target sudah ditulis manual di [monitoring/prometheus.yml](monitoring/prometheus.yml), cukup jalankan:

```bash
./setup-monitoring.sh monitoring
```

## Akses

- Prometheus: http://localhost:9990
- Grafana: http://localhost:3000
- Default Grafana: `admin` / `admin` (ganti segera)

## Konfigurasi yang perlu disesuaikan

- Target scraping Prometheus: edit [monitoring/prometheus.yml](monitoring/prometheus.yml) untuk menambahkan `node_exporter`, `nginx`, atau `snmp_exporter`.
- Untuk node exporter, dua server yang dimonitor pada setup ini adalah `192.168.1.4:9100` dan `192.168.1.99:9100`.
- Command monitoring bisa dijalankan tanpa argumen target: `./setup-monitoring.sh monitoring`.
- Jika ingin auto-update target dari command, pakai env `MONITORING_TARGET_IPS=192.168.1.4,192.168.1.99`.
- Ganti password default Grafana di [docker-compose-monitoring.yml](docker-compose-monitoring.yml).
- Jika menggunakan Alertmanager: aktifkan service terkait di [docker-compose-monitoring.yml](docker-compose-monitoring.yml) dan isi kredensial/aturan di [monitoring/alertmanager.yml](monitoring/alertmanager.yml).

## Provisioning dashboard Grafana

Gunakan script provisioning jika mau mengimpor dashboard default dan datasource:

```bash
./monitoring/provision-grafana.sh
```

## Tips & Troubleshooting singkat

- Periksa log container: `docker compose -f docker-compose-monitoring.yml logs -f`.
- Jika tidak bisa mengakses Grafana, pastikan tidak ada layanan lain (mis. aplikasi lokal) menggunakan port 3000.
- Untuk menambahkan exporter terpisah, lihat file `docker-compose-node-exporter.yml` dan `docker-compose-snmp-exporter.yml` sebagai contoh.

## Selanjutnya

- Sesuaikan `monitoring/prometheus.yml` dengan target Anda.
- Ganti kredensial Grafana dan simpan versi aman (mis. di secret manager).
- Jika mau, saya bisa bantu: menulis contoh `prometheus.yml` untuk node/nginx, atau menerjemahkan README ke Bahasa Inggris.

---

File terkait: [monitoring/prometheus.yml](monitoring/prometheus.yml), [monitoring/alertmanager.yml](monitoring/alertmanager.yml), [monitoring/provision-grafana.sh](monitoring/provision-grafana.sh)