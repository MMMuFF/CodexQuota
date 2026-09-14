# 签名自动更新 / Signed automatic updates

CodexQuota uses Sparkle 2.10.0 (MIT with bundled third-party notices). Both the feed and archive must be signed; the archive is verified before extraction. The updater uses:

`https://github.com/MMMuFF/CodexQuota/releases/latest/download/appcast.xml`

## 发布 / Publishing

1. Increase `CFBundleVersion` for every distributed build; never reuse a build number with different bytes. Update the bilingual release notes.
2. Run tests, then `zsh scripts/prepare-update.sh`. This builds a ZIP and generates a signed `appcast.xml` in a newly created `.build/artifacts/update-*` directory. It does not publish or install anything.
3. Verify that the generated feed contains the intended version, build, macOS/architecture requirements, signature, and fixed version-specific GitHub download URL. Test the update from an older updater-enabled app in an isolated environment before publishing.
4. Attach **both** `CodexQuota.zip` and `appcast.xml` from that same output directory to the matching GitHub tag (`v<CFBundleShortVersionString>`). Publish only a stable, non-draft Release and mark it latest. Do not upload a prerelease feed as latest.
5. Download the published files again; verify their bytes and signature. Only then claim online updating is available. Do not edit the signed XML or rebuild/replace its ZIP afterwards.

每次发布递增构建号，运行 `zsh scripts/prepare-update.sh`，将同一输出目录的 ZIP 和签名 XML 一起上传至对应正式 Release。脚本本身不会上传、发布或安装。发布后必须回读下载文件，不能只看本地成功。

## 密钥 / Signing key

The signing private key is stored only in the macOS login Keychain under Sparkle account `com.mufeng.codexquota.updates`. The app embeds only the public key in `SUPublicEDKey`. The preparation script verifies the local key matches the embedded public key and fails closed if it does not. It never exports or logs a private key.

私钥只在本机钥匙串。不要将私钥写进代码、日志、文档或 GitHub。请通过安全的钥匙串备份流程保管密钥；丢失密钥会中断旧版本的更新信任链，不可简单生成新密钥继续发布。其他贡献者可构建，但没有发行密钥就不能签发本项目的自动更新。

## 行为与边界 / Behavior and limits

- Checks/downloads are enabled by default, normally once per day. Users can disable them or check manually from More. No system profiling or Codex credentials are sent to GitHub.
- Automatic installation waits for the detail card to close and for refresh/credit operations to finish. A termination guard also protects in-flight credit use. Sparkle handles version comparison, compatible-update selection, signature verification, replacement and relaunch.
- An update already staged by Sparkle can finish when the app quits. Turning the preference off stops future automatic checks/downloads and our immediate-install request, not necessarily an already committed installation.
- Offline, bad-signature or missing-feed failures do not stop quota functionality. Manual checks provide Sparkle error feedback.
- The first updater-enabled build needs manual installation. Until a signed feed is published, the GitHub endpoint is unavailable; this is not a successful update check.
- Ad-hoc signing is not Developer ID signing/notarization. Updating may require Accessibility reauthorization. Do not reset TCC, disable Gatekeeper or patch Codex to hide this limitation.

首次仍需手动安装。自动更新不绕过系统权限；辅助功能授权是否保持需要真实机器验收。测试窗口渲染、构建签名与清单签名通过，不等于已验证线上替换和重启。
