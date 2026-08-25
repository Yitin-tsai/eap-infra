function positiveInteger(name, defaultValue) {
  const raw = __ENV[name] || String(defaultValue);
  const parsed = Number(raw);
  if (!Number.isInteger(parsed) || parsed <= 0) {
    throw new Error(`${name} must be a positive integer, got: ${raw}`);
  }
  return parsed;
}

function optionalPositiveNumber(name) {
  const raw = __ENV[name];
  if (!raw) {
    return null;
  }
  const parsed = Number(raw);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    throw new Error(`${name} must be a positive number, got: ${raw}`);
  }
  return parsed;
}

export function loadConfig() {
  const targetsFile = __ENV.EAP_TARGETS_FILE;
  if (!targetsFile) {
    throw new Error('EAP_TARGETS_FILE is required');
  }

  const targetOrderTps = positiveInteger('EAP_TARGET_ORDER_TPS', 100);
  const totalSeconds = positiveInteger('EAP_TOTAL_SECONDS', 10);
  return {
    benchmarkContract: __ENV.EAP_BENCHMARK_CONTRACT || 'external-http-matched-steady-state-chain',
    gracefulStop: __ENV.EAP_K6_GRACEFUL_STOP || '15s',
    httpTimeout: __ENV.EAP_K6_HTTP_TIMEOUT || '10s',
    maxP95Milliseconds: optionalPositiveNumber('EAP_K6_MAX_P95_MS'),
    preAllocatedVUs: positiveInteger(
      'EAP_K6_PRE_ALLOCATED_VUS',
      Math.max(64, targetOrderTps),
    ),
    reportPath: __ENV.EAP_K6_REPORT_PATH || '',
    runId: __ENV.EAP_RUN_ID || 'unknown',
    summaryPath: __ENV.EAP_K6_SUMMARY_PATH || '',
    targetOrderTps,
    targetsFile,
    totalSeconds,
  };
}

export function buildOptions(config, expectedRequests) {
  const thresholds = {
    checks: ['rate==1'],
    dropped_iterations: ['count==0'],
    eap_out_of_range_iterations: ['count==0'],
    http_req_failed: ['rate==0'],
    http_reqs: [`count==${expectedRequests}`],
  };
  if (config.maxP95Milliseconds !== null) {
    thresholds.http_req_duration = [`p(95)<${config.maxP95Milliseconds}`];
  }

  return {
    discardResponseBodies: true,
    scenarios: {
      matchedOrders: {
        executor: 'constant-arrival-rate',
        rate: config.targetOrderTps,
        timeUnit: '1s',
        duration: `${config.totalSeconds * 1000 - 1}ms`,
        preAllocatedVUs: config.preAllocatedVUs,
        gracefulStop: config.gracefulStop,
        tags: {
          benchmark_contract: config.benchmarkContract,
          run_id: config.runId,
        },
      },
    },
    summaryTrendStats: ['avg', 'min', 'med', 'p(90)', 'p(95)', 'p(99)', 'max'],
    thresholds,
  };
}
