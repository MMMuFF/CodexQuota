#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
test_dir="${project_dir}/.build/manual-app-tests"
target_triple="$(uname -m)-apple-macosx13.0"
mkdir -p "${test_dir}/module-cache"

swiftc -parse-as-library -swift-version 5 \
  -target "${target_triple}" \
  -module-cache-path "${test_dir}/module-cache" \
  -emit-library -emit-module -module-name CodexQuotaCore \
  "${project_dir}"/Sources/CodexQuotaCore/*.swift \
  -emit-module-path "${test_dir}/CodexQuotaCore.swiftmodule" \
  -o "${test_dir}/libCodexQuotaCore.dylib"

swiftc -parse-as-library -swift-version 5 \
  -target "${target_triple}" \
  -module-cache-path "${test_dir}/module-cache" \
  -I "${test_dir}" -L "${test_dir}" -lCodexQuotaCore \
  -Xlinker -rpath -Xlinker "${test_dir}" \
  "${project_dir}/Sources/CodexQuotaApp/QuotaPopoverViewController.swift" \
  "${project_dir}/Sources/CodexQuotaApp/QuotaOverlayPanel.swift" \
  "${project_dir}/Sources/CodexQuotaApp/StatusItemController.swift" \
  "${project_dir}/Sources/CodexQuotaApp/CodexSidebarLocator.swift" \
  "${project_dir}/Sources/CodexQuotaApp/CodexWindowLocator.swift" \
  "${project_dir}"/Tests/CodexQuotaAppTests/*.swift \
  -o "${test_dir}/CodexQuotaAppChecks"

"${test_dir}/CodexQuotaAppChecks"
