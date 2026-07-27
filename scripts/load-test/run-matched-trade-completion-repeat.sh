#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

if (( $# > 1 )); then
  echo "usage: $0 [RUN_PREFIX]" >&2
  exit 2
fi

RUN_PREFIX="${1:-GLT_$(date +%Y%m%d)_MATCHED_TRADE_COMPLETION_REPEAT}"

bash "${ROOT_DIR}/scripts/load-test/run-2000-ticket-marker-repeat.sh" "${RUN_PREFIX}"
