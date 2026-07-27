#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

echo "[WARN] run-2000-ticket-marker-10k.sh is a legacy alias; use run-matched-trade-completion-10k.sh." >&2
bash "${ROOT_DIR}/scripts/load-test/run-matched-trade-completion-10k.sh" "$@"
