import http from 'k6/http';
import { check, sleep } from 'k6';
import exec from 'k6/execution';

// ===============================
// CONFIG
// ===============================

// Bisa diganti lewat ENV:
// k6 run -e TARGET_URL=http://192.168.1.9:7100/login test.js
const TARGET_URL = __ENV.TARGET_URL || 'http://192.168.1.9:7100/login';

const MAX_VUS = 150;
const RESPONSE_LIMIT_MS = 1000;

// ===============================
// OPTIONS
// ===============================

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
    http_req_failed: ['rate<0.01'],                // error maksimal 1%
    http_req_duration: [`p(95)<${RESPONSE_LIMIT_MS}`], // 95% request harus < 1 detik
    checks: ['rate>0.99'],                         // 99% check harus sukses
  },
};

// ===============================
// SETUP
// ===============================

export function setup() {
  console.log('========================================');
  console.log('K6 LOAD TEST STARTED');
  console.log('========================================');
  console.log(`Target URL          : ${TARGET_URL}`);
  console.log(`Max VUs             : ${MAX_VUS}`);
  console.log(`Response threshold  : p95 < ${RESPONSE_LIMIT_MS}ms`);
  console.log(`Allowed failed rate : < 1%`);
  console.log('Stages:');
  console.log('- 30s  -> 50 VU');
  console.log('- 1m   -> hold 50 VU');
  console.log('- 30s  -> 100 VU');
  console.log('- 1m   -> hold 100 VU');
  console.log('- 30s  -> 150 VU');
  console.log('- 1m   -> hold 150 VU');
  console.log('- 30s  -> ramp down');
  console.log('========================================');
}

// ===============================
// TEST
// ===============================

export default function () {
  const res = http.get(TARGET_URL, {
    timeout: '60s',
    tags: {
      endpoint: 'login',
      target_url: TARGET_URL,
    },
  });

  const isStatusOk = res.status === 200;
  const isFastEnough = res.timings.duration < RESPONSE_LIMIT_MS;

  check(res, {
    'status is 200': () => isStatusOk,
    [`response time < ${RESPONSE_LIMIT_MS}ms`]: () => isFastEnough,
  });

  // Log hanya jika bermasalah agar terminal tidak terlalu ramai
  if (!isStatusOk || res.error) {
    console.error(
      JSON.stringify({
        type: 'REQUEST_FAILED',
        target_url: TARGET_URL,
        vu: exec.vu.idInTest,
        iteration: exec.scenario.iterationInTest,
        status: res.status,
        error: res.error,
        error_code: res.error_code,
        duration_ms: Number(res.timings.duration.toFixed(2)),
        blocked_ms: Number(res.timings.blocked.toFixed(2)),
        waiting_ms: Number(res.timings.waiting.toFixed(2)),
        receiving_ms: Number(res.timings.receiving.toFixed(2)),
        body_preview: res.body ? res.body.substring(0, 200) : null,
      })
    );
  }

  // Log request lambat, tapi bukan semua request
  if (isStatusOk && !isFastEnough) {
    console.warn(
      JSON.stringify({
        type: 'SLOW_REQUEST',
        target_url: TARGET_URL,
        vu: exec.vu.idInTest,
        iteration: exec.scenario.iterationInTest,
        status: res.status,
        duration_ms: Number(res.timings.duration.toFixed(2)),
        waiting_ms: Number(res.timings.waiting.toFixed(2)),
      })
    );
  }

  sleep(1);
}

// ===============================
// SUMMARY
// ===============================

export function teardown() {
  console.log('========================================');
  console.log('K6 LOAD TEST FINISHED');
  console.log(`Target URL: ${TARGET_URL}`);
  console.log('Check summary above for:');
  console.log('- http_req_failed');
  console.log('- http_req_duration p95');
  console.log('- status is 200');
  console.log('- response time threshold');
  console.log('========================================');
}