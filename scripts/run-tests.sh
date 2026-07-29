#!/bin/zsh

set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
test_dir="${project_dir}/.build/manual-tests"
test_binary="${test_dir}/CodexQuotaCoreChecks"

mkdir -p "${test_dir}/module-cache"

swiftc \
  -parse-as-library \
  -swift-version 5 \
  -module-cache-path "${test_dir}/module-cache" \
  "${project_dir}"/Sources/CodexQuotaCore/*.swift \
  "${project_dir}"/Tests/CodexQuotaCoreTests/*.swift \
  -o "${test_binary}"

"${test_binary}"
