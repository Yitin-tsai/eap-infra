#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/docker-compose.loadtest.yml"

resolved_project="$(
  COMPOSE_PROJECT_NAME=eap-workspace \
    docker compose -p eap-loadtest -f "${COMPOSE_FILE}" config --format json \
    | jq -r '.name'
)"

if [[ "${resolved_project}" != "eap-loadtest" ]]; then
  echo "expected load-test compose project eap-loadtest, got ${resolved_project}" >&2
  exit 1
fi

compose_without_explicit_project='docker compose '"-f"
if rg -n -F "${compose_without_explicit_project}" "${ROOT_DIR}/scripts/load-test" --glob '*.sh'; then
  echo "load-test script contains docker compose without an explicit -p project" >&2
  exit 1
fi

echo "load-test compose project isolation test passed"
