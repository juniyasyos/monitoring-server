# Dokumentasi Penggunaan Ansible untuk K6 Load Testing

Dokumen ini menjelaskan cara menggunakan Ansible Playbook `k6-test-playbook.yml` untuk melakukan Load Testing menggunakan **k6**. Playbook ini dirancang untuk berjalan secara fleksibel dan dinamis, memungkinkan Anda mengubah target host, port, dan script tanpa perlu mengubah baris kode apa pun di dalam playbook maupun script k6.

## Prasyarat
- **Ansible** sudah terinstall di lokal/server.
- **Docker** sudah terinstall dan berjalan (karena playbook ini menjalankan k6 di dalam container Docker `grafana/k6`).

---

## Variabel yang Tersedia

Berikut adalah variabel-variabel yang dapat disesuaikan (override) saat mengeksekusi playbook:

| Variabel | Nilai Default | Deskripsi |
| :--- | :--- | :--- |
| `protocol` | `http` | Protokol yang digunakan (`http` atau `https`). |
| `target_host` | `192.168.1.9` | IP Address atau domain target. |
| `target_port` | `7100` | Port aplikasi yang menjadi target. |
| `target_endpoint`| `/login` | Path atau endpoint yang ingin ditest. |
| `script_name` | `test.js` | Nama file script k6 yang berada di dalam folder `k6/scripts/`. |

---

## Cara Penggunaan

### 1. Menjalankan Test dengan Target Default
Secara bawaan, test akan mengarah ke `http://192.168.1.9:7100/login` menggunakan file script `test.js`. Untuk menjalankannya, gunakan perintah:

```bash
ansible-playbook k6-test-playbook.yml
```

### 2. Menjalankan Test dengan Custom Host dan Port (Dinamis)
Jika Anda ingin mengetes environment atau aplikasi di IP dan port yang berbeda (misalnya: `http://10.0.0.5:8080/api/health`), gunakan flag `-e` atau `--extra-vars`:

```bash
ansible-playbook k6-test-playbook.yml -e "target_host=10.0.0.5 target_port=8080 target_endpoint=/api/health"
```

### 3. Menggunakan Script K6 yang Lain
Jika Anda memiliki beberapa skenario test (misal Anda mempunyai file `test_login.js` di dalam folder `k6/scripts/`), Anda dapat merubah nama script yang akan dijalankan:

```bash
ansible-playbook k6-test-playbook.yml -e "script_name=test_login.js target_host=192.168.1.10"
```

### 4. Mengetes Aplikasi dengan HTTPS
Jika Anda ingin melakukan pengujian pada URL dengan secure protocol (`https://api.example.com:443/data`), ubah parameter `protocol` menjadi `https`:

```bash
ansible-playbook k6-test-playbook.yml -e "protocol=https target_host=api.example.com target_port=443 target_endpoint=/data"
```

---

## Membaca Hasil Test
Setelah playbook dijalankan, Ansible akan mendownload image K6 (jika belum ada) dan memulai pengetesan. Karena playbook ini diset menggunakan `ignore_errors: true`, apabila target sedang down atau terdapat *threshold* k6 yang gagal, Ansible akan terus melanjutkan task untuk menampilkan output log dari k6 pada terminal. 

Anda akan melihat ringkasan metrics dari K6 di bagian akhir task bernama:
**`TASK [Tampilkan hasil test k6]`**
