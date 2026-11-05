#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
source "${ROOT_DIR}/scripts/load-test/http-matched-loadtest-lib.sh"
fixture="$(mktemp -d "${TMPDIR:-/tmp}/eap-fingerprint-test.XXXXXX")"
git -C "${fixture}" init -q
git -C "${fixture}" -c user.name=Fixture -c user.email=fixture@example.invalid commit --allow-empty -qm fixture
printf 'first\n' > "${fixture}/中文 空白.txt"
before="$(http_matched_worktree_sha256 "${fixture}")"
printf 'second\n' > "${fixture}/中文 空白.txt"
after="$(http_matched_worktree_sha256 "${fixture}")"
if [[ "${before}" == "${after}" ]]; then
  echo 'FAIL: changed non-ASCII untracked content did not change fingerprint' >&2
  exit 1
fi
if [[ "${after}" != "$(http_matched_worktree_sha256 "${fixture}")" ]]; then
  echo 'FAIL: unchanged content produced an unstable fingerprint' >&2
  exit 1
fi
echo 'PASS: non-ASCII/spaced untracked filenames are hashed and changes are detected'
