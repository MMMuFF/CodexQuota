#!/bin/zsh

set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
output_archive="${project_dir}/.build/artifacts/CodexQuota.zip"
legacy_output_app_dir="${project_dir}/.build/artifacts/CodexQuota.app"
staging_root="$(mktemp -d /private/tmp/codexquota-build.XXXXXX)"
app_dir="${staging_root}/CodexQuota.app"
verification_dir="${staging_root}/verification"
contents_dir="${app_dir}/Contents"
macos_dir="${contents_dir}/MacOS"
swiftpm_state_dir="${project_dir}/.build/swiftpm-state"
module_cache_dir="${swiftpm_state_dir}/module-cache"
signing_identity="${CODE_SIGN_IDENTITY:--}"

trap 'rm -rf "${staging_root}"' EXIT

cd "${project_dir}"

mkdir -p \
  "${swiftpm_state_dir}/cache" \
  "${swiftpm_state_dir}/config" \
  "${swiftpm_state_dir}/security" \
  "${module_cache_dir}"

export CLANG_MODULE_CACHE_PATH="${module_cache_dir}"
export SWIFTPM_MODULECACHE_OVERRIDE="${module_cache_dir}"

swift build \
  --build-system native \
  --cache-path "${swiftpm_state_dir}/cache" \
  --config-path "${swiftpm_state_dir}/config" \
  --security-path "${swiftpm_state_dir}/security" \
  -c release \
  --product CodexQuota

mkdir -p "${macos_dir}"
cp -f "${project_dir}/.build/release/CodexQuota" "${macos_dir}/CodexQuota"
cp -f "${project_dir}/Resources/Info.plist" "${contents_dir}/Info.plist"

/usr/bin/xattr -cr "${app_dir}"
/usr/bin/codesign --force --deep --sign "${signing_identity}" "${app_dir}"
/usr/bin/codesign --verify --deep --strict "${app_dir}"

rm -rf "${legacy_output_app_dir}"
rm -f "${output_archive}"
mkdir -p "${output_archive:h}" "${verification_dir}"
COPYFILE_DISABLE=1 /usr/bin/ditto \
  -c -k --norsrc --keepParent \
  "${app_dir}" \
  "${output_archive}"
/usr/bin/ditto -x -k "${output_archive}" "${verification_dir}"
/usr/bin/codesign --verify --deep --strict "${verification_dir}/CodexQuota.app"

if [[ "${signing_identity}" == "-" ]]; then
  echo "Warning: ad-hoc signature; rebuilding may require Accessibility permission again." >&2
fi

echo "Built ${output_archive}"
