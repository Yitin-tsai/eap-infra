#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

repo_json() {
  local name="$1"
  local path="$2"
  local abs_path="${ROOT_DIR}/${path}"
  if [[ ! -d "${abs_path}/.git" && "${path}" != "." ]]; then
    jq -n --arg name "${name}" --arg path "${path}" '{name: $name, path: $path, present: false}'
    return
  fi

  local commit
  local branch
  local tracked_dirty_count
  local untracked_count
  commit="$(git -C "${abs_path}" rev-parse HEAD)"
  branch="$(git -C "${abs_path}" branch --show-current || true)"
  tracked_dirty_count="$(git -C "${abs_path}" status --porcelain --untracked-files=no | wc -l | tr -d ' ')"
  untracked_count="$(git -C "${abs_path}" ls-files --others --exclude-standard | wc -l | tr -d ' ')"

  jq -n \
    --arg name "${name}" \
    --arg path "${path}" \
    --arg commit "${commit}" \
    --arg branch "${branch}" \
    --argjson trackedDirtyCount "${tracked_dirty_count}" \
    --argjson untrackedCount "${untracked_count}" \
    '{
      name: $name,
      path: $path,
      present: true,
      branch: $branch,
      commit: $commit,
      dirty: ($trackedDirtyCount > 0),
      trackedDirtyCount: $trackedDirtyCount,
      untrackedCount: $untrackedCount
    }'
}

image_json() {
  local name="$1"
  local pinned_ref="$2"
  local inspect_ref="$3"
  local inspect
  if ! inspect="$(docker image inspect "${inspect_ref}" 2>/dev/null)"; then
    jq -n \
      --arg name "${name}" \
      --arg pinnedRef "${pinned_ref}" \
      --arg inspectRef "${inspect_ref}" \
      '{name: $name, pinnedRef: $pinnedRef, inspectRef: $inspectRef, present: false}'
    return
  fi

  if [[ "$(jq 'length' <<<"${inspect}")" == "0" ]]; then
    jq -n \
      --arg name "${name}" \
      --arg pinnedRef "${pinned_ref}" \
      --arg inspectRef "${inspect_ref}" \
      '{name: $name, pinnedRef: $pinnedRef, inspectRef: $inspectRef, present: false}'
    return
  fi

  jq -n \
    --arg name "${name}" \
    --arg pinnedRef "${pinned_ref}" \
    --arg inspectRef "${inspect_ref}" \
    --argjson inspect "${inspect}" \
    '{
      name: $name,
      pinnedRef: $pinnedRef,
      inspectRef: $inspectRef,
      present: true,
      id: $inspect[0].Id,
      repoDigests: ($inspect[0].RepoDigests // [])
    }'
}

repos_json="$(
  jq -s '.' < <(
    repo_json "infra" "."
    repo_json "order" "eap-order"
    repo_json "wallet" "eap-wallet"
    repo_json "matchEngine" "eap-matchEngine"
    repo_json "common" "eap-common"
  )
)"

images_json="$(
  jq -s '.' < <(
    image_json "postgres" "postgres@sha256:f565573d74aedc9b218e1d191b04ec75bdd50c33b2d44d91bcd3db5f2fcea647" "postgres:14.6"
    image_json "rabbitmq" "rabbitmq@sha256:606d8c0d6b3c18d1da9afc53bc7cdb2a8d5486df91b5a9830e9e07626c9ae281" "rabbitmq:3-management-alpine"
    image_json "redis" "redis@sha256:6ab0b6e7381779332f97b8ca76193e45b0756f38d4c0dcda72dbb3c32061ab99" "redis:7-alpine"
  )
)"

jq -n \
  --arg generatedAtUtc "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg rootDir "${ROOT_DIR}" \
  --argjson repos "${repos_json}" \
  --argjson images "${images_json}" \
  '{
    generatedAtUtc: $generatedAtUtc,
    rootDir: $rootDir,
    repos: $repos,
    images: $images,
    clean: (([$repos[].dirty] | any) | not),
    hasUntrackedFiles: (([$repos[].untrackedCount] | add) > 0)
  }'
