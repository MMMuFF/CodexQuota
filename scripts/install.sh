#!/bin/zsh

set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
default_archive="${project_dir}/.build/artifacts/CodexQuota.zip"
install_dir="${CODEX_QUOTA_INSTALL_DIR:-/Applications}"
target_app="${install_dir}/CodexQuota.app"
expected_bundle_id="com.mufeng.codexquota"
legacy_app="${HOME}/Applications/CodexQuota.app"
archive_path=""

usage() {
    cat <<'EOF'
用法：
  ./scripts/install.sh
  ./scripts/install.sh --archive /path/to/CodexQuota.zip

默认从当前源码构建后安装。--archive 只安装指定的本地 ZIP，不会联网下载。
默认安装到 /Applications/CodexQuota.app；可用 CODEX_QUOTA_INSTALL_DIR 自定义目录。
EOF
}

if [[ "$#" -eq 0 ]]; then
    "${script_dir}/build-app.sh"
    archive_path="${default_archive}"
elif [[ "$#" -eq 2 && "$1" == "--archive" ]]; then
    archive_path="$2"
else
    usage >&2
    exit 64
fi

if [[ ! -f "${archive_path}" ]]; then
    echo "错误：找不到安装包：${archive_path}" >&2
    exit 66
fi

if /usr/bin/pgrep -x CodexQuota >/dev/null 2>&1; then
    echo "错误：检测到 CodexQuota 正在运行。请退出所有同名副本，再重新安装。" >&2
    exit 75
fi

staging_root="$(mktemp -d /private/tmp/codexquota-install.XXXXXX)"
expanded_root="${staging_root}/expanded"
staged_app="${expanded_root}/CodexQuota.app"
replacement_app="${install_dir}/.CodexQuota.installing.$$"
previous_app="${install_dir}/.CodexQuota.previous.$$"
legacy_previous="${HOME}/Applications/.CodexQuota.previous.$$"
did_move_previous=false
did_move_legacy=false
did_place_replacement=false
installation_committed=false

validate_existing_app() {
    local app_path="$1"
    local app_plist="${app_path}/Contents/Info.plist"
    local app_bundle_id=""

    if [[ ! -d "${app_path}" || -L "${app_path}" || ! -f "${app_plist}" ]]; then
        echo "错误：目标路径不是有效的 CodexQuota 应用：${app_path}" >&2
        return 1
    fi
    if ! app_bundle_id="$(
        /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${app_plist}" 2>/dev/null
    )" || [[ "${app_bundle_id}" != "${expected_bundle_id}" ]]; then
        echo "错误：拒绝替换 Bundle ID 不匹配的同名应用：${app_path}" >&2
        return 1
    fi
}

