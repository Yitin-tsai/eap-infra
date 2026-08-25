# Distributed Capacity and Front-Half Scaling Tooling - 2026-08-20

## Goal

The current laptop result mixes two limits: EAP service work and the load generator,
databases, broker, JVMs, and monitoring processes competing for one host. Isolated
service diagnostics are faster, but their rates cannot be multiplied or combined to
derive a full-system TPS number. The next two bounded tasks are therefore:

1. move the HTTP load generator to another host without changing the business path;
2. test whether the Order front half benefits from a coordinated connection budget
   before considering code-level writer admission or service replicas.

Neither task changes current capacity evidence until it produces repeatable,
correctness-gated results.

## Task 1: Separated HTTP Load Generator

`scripts/load-test/run-http-matched-external-open-loop.sh` now implements
`LOAD_GENERATOR_PLACEMENT=remote-host`. The orchestrator:

1. prepares the same shuffled, finite workload manifest and checksummed Vegeta
   targets used by the co-located run;
2. copies the targets and `remote-vegeta-driver.sh` to a restricted
   `/tmp/eap-loadtest-<run-id>` directory over SSH;
3. verifies the checksum, remote toolchain, Order health reachability, clock skew,
   operating system, architecture, and logical CPU count;
4. runs only the open-loop HTTP attack remotely;
5. returns compressed per-request results, the filtered Vegeta report, process
   timing, and driver metadata;
6. applies the existing local Java trade-ID, asset, order-book, reservation, queue,
   DLQ, offered-load, completion, and backlog gates.

The helper removes the synthetic Vegeta end-of-target result before counting or
reporting requests. It requires exactly one retained result per manifest target and
does not retain the raw binary attack stream.

Example:

```bash
HTTP_LOAD_DRIVER=vegeta \
LOAD_GENERATOR_PLACEMENT=remote-host \
REMOTE_DRIVER_SSH_TARGET=loadtest@192.0.2.20 \
ORDER_URL=http://192.0.2.10:8080/eap-order \
TARGET_ORDER_TPS=648 \
WARMUP_SECONDS=60 \
DURATION_SECONDS=900 \
WORKLOAD_SEED=20260820 \
DIAGNOSTICS_LEVEL=none \
bash scripts/load-test/run-http-matched-external-open-loop.sh \
  DISTRIBUTED_648_SEED_20260820_R1
```

The address values are examples. A valid experiment must record the real service
and driver host boundaries without publishing credentials.

### Promotion gate

A separated-driver result is useful only after a co-located and remote A/B uses the
same commit, seed, rate, warm-up, duration, monitor interval, service settings, and
reset contract. Both runs must supply every target and pass exact three-service
trade IDs, assets, final queue/DLQ drain, order-book cleanup, reservation cleanup,
offered-load, completion, and backlog gates. A short run validates the harness; a
long-window repeat is required to change a sustained boundary.

This topology isolates the HTTP driver. It does not yet distribute EAP services or
PostgreSQL, and it does not prove horizontal scaling.

## Task 2: Order Front-Half Budget Matrix

`scripts/load-test/run-front-half-pool-budget-matrix.sh` defines three fixed
load-test-only Order JDBC profiles:

| Profile | Command max/min | Consumer max/min | Projection max/min | Total max |
| --- | ---: | ---: | ---: | ---: |
| `baseline-58` | `35/35` | `20/5` | `3/1` | `58` |
| `balanced-48` | `30/20` | `16/4` | `2/1` | `48` |
| `balanced-40` | `26/16` | `12/3` | `2/1` | `40` |

The controlled variable is the coordinated profile, not one individual pool. Every
profile uses the same one-sided `order-admission-chain`, target, event count,
duration, diagnostics level, and clean JVM restart policy. Two repeats are required
by default. The runner writes each existing repeat summary plus one matrix summary.

```bash
bash scripts/load-test/run-front-half-pool-budget-matrix.sh --plan

# Run only after the sustained transition has been reproduced with pool-attributed
# evidence and the host is otherwise idle.
RUN_PREFIX=GLT_20260820_FRONT_HALF_BUDGET_R1 \
TARGET_TPS=1300 \
EVENTS=10000 \
REPEATS=2 \
bash scripts/load-test/run-front-half-pool-budget-matrix.sh --execute
```

This matrix does not repeat the previously rejected command-pool-24 experiment.
That test changed the command pool alone and showed no full-chain benefit. The new
matrix exists to test an aggregate cross-pool contention hypothesis if a fresh
sustained diagnostic supports it.

### Adoption gate

Order admission results can eliminate a candidate cheaply. They cannot adopt it.
A candidate advances only if both repeats pass and improve admission throughput or
tail latency without increasing connection acquisition, PostgreSQL waits, queue
debt, or convergence time. It must then pass a shuffled mixed HTTP full-chain A/B
with identical seed and workload, exact durable correctness, and final drain.

## Current Decision

- Remote-driver orchestration is implemented and locally tool-tested. A real remote
  run is blocked only by the absence of a second reachable host.
- The front-half matrix was executed as
  `GLT_20260820_FRONT_HALF_BUDGET_R1` at an offered target of `1300 orders/s`,
  `10400` accepted orders per repeat, and two repeats per profile. Every underlying
  run accepted all requests, reached the exact front-half state, drained its queues,
  and had no capacity-invalid reason. None reached the separately configured
  `1170 orders/s` order-book threshold, so this remains a saturation diagnostic and
  not capacity evidence.
- `baseline-58` averaged `1042.99 order-book admissions/s`; `balanced-48` averaged
  `999.05/s` (`-4.2%`); and `balanced-40` averaged `996.15/s` (`-4.5%`) with a
  `17.2%` two-run spread. Reducing the aggregate connection budget did not improve
  admission throughput or stability. Both candidate profiles are rejected and no
  full-chain promotion run is justified.
- Baseline repeat 1 followed an interrupted full-chain run and inherited cumulative
  service timer history before the benchmark reset. Its current-run counts and
  throughput converged, but it is excluded from fine-grained timer comparisons.
  Baseline repeat 2 and both candidate repeats started with clean service metrics.
- No application connection pool, transaction boundary, listener concurrency, or
  production setting changed.
- Running multiple Order replicas is not the next safe experiment. Scheduled
  relays, projectors, and recovery workers need explicit single-owner or partition
  semantics before replica throughput can be interpreted cleanly.
- The release-pinned same-host capacity boundary and all existing isolated,
  short-window, sequential, and current-worktree classifications remain unchanged.
- A follow-up current-worktree diagnostic showed that allocating 64 market sequence
  values per Redis call stabilized local front-half latency, but that configuration
  is rejected for adoption because independent Order replicas could violate global
  arrival ordering. A separate 16-connection Lettuce pool repeat exhausted its pool
  and returned HTTP 500. The current per-order sequence allocation and shared native
  Redis connection remain unchanged.

The compact diagnostic artifact is
[front-half-pool-budget-r1.json](results/2026-08-20-front-half-pool-budget/front-half-pool-budget-r1.json).
The follow-up evidence is in
[market-sequence-and-lettuce-ab-r1.json](results/2026-08-20-market-sequence/market-sequence-and-lettuce-ab-r1.json).
