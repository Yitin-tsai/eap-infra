import { check } from 'k6';
import exec from 'k6/execution';
import http from 'k6/http';
import { Counter } from 'k6/metrics';

import { buildOptions, loadConfig } from './lib/config.js';
import { loadPreparedTargets, materializeRequest } from './lib/prepared-workload.js';
import { writeSummary } from './lib/report.js';

const config = loadConfig();
const expectedRequests = config.targetOrderTps * config.totalSeconds;
const targets = loadPreparedTargets(config.targetsFile, expectedRequests);
const outOfRangeIterations = new Counter('eap_out_of_range_iterations');

export const options = buildOptions(config, expectedRequests);

export default function () {
  const index = exec.scenario.iterationInTest;
  if (index >= targets.length) {
    outOfRangeIterations.add(1);
    return;
  }

  const request = materializeRequest(targets[index], config.httpTimeout);
  const response = http.request(request.method, request.url, request.body, request.params);
  check(response, {
    'HTTP status accepted': (candidate) => candidate.status >= 200 && candidate.status < 300,
  });
}

export function handleSummary(data) {
  return writeSummary(data, config, expectedRequests);
}
