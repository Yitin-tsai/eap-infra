#!/usr/bin/env bash

# Reads the same owner-local contract consumed by the schema-v4 full-chain gate.
# The caller supplies the exact fixed-work allowlist for the service under test.
eap_read_zero_durable_debt_snapshot() {
  local actuator_base="$1"
  local expected_service="$2"
  local expected_work_json="$3"
  local payload
  payload="$(curl -fsS "${actuator_base}/actuator/durableDebt")" || return 1

  jq -e \
    --arg expectedService "${expected_service}" \
    --argjson expectedWork "${expected_work_json}" '
      def non_negative_integer:
        type == "number" and . >= 0 and . == floor;
      .contractVersion == 1
      and .service == $expectedService
      and .observationSuccess == true
      and (.snapshotAgeSeconds | non_negative_integer)
      and .snapshotAgeSeconds <= 15
      and (.observedAt | type) == "string"
      and (try (
        .observedAt
        | sub("\\.[0-9]+Z$"; "Z")
        | fromdateiso8601
        | type == "number") catch false)
      and (.components | type) == "array"
      and ([.components[].work] | length) == ([.components[].work] | unique | length)
      and ([.components[].work] | sort) == ($expectedWork | sort)
      and all(.components[];
        (.totalCount | non_negative_integer) and .totalCount == 0
        and (.retryCount | non_negative_integer) and .retryCount == 0
        and (.terminalCount | non_negative_integer) and .terminalCount == 0
        and (.oldestUnresolvedAgeSeconds | non_negative_integer)
        and .oldestUnresolvedAgeSeconds == 0)
    ' <<<"${payload}" >/dev/null || return 1

  jq -c '{
    contractVersion,
    service,
    observedAt,
    observationSuccess,
    snapshotAgeSeconds,
    components: (.components | map({
      key: .work,
      value: {
        totalCount,
        retryCount,
        terminalCount,
        oldestUnresolvedAgeSeconds
      }
    }) | from_entries)
  }' <<<"${payload}"
}

eap_wait_for_zero_durable_debt_snapshot() {
  local actuator_base="$1"
  local expected_service="$2"
  local expected_work_json="$3"
  local timeout_seconds="$4"
  local deadline=$(( $(date +%s) + timeout_seconds ))
  local snapshot
  while [[ $(date +%s) -lt ${deadline} ]]; do
    if snapshot="$(eap_read_zero_durable_debt_snapshot \
        "${actuator_base}" "${expected_service}" "${expected_work_json}" 2>/dev/null)"; then
      printf '%s\n' "${snapshot}"
      return 0
    fi
    sleep 1
  done
  echo "[ERROR] ${expected_service} durable-debt snapshot did not become fresh, exact, and zero" >&2
  return 1
}
