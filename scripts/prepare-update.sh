#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
sparkle_tools="${project_dir}/.build/artifacts/sparkle/Sparkle/bin"
signing_account="com.mufeng.codexquota.updates"
plist="${project_dir}/Resources/Info.plist"

"${script_dir}/build-app.sh"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${plist}")"
if [[ ! "${version}" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
    echo "Refusing to prepare a non-stable update version." >&2
    exit 65
fi
public_key="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "${plist}")"
if [[ "$("${sparkle_tools}/generate_keys" --account "${signing_account}" -p)" != "${public_key}" ]]; then
    echo "The local signing key does not match this app. No update was prepared." >&2
    exit 65
fi

release_dir="$(mktemp -d "${project_dir}/.build/artifacts/update-XXXXXX")"
cp "${project_dir}/.build/artifacts/CodexQuota.zip" "${release_dir}/CodexQuota.zip"
cp "${project_dir}/.build/artifacts/CodexQuota.zip.sha256" "${release_dir}/CodexQuota.zip.sha256"
"${sparkle_tools}/generate_appcast" --account "${signing_account}" \
    --download-url-prefix "https://github.com/MMMuFF/CodexQuota/releases/download/v${version}/" \
    --full-release-notes-url "https://github.com/MMMuFF/CodexQuota/releases/tag/v${version}" \
    --link "https://github.com/MMMuFF/CodexQuota" \
    --maximum-deltas 0 "${release_dir}"
"${sparkle_tools}/sign_update" --account "${signing_account}" --verify "${release_dir}/appcast.xml"
echo "Prepared signed update files (not published): ${release_dir}"
