#!/usr/bin/env python3
"""Run isolated paired diagnostics through the existing full-chain verifier."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import time
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
REPORTS = ROOT / 'build/load-test-reports'


def sql_snapshot():
    query = """SELECT json_build_object(
      'synchronousCommit', current_setting('synchronous_commit'),
      'synchronousCommitSource', (SELECT source FROM pg_settings WHERE name='synchronous_commit'),
      'roleDatabaseOverrides', (SELECT coalesce(json_agg(setconfig), '[]'::json) FROM pg_db_role_setting),
      'heads', (SELECT count(*) FROM order_service.order_stream_heads),
      'submissions', (SELECT count(*) FROM order_service.order_event_store
                      WHERE event_type = 'OrderSubmissionRequestedV1'),
      'events', (SELECT count(*) FROM order_service.order_event_store),
      'outbox', (SELECT count(*) FROM order_service.order_event_outbox),
      'receipts', (SELECT count(*) FROM order_service.http_order_idempotency),
      'receiptOrders', (SELECT count(DISTINCT response_body::jsonb->>'orderId')
                        FROM order_service.http_order_idempotency),
      'receiptsWithoutOrder', (SELECT count(*) FROM order_service.http_order_idempotency r
         LEFT JOIN order_service.order_stream_heads h
         ON h.aggregate_id = (r.response_body::jsonb->>'orderId')::uuid
         WHERE h.aggregate_id IS NULL))"""
    raw = subprocess.check_output(['docker', 'exec', 'eap-order-postgres-loadtest',
        'psql', '-U', 'admin', '-d', 'eap_order_db', '-Atqc', query], text=True)
    return json.loads(raw)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--campaign-id', required=True)
    parser.add_argument('--duration', type=int, default=180)
    parser.add_argument('--warmup', type=int, default=60)
    parser.add_argument('--repeats', type=int, default=3)
    parser.add_argument('--calibration-only', action='store_true')
    args = parser.parse_args()
    if not args.campaign_id.replace('_', '').replace('-', '').isalnum():
        parser.error('campaign-id must contain only letters, digits, underscores and hyphens')
    if args.duration < 2 or args.warmup < 0 or args.repeats < 1:
        parser.error('invalid duration, warmup or repeats')
    REPORTS.mkdir(parents=True, exist_ok=True)
    schedule = [('CAL_' + mode.upper(), mode, 50, 10, 30) for mode in ('none', 'unique')]
    if not args.calibration_only:
        for repeat in range(1, args.repeats + 1):
            modes = ('none', 'unique') if repeat % 2 else ('unique', 'none')
            schedule += [(f'R{repeat}_{mode.upper()}', mode, 200, args.warmup, args.duration)
                         for mode in modes]
    results = []
    index_path = REPORTS / f'{args.campaign_id}-index.json'
    for suffix, mode, rate, warmup, duration in schedule:
        run_id = f'{args.campaign_id}_{suffix}'
        prefix = REPORTS / f'http-matched-external-{run_id}'
        env = dict(os.environ, RUN_ID=run_id, HTTP_LOAD_DRIVER='k6', HTTP_IDEMPOTENCY_MODE=mode,
            TARGET_ORDER_TPS=str(rate), WARMUP_SECONDS=str(warmup), DURATION_SECONDS=str(duration),
            WORKLOAD_SEED='20260905', USERS_PER_SIDE='500', WAIT_TIMEOUT_SECONDS='240',
            LOADTEST_SERVICE_LAUNCH_MODE='jar', START_SERVICES='true',
            STOP_SERVICES_AFTER_RUN='false', REMOVE_LOADTEST_DATA_AFTER_SUCCESS='false',
            KEEP_RAW_LOADTEST_ARTIFACTS='true', DIAGNOSTICS_LEVEL='light',
            DIAGNOSTIC_SAMPLE_INTERVAL_SECONDS='5', EAP_LOADTEST_SYNCHRONOUS_COMMIT='on',
            EAP_LOADTEST_TRACK_IO_TIMING='on', EAP_LOADTEST_TRACK_WAL_IO_TIMING='on')
        print(json.dumps({'stage': 'starting', 'runId': run_id, 'rate': rate,
                          'warmup': warmup, 'duration': duration}), flush=True)
        started = time.time()
        with Path(f'{prefix}-campaign.log').open('w') as log:
            completed = subprocess.run(['bash', 'scripts/load-test/run-http-matched-external-open-loop.sh',
                run_id], cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT,
                timeout=warmup + duration + 900)
        entry = {'runId': run_id, 'mode': mode, 'targetUniqueOrdersPerSecond': rate,
                 'warmupSeconds': warmup, 'durationSeconds': duration,
                 'exitStatus': completed.returncode, 'wallSeconds': time.time() - started}
        result_path = Path(f'{prefix}-result.json')
        if result_path.exists():
            result = json.loads(result_path.read_text())
            entry.update({name: result.get(name) for name in (
                'benchmarkSchemaVersion', 'validForSustainedCapacity', 'externalHttpLatencyMs',
                'steadyAcceptedOrderTps', 'steadyCompletedTradeTps', 'requiredFieldsMissing',
                'requiredFieldsInvalid', 'capacityClaimAllowed')})
            entry['sourceStable'] = result.get('benchmarkProvenance', {}).get('sourceStable')
            entry['sourceSignature'] = [
                [repo['name'], repo['commit'], repo['workingTreeSha256']]
                for repo in result.get('benchmarkProvenance', {}).get('repositories', [])]
            entry['fingerprints'] = result.get('benchmarkProvenance', {}).get('fingerprints')
            expected = rate * (warmup + duration)
            entry['workloadCorrectnessPassed'] = all(result.get(name) is True for name in (
                'threeServiceTradeIdsEqual', 'assetReconciliationPassed', 'orderReadModelConverged',
                'finalDurableDebtObservationsHealthy', 'steadyDurableDebtObservationsHealthy'))
            entry['exactSchedulePassed'] = (result.get('httpAccepted') == expected
                and result.get('externalScheduledRequests') == expected
                and result.get('externalDroppedIterations') == 0
                and result.get('externalOutOfRangeIterations') == 0
                and result.get('externalDriverExitStatus') == 0
                and result.get('httpIdempotencyMode') == mode)
        if completed.returncode == 0:
            entry['sql'] = sql_snapshot()
            with urllib.request.urlopen('http://localhost:8080/eap-order/actuator/prometheus', timeout=10) as response:
                Path(f'{prefix}-order-final.prom').write_bytes(response.read())
            expected = rate * (warmup + duration)
            sql = entry['sql']
            entry['idempotencyInvariantPassed'] = (
                sql['synchronousCommit'] == 'on'
                and sql['heads'] == sql['submissions'] == expected
                and sql['receipts'] == sql['receiptOrders'] == (expected if mode == 'unique' else 0)
                and sql['receiptsWithoutOrder'] == 0)
        results.append(entry)
        index_path.write_text(json.dumps({'campaignId': args.campaign_id,
            'capacityClaimAllowed': False, 'runs': results}, indent=2) + '\n')
        print(json.dumps({'stage': 'finished', **entry}), flush=True)
        if (completed.returncode != 0 or entry.get('benchmarkSchemaVersion') != 4
                or entry.get('workloadCorrectnessPassed') is not True
                or entry.get('validForSustainedCapacity') is not True
                or entry.get('sourceStable') is not True
                or entry.get('exactSchedulePassed') is not True
                or entry.get('requiredFieldsMissing') != []
                or entry.get('requiredFieldsInvalid') != []
                or entry.get('idempotencyInvariantPassed') is not True):
            raise SystemExit(f'comparison stopped: failed gate for {run_id}; inspect {prefix}-campaign.log')
        if (entry['sourceSignature'] != results[0]['sourceSignature']
                or entry['fingerprints'] != results[0]['fingerprints']):
            raise SystemExit(f'comparison stopped: source changed across arms at {run_id}')


if __name__ == '__main__':
    main()
