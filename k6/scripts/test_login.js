import http from 'k6/http';
import { check, sleep } from 'k6';

// =========================================================================                                                                                      
// 1. INIT CONTEXT: Deklarasi data statis di sini (di luar fungsi default)                                                                                        
// Ini menghemat memori dan CPU karena k6 hanya mengeksekusinya 1x per VU,                                                                                        
// bukan setiap kali iterasi request.                                                                                                                             
// =========================================================================                                                                                      

const LOGIN_URL = 'http://192.168.1.9:8110/api/login';

// Lakukan JSON.stringify cukup sekali di Init Context                                                                                                            
const payload = JSON.stringify({
  nip: '0000.00000',
  password: 'adminpassword',
});

const params = {
  headers: {
    'Content-Type': 'application/json',
  },
};

// Konfigurasi Load Testing                                                                                                                                       
export const options = {
  stages: [
    { duration: '10s', target: 20 },
    { duration: '30s', target: 50 },
    { duration: '10s', target: 0 },
  ],
  thresholds: {
    http_req_duration: ['p(95)<1000'], // 95% request selesai di bawah 1s                                                                                         
    http_req_failed: ['rate<0.05'],    // Toleransi error max 5%                                                                                                  
  },
};

// =========================================================================                                                                                      
// 2. VU CODE: Fungsi yang akan dieksekusi berulang-ulang oleh Virtual Users                                                                                      
// =========================================================================                                                                                      

export default function () {
  // Melakukan HTTP POST request                                                                                                                                  
  const res = http.post(LOGIN_URL, payload, params);

  // Memverifikasi respons server                                                                                                                                 
  check(res, {
    'status is 200': (r) => r.status === 200,

    // Validasi yang lebih akurat (Opsional tapi disarankan)                                                                                                      
    // Sebaiknya parse ke format JSON jika respons dari API Anda adalah JSON                                                                                      
    'login successful (has token)': (r) => {
      // Jika statusnya bukan 200, langsung anggap gagal agar tidak repot mem-parsing                                                                             
      if (r.status !== 200) return false;

      // -- UNCOMMENT blok di bawah jika ingin validasi isi respons lebih dalam --                                                                                
      /*                                                                                                                                                          
      try {                                                                                                                                                       
        const responseBody = r.json();                                                                                                                            
        // Ubah 'token' dengan field spesifik yang dikirim backend Anda ketika login sukses                                                                       
        return responseBody.hasOwnProperty('token') || responseBody.token !== undefined;                                                                          
      } catch (e) {                                                                                                                                               
        return false; // Gagal jika body tidak bisa diparse menjadi JSON                                                                                          
      }                                                                                                                                                           
      */

      return true; // Hapus baris ini jika menggunakan blok try-catch di atas                                                                                     
    },
  });

  // =========================================================================
  // 3. DYNAMIC SLEEP: Jeda yang realistis
  // =========================================================================
  // Jeda persis 1 detik (sleep(1)) akan membuat gelombang request yang 
  // sangat tidak realistis (seperti robot).
  // Sebaiknya gunakan Math.random() untuk jeda yang acak (misal 1 hingga 2 detik)
  // menyimulasikan 'think time' perilaku manusia yang bervariasi.
  sleep(Math.random() * 1 + 1);
}