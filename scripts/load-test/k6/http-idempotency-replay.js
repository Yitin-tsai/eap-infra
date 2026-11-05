import { check } from 'k6';
import exec from 'k6/execution';
import http from 'k6/http';
import { Counter } from 'k6/metrics';
import { buildOptions, loadConfig } from './lib/config.js';
import { loadPreparedTargets, materializeRequest } from './lib/prepared-workload.js';
import { writeSummary } from './lib/report.js';
import { sameReceipt } from './lib/idempotency.js';

// Separate phase: all operations must already have committed receipts.
// Requests/s here measures replay attempts, never new accepted orders/s.
const config = { ...loadConfig(), idempotencyMode: 'unique', trafficClass: 'replay-only' };
const expectedRequests = config.targetOrderTps * config.totalSeconds;
const targets = loadPreparedTargets(config.targetsFile, expectedRequests, 'unique');
const outOfRange = new Counter('eap_out_of_range_iterations');
export const options = { ...buildOptions(config, expectedRequests), discardResponseBodies: false };

export default function () {
  const index = exec.scenario.iterationInTest;
  if (index >= targets.length) {
    outOfRange.add(1);
    return;
  }
  const target = targets[index];
  const request = materializeRequest(target, config.httpTimeout);
  request.params.responseType = 'text';
  const response = http.request(request.method, request.url, request.body, request.params);
  let actual = null;
  try { actual = response.json(); } catch (_) { /* check below fails closed */ }
  check(response, {
    'original receipt returned': () => response.status === 200 && sameReceipt(actual, target.expectedResponse),
  });
}

export function handleSummary(data) {
  return writeSummary(data, config, expectedRequests);
}
