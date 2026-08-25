function values(data, name) {
  const metric = data.metrics && data.metrics[name];
  return (metric && (metric.values || metric)) || {};
}

function number(value, digits = 2) {
  return Number.isFinite(value) ? value.toFixed(digits) : 'n/a';
}

function count(data, name) {
  const metric = values(data, name);
  return metric.count || 0;
}

function rate(data, name) {
  const metric = values(data, name);
  return metric.rate || 0;
}

function markdown(data, config, expectedRequests) {
  const requests = count(data, 'http_reqs');
  const dropped = count(data, 'dropped_iterations');
  const outOfRange = count(data, 'eap_out_of_range_iterations');
  const failedRate = rate(data, 'http_req_failed');
  const checkValues = values(data, 'checks');
  const failedChecks = checkValues.fails || 0;
  const duration = values(data, 'http_req_duration');
  const driverPassed = requests === expectedRequests
    && dropped === 0
    && outOfRange === 0
    && failedRate === 0
    && failedChecks === 0
    && (config.maxP95Milliseconds === null
      || duration['p(95)'] < config.maxP95Milliseconds);

  return `# k6 Driver Report: ${config.runId}

> This report validates HTTP load generation only. EAP capacity and correctness
> require the final cross-service result report.

## Decision

- Driver gate: **${driverPassed ? 'PASS' : 'REJECT'}**
- Benchmark contract: \`${config.benchmarkContract}\`
- Workload: constant arrival rate, prepared finite request schedule

## Offered Load

| Metric | Value |
| --- | ---: |
| Target orders/s | ${config.targetOrderTps} |
| Duration | ${config.totalSeconds}s |
| Expected requests | ${expectedRequests} |
| Executed requests | ${requests} |
| Observed requests/s | ${number(rate(data, 'http_reqs'))} |
| Dropped iterations | ${dropped} |
| Out-of-range iterations | ${outOfRange} |
| HTTP failure ratio | ${number(failedRate * 100, 4)}% |
| Failed checks | ${failedChecks} |

## HTTP Latency

| Metric | Milliseconds |
| --- | ---: |
| average | ${number(duration.avg)} |
| median | ${number(duration.med)} |
| p90 | ${number(duration['p(90)'])} |
| p95 | ${number(duration['p(95)'])} |
| p99 | ${number(duration['p(99)'])} |
| maximum | ${number(duration.max)} |

## Interpretation Boundary

k6 can prove that the requested HTTP schedule was offered without driver drops and
that the HTTP responses met the configured checks. It cannot prove that MatchEngine,
Order, and Wallet produced identical trades, reconciled assets, drained queues and
DLQs, or cleared Redis reservations. Read the generated EAP result report for those
gates.
`;
}

export function writeSummary(data, config, expectedRequests) {
  const outputs = {
    stdout: `k6 driver artifacts: summary=${config.summaryPath || '<disabled>'}, report=${config.reportPath || '<disabled>'}\n`,
  };
  if (config.summaryPath) {
    outputs[config.summaryPath] = `${JSON.stringify(data, null, 2)}\n`;
  }
  if (config.reportPath) {
    outputs[config.reportPath] = markdown(data, config, expectedRequests);
  }
  return outputs;
}
