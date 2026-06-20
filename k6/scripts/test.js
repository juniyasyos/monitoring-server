import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  stages: [
    { duration: '30s', target: 50 },    // naik ke 50 VU
    { duration: '1m', target: 50 },     // tahan 50 VU

    { duration: '30s', target: 100 },   // naik ke 100 VU
    { duration: '1m', target: 100 },    // tahan 100 VU

    { duration: '30s', target: 150 },   // naik ke 150 VU
    { duration: '1m', target: 150 },    // tahan 150 VU

    { duration: '30s', target: 0 },     // turun perlahan
  ],

  thresholds: {
    http_req_failed: ['rate<0.01'],        // error maksimal 1%
    http_req_duration: ['p(95)<1000'],     // 95% request harus < 1 detik
    checks: ['rate>0.99'],                 // 99% check harus sukses
  },
};

export default function () {
  const TARGET_URL = 'http://192.168.1.9:8110/login';

  const res = http.get(TARGET_URL);

  check(res, {
    'status is 200': (r) => r.status === 200,
    'response time < 1s': (r) => r.timings.duration < 1000,
  });

  sleep(1);
}