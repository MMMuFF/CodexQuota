# Codex 昵称额度（CodexQuota）

一个开源的 macOS 伴生应用：在 Codex Desktop 左侧栏底部、用户昵称右侧显示额度，不占用菜单栏，也不修改 Codex 安装包。

```text
34% · 7月25日 · 4天
```

鼠标悬停后可查看会员到期时间、额度刷新时间和最早到期重置券，并可手动刷新或在二次确认后使用一张重置券。

> [!IMPORTANT]
> 当前提供的是源码本地构建方式，没有 Developer ID 公证安装器。默认产物使用 ad-hoc 签名，适合自行检查源码后在本机使用；重新构建后，macOS 可能要求重新授权辅助功能。

## 功能

- 显示当前额度剩余百分比、刷新日期/具体时间和剩余天数
- 根据当前会员类型显示 Plus、Pro 等会员到期时间
- 显示最早到期重置券及可用数量
- 额度每 5 分钟刷新，也可在详情卡中手动刷新
- 跟随 Codex 侧边栏移动、缩放和收起
- 设置页、侧边栏收起、窗口最小化或 Codex 不在前台时自动隐藏
- 切换账户后按账户重新读取，并隔离重置券幂等请求
- 不占用 Dock、菜单栏或普通主窗口

## 系统要求

- macOS 13 或更高版本
- Xcode Command Line Tools 与 Swift 5.9+
- Codex Desktop 已安装到 `/Applications/ChatGPT.app`
- 已在 Codex 中登录 ChatGPT 账户

检查开发工具：

```bash
xcode-select -p
swift --version
```

如果第一条命令失败，可运行 `xcode-select --install`，按 macOS 提示完成安装。

## 安装

```bash
git clone https://github.com/MMMuFF/CodexQuota.git
cd CodexQuota
./scripts/install.sh
```

安装脚本会：

1. 从当前源码构建 `.build/artifacts/CodexQuota.zip`
2. 校验 Bundle ID、版本和代码签名完整性
3. 安装到 `~/Applications/CodexQuota.app`
4. 从固定路径启动应用

脚本不使用 `sudo`、不联网下载依赖、不主动清除 Gatekeeper 隔离属性，也不会修改 `/Applications/ChatGPT.app`。如果任意 CodexQuota 副本仍在运行，脚本会拒绝覆盖；请先全部退出。

代码签名检查用于确认应用在复制过程中没有损坏，不验证发布者身份，也不代表应用经过 Apple 公证。

也可以只构建，不安装：

```bash
./scripts/build-app.sh
```

本机如有签名证书，可指定签名身份：

```bash
CODE_SIGN_IDENTITY="Apple Development: Your Name" ./scripts/install.sh
```

Apple Development 证书适合同机开发测试，不等于面向公众分发所需的 Developer ID、Hardened Runtime 与公证流程。

## 首次使用

1. 打开 `~/Applications/CodexQuota.app`。
2. 打开 Codex 的普通任务页，并展开左侧栏。
3. 首次出现提示时，前往「系统设置 → 隐私与安全性 → 辅助功能」，允许“Codex 昵称额度”或 `CodexQuota`。
4. 回到 Codex；昵称右侧会显示额度，悬停即可打开详情卡。

辅助功能权限只用于读取 Codex 窗口、任务侧边栏和分隔线的几何结构，以保持额度位置正确。应用不需要屏幕录制、输入监控或完全磁盘访问，不监听全局键盘或鼠标；仅处理自身额度组件与详情卡上的悬停和点击。

应用使用 `LSUIElement` 运行，因此没有 Dock 图标、菜单栏图标或普通主窗口。退出后需要从 `~/Applications/CodexQuota.app` 重新启动。

首次启动会请求通过 macOS `SMAppService` 注册登录启动。若系统要求批准，可在「系统设置 → 通用 → 登录项」中开启“Codex 昵称额度”。手动退出或崩溃后不会立刻自动拉起，只会在下次登录时启动。

## 显示规则与操作

额度仅在以下条件同时满足时显示：

- Codex 位于前台
- 普通任务页处于打开状态
- Codex 主窗口可见
- 左侧栏已展开

进入设置页、收起侧边栏、最小化窗口、切换到其他应用，或当前 Space 没有前台可见的 Codex 普通任务窗口时隐藏，属于预期行为。

切换账户后，建议悬停额度并点击“刷新”。“使用重置券”是不可逆操作，应用会显示二次确认；发送消费请求前会重新校验稳定账户 ID，不一致或无法读取时取消操作。

## 更新

先在详情卡中点击“退出…”，再运行：

```bash
cd /path/to/CodexQuota
git pull
./scripts/install.sh
```

请把 `/path/to/CodexQuota` 替换为首次克隆时的仓库目录。只在 `~/Applications/CodexQuota.app` 保留一个稳定副本。不要从下载目录、临时解压目录或旧构建目录长期运行，否则 macOS 辅助功能授权和 Spotlight 可能指向不同副本。

## 验证与开发

运行核心逻辑检查：

```bash
./scripts/run-tests.sh
```

当前检查覆盖额度解析、日期格式、账户隔离、重置券安全策略和窗口定位几何；不覆盖真实辅助功能授权、TCC、Gatekeeper、Space 切换及完整 AppKit 交互。

源码没有第三方 SwiftPM 依赖。关键目录：

```text
Sources/CodexQuotaCore/   数据解析与安全策略
Sources/CodexQuotaApp/    AppKit 覆盖层与交互
Tests/                    零第三方依赖测试入口
scripts/                  构建、安装与检查脚本
```

开发调试时如需测试另一份 Codex 可执行文件，可显式设置 `CODEX_QUOTA_CODEX_PATH`。正式使用默认只信任 `/Applications/ChatGPT.app/Contents/Resources/codex`，不会执行 `PATH` 中任意同名程序。

## 故障排查

### 完全不显示

先确认 Codex 在普通任务页、侧边栏已展开且窗口位于前台，然后运行：

```bash
test -x /Applications/ChatGPT.app/Contents/Resources/codex
pgrep -fl CodexQuota
codesign --verify --deep --strict "$HOME/Applications/CodexQuota.app"
```

### 已授权辅助功能但仍不显示

检查是否授权了下载目录或旧解压目录中的同名副本。退出应用，在辅助功能列表中移除旧条目，只保留 `~/Applications/CodexQuota.app`，重新添加后再启动。

ad-hoc 重新构建会改变代码签名。如果旧授权失效，请退出应用、移除旧权限条目、重新添加稳定安装路径，再启动。

### 显示“读取失败”

确认 Codex 已登录、固定 `codex` 路径存在且网络/VPN 可访问 ChatGPT，然后在详情卡中点击“刷新”。

### 出现多个同名应用

只保留 `~/Applications/CodexQuota.app`。删除下载目录和旧构建目录中手动解压的 `.app`，不要修改 Spotlight 数据库。仓库内的 `.build` 可以用 SwiftPM 常规清理命令重新生成。

### 错位、拖动后消失或悬停无响应

先退出并从稳定路径重开。若仍可复现，请在 Issue 中提供脱敏截图、macOS/Codex/CodexQuota 版本，以及是否使用副屏、设置页或临时对话框。

## 数据与隐私

- 额度百分比和刷新时间优先由本机 `codex app-server` 读取。
- 会员到期时间仅在本机解码 `~/.codex/auth.json` 的订阅日期字段。
- 重置券详情使用同一份本机登录态，仅向 `https://chatgpt.com` 发出 HTTPS 请求，并拒绝重定向。
- Token 不写入日志、不进入 UI 状态、不持久化到项目，也不会发送给第三方。
- 不包含遥测、广告、统计或追踪。
- 重置券消费使用按账户和时间隔离的幂等请求 ID，降低网络结果不明时重复消费风险。

CodexQuota 不是 OpenAI 官方产品，与 OpenAI 无隶属或背书关系。应用依赖 Codex 本机协议和 ChatGPT 的非公开接口；上游更新可能导致部分功能暂时不可用。

## 卸载

1. 在详情卡中点击“退出…”。
2. 在「系统设置 → 通用 → 登录项」中关闭“Codex 昵称额度”。
3. 在「系统设置 → 隐私与安全性 → 辅助功能」中移除对应权限。
4. 将 `~/Applications/CodexQuota.app` 移到废纸篓。

如需同时清除本机偏好，可在确认没有结果不明的重置券请求后运行：

```bash
defaults delete com.mufeng.codexquota
```

应用从未修改 `/Applications/ChatGPT.app`，因此无需修复或重装 Codex。

## 许可证

[MIT](LICENSE)