cleanup() {
    local exit_status="$?"
    trap - EXIT HUP INT TERM

    if [[ "${installation_committed}" != true ]]; then
        if [[ "${did_place_replacement}" == true && -e "${target_app}" ]]; then
            if ! rm -rf "${target_app}"; then
                echo "严重错误：无法移除未完成安装的新应用：${target_app}" >&2
                exit_status=74
            fi
        fi

        if [[ "${did_move_previous}" == true && -e "${previous_app}" ]]; then
            if [[ -e "${target_app}" ]]; then
                echo "严重错误：目标仍存在，旧应用备份保留在：${previous_app}" >&2
                exit_status=74
            elif ! mv "${previous_app}" "${target_app}"; then
                echo "严重错误：无法恢复旧应用，备份仍位于：${previous_app}" >&2
                exit_status=74
            fi
        fi

        if [[ "${did_move_legacy}" == true && -e "${legacy_previous}" ]]; then
            if [[ -e "${legacy_app}" ]]; then
                echo "严重错误：旧路径仍存在，迁移备份保留在：${legacy_previous}" >&2
                exit_status=74
            elif ! mv "${legacy_previous}" "${legacy_app}"; then
                echo "严重错误：无法恢复旧路径应用，备份仍位于：${legacy_previous}" >&2
                exit_status=74
            fi
        fi
    fi

    if ! rm -rf "${replacement_app}" "${staging_root}"; then
        exit_status=74
    fi
    if [[ "${installation_committed}" == true ]]; then
        if [[ "${did_move_previous}" == true && -e "${previous_app}" ]] \
            && ! rm -rf "${previous_app}"; then
            echo "提示：安装成功，但旧版隐藏备份未能清理：${previous_app}" >&2
        fi
        if [[ "${did_move_legacy}" == true && -e "${legacy_previous}" ]] \
            && ! rm -rf "${legacy_previous}"; then
            echo "提示：迁移成功，但旧路径隐藏备份未能清理：${legacy_previous}" >&2
        fi
    fi
    exit "${exit_status}"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p "${expanded_root}"
/usr/bin/ditto -x -k "${archive_path}" "${expanded_root}"

if [[ ! -d "${staged_app}" || -L "${staged_app}" ]]; then
    echo "错误：ZIP 中没有有效的 CodexQuota.app。" >&2
    exit 65
fi

plist="${staged_app}/Contents/Info.plist"
executable="${staged_app}/Contents/MacOS/CodexQuota"
if [[ ! -f "${plist}" || ! -x "${executable}" ]]; then
    echo "错误：应用结构不完整。" >&2
    exit 65
fi

bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${plist}")"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${plist}")"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${plist}")"
if [[ "${bundle_id}" != "${expected_bundle_id}" || -z "${version}" || -z "${build}" ]]; then
    echo "错误：Bundle 信息不符合 CodexQuota 发行约定。" >&2
    exit 65
fi

/usr/bin/codesign --verify --deep --strict --verbose=2 "${staged_app}"

mkdir -p "${install_dir}"
rm -rf "${replacement_app}"
/usr/bin/ditto "${staged_app}" "${replacement_app}"
/usr/bin/codesign --verify --deep --strict --verbose=2 "${replacement_app}"

if [[ -e "${target_app}" ]]; then
    if ! validate_existing_app "${target_app}"; then
        exit 73
    fi

    if [[ "${install_dir}" == "/Applications" && "${legacy_app}" != "${target_app}" \
        && -e "${legacy_app}" ]]; then
        echo "错误：系统与用户应用目录同时存在 CodexQuota；请先移除旧副本后重试。" >&2
        exit 73
    fi

    old_requirement="$(
        /usr/bin/codesign -d -r- "${target_app}" 2>&1 \
            | /usr/bin/sed -n 's/^designated => //p' \
            || true
    )"
    new_requirement="$(
        /usr/bin/codesign -d -r- "${replacement_app}" 2>&1 \
            | /usr/bin/sed -n 's/^designated => //p' \
            || true
    )"
    if [[ -n "${old_requirement}" && -n "${new_requirement}" \
        && "${old_requirement}" != "${new_requirement}" ]]; then
        echo "提示：新旧签名身份不同，macOS 可能要求重新授权“辅助功能”。" >&2
    fi

    if [[ -e "${previous_app}" ]]; then
        echo "错误：旧版安装备份已存在：${previous_app}" >&2
        exit 73
    fi
    mv "${target_app}" "${previous_app}"
    did_move_previous=true
elif [[ "${install_dir}" == "/Applications" && "${legacy_app}" != "${target_app}" \
    && -e "${legacy_app}" ]]; then
    if ! validate_existing_app "${legacy_app}"; then
        exit 73
    fi
    if [[ -e "${legacy_previous}" ]]; then
        echo "错误：旧路径迁移备份已存在：${legacy_previous}" >&2
        exit 73
    fi
    mv "${legacy_app}" "${legacy_previous}"
    did_move_legacy=true
fi

if ! mv "${replacement_app}" "${target_app}"; then
    echo "错误：安装失败；已尝试恢复原应用。" >&2
    exit 74
fi
did_place_replacement=true

if ! /usr/bin/codesign --verify --deep --strict --verbose=2 "${target_app}"; then
    echo "错误：安装后的签名验证失败；已恢复原应用。" >&2
    exit 74
fi
installation_committed=true

echo "已安装 CodexQuota ${version} (${build})：${target_app}"
if [[ "${CODEX_QUOTA_SKIP_OPEN:-0}" != "1" ]]; then
    /usr/bin/open "${target_app}"
fi
