import http from 'k6/http';
import { check, sleep } from 'k6';

// =========================================================================                                        
// 1. INIT CONTEXT                                                                                                  
// Sesuaikan URL ini dengan APP_URL yang ada di file .env aplikasi Anda                                             
// (Misalnya: http://127.0.0.1:8010, atau sesuaikan jika Anda memakai IP server)                                    
// =========================================================================                                        
const BASE_URL = 'http://127.0.0.1:8010';

export const options = {
  stages: [
    { duration: '10s', target: 20 },
    { duration: '30s', target: 50 },
    { duration: '10s', target: 0 },
  ],
  thresholds: {
    http_req_duration: ['p(95)<1000'],
    http_req_failed: ['rate<0.05'],
  },
};

// =========================================================================                                        
// 2. VU CODE: Eksekusi berulang-ulang oleh Virtual Users                                                           
// =========================================================================                                        
export default function () {
  // A. Dapatkan CSRF Token & Session Cookie                                                                        
  // Harus dilakukan request GET ke /login agar Laravel meng-issue cookie session                                   
  // dan token CSRF untuk kita pakai pada POST request berikutnya.                                                  
  const resInit = http.get(`${BASE_URL}/login`);

  let csrfToken = '';
  if (resInit.cookies['XSRF-TOKEN'] && resInit.cookies['XSRF-TOKEN'].length > 0) {
    // Decode value XSRF-TOKEN untuk digunakan di header POST                                                       
    csrfToken = decodeURIComponent(resInit.cookies['XSRF-TOKEN'][0].value);
  }

  // B. Siapkan payload login menggunakan 'nip' dan 'password' (Sesuai parameter controller Anda)                   
  const payload = JSON.stringify({
    nip: '0000.00000',
    password: 'adminpassword',
  });

  const params = {
    headers: {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'X-XSRF-TOKEN': csrfToken, // Menyertakan token CSRF ke header request agar tidak terjadi "419 Page Expired"  
    },
    // Kita matikan auto-redirect k6. Saat login berhasil, Laravel mengembalikan 302 Redirect.                      
    // Menangkap respon 302 ini lebih efisien dibanding mengikuti rentetan redirect.                                
    redirects: 0
  };

  // C. Lakukan request POST ke endpoint /login (bukan /api/login)                                                  
  const resLogin = http.post(`${BASE_URL}/login`, payload, params);

  // D. Verifikasi respons
  check(resLogin, {
    // Laravel mengembalikan status HTTP 302 jika login sukses dan di-redireFct ke Dashboard
    // atau 409 jika Controller memanfaatkan Inertia::location secara strict (Inertia mode).
    'login successful (redirected)': (r) => r.status === 302 || r.status === 409 || r.status === 200,

    // Status HTTP 422 dikembalikan jika ada kegagalan otentikasi/validasi (NIP salah/throttle)
    'no validation error (not 422)': (r) => r.status !== 422,
  });

  // =========================================================================
  // 3. DYNAMIC SLEEP: Jeda persis seperti disarankan
  // =========================================================================
  sleep(Math.random() * 1 + 1);
}