import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  stages: [
    { duration: '30s', target: 50 },   // pemanasan
    { duration: '1m', target: 100 },   // naik ke 100 user
    { duration: '1m', target: 200 },   // naik ke 200 user
    { duration: '2m', target: 400 },   // puncak 400 user
    { duration: '1m', target: 400 },   // tahan 400 user
    { duration: '30s', target: 0 },    // turun perlahan
  ],

  thresholds: {
    http_req_failed: ['rate<0.01'],        // error maksimal 1%
    http_req_duration: ['p(95)<1000'],     // 95% request di bawah 1 detik
    checks: ['rate>0.99'],                 // 99% check harus sukses
  },
};

export default function () {
  const TARGET_URL = 'http://192.168.1.9:8110';

  const res = http.get(TARGET_URL);

  check(res, {
    'status is 200': (r) => r.status === 200,
    'response time < 1s': (r) => r.timings.duration < 1000,
  });

  sleep(1);
}