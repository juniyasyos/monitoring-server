import http from 'k6/http';
import { check, sleep } from 'k6';

// Konfigurasi load testing
export const options = {
  vus: 10,           // jumlah Virtual Users (pengguna bersamaan)
  duration: '30s',   // durasi test berjalan
  // threshold (batas toleransi) untuk menentukan test sukses/gagal
  thresholds: {
    http_req_duration: ['p(95)<500'], // 95% request harus selesai di bawah 500ms
    http_req_failed: ['rate<0.01'],   // maksimal 1% request yang boleh gagal
  },
};

export default function () {
  // Ganti URL ini dengan website yang ingin Anda test
  const TARGET_URL = 'http://192.168.1.9:8110'; 

  const res = http.get(TARGET_URL);

  // Verifikasi response
  check(res, {
    'status is 200': (r) => r.status === 200,
    'response time OK': (r) => r.timings.duration < 500,
  });

  // Jeda 1 detik antar request tiap Virtual User
  sleep(1);
}
