# Codex 昵称额度（CodexQuota）

一个开源的 macOS 伴生应用：在 Codex Desktop 左侧栏底部、用户昵称右侧显示额度，不占用菜单栏，也不修改 Codex 安装包。

<p align="center">
  <a href="https://github.com/MMMuFF/CodexQuota/releases/latest"><strong>下载最新版</strong></a>
  · <a href="#安装">安装说明</a>
  · <a href="#如何读懂进度">如何读懂进度</a>
</p>

<p align="center">
  <img
    src="./docs/images/codex-quota-sidebar.png"
    alt="Codex 左侧栏昵称旁显示额度剩余百分比、刷新日期和剩余天数"
    width="620">
</p>
<p align="center"><sub>昵称旁常显：剩余额度 · 刷新日期 · 剩余天数（演示数据）</sub></p>

鼠标悬停后可查看时间/额度进度、预计耗尽时间、会员到期时间、额度刷新时间和最早到期重置券，并可手动刷新或在二次确认后使用一张重置券。

<p align="center">
  <img
    src="./docs/images/codex-quota-popover.png"
    alt="Codex 额度详情卡显示会员到期、额度刷新时间和最早到期重置券"
    width="620">
</p>
<p align="center"><sub>详情卡位置与基础信息示意；当前版本另含时间/额度进度与预计耗尽时间（演示数据）</sub></p>

> [!IMPORTANT]
> Release ZIP，以及未指定 `CODE_SIGN_IDENTITY` 的本地构建，默认使用 ad-hoc 签名，没有 Developer ID 公证。请仅从本仓库 Release 下载，或检查源码后自行构建；更换或重新构建应用后，macOS 可能要求重新授权辅助功能。

## 功能

- 显示当前额度剩余百分比、刷新日期/具体时间和剩余天数
- 对比本周期时间进度与额度消耗进度，并按当前周期均速显示预计耗尽时间
- 常显额度下方用中性、橙色或红色细线提示额度消耗相对时间进度的偏差
- 根据当前会员类型显示 Plus、Pro 等会员到期时间
- 续费后优先读取当前账户的实时订阅日期，不再沿用旧 Token 日期
- 显示最早到期重置券及可用数量
- 额度每 5 分钟刷新，也可在详情卡中手动刷新
- 跟随 Codex 侧边栏移动、缩放和收起
- 设置页、侧边栏收起、窗口最小化或 Codex 不在前台时自动隐藏
- 切换账户后按账户重新读取，并隔离重置券幂等请求
- 使用独立设计的额度仪表环应用图标
- 不占用 Dock、菜单栏或普通主窗口

## 系统要求

- macOS 13 或更高版本
- Codex Desktop 已安装到 `/Applications/ChatGPT.app`
- 已在 Codex 中登录 ChatGPT 账户
- 下载 Release ZIP：需要 Apple Silicon（M 系列）Mac
- 从源码构建：另需 Xcode Command Line Tools 与 Swift 5.9+；Intel Mac 请使用此方式

## 安装

### 下载 Release（推荐）

1. 在 Apple Silicon（M 系列）Mac 上，从 [最新 Release](https://github.com/MMMuFF/CodexQuota/releases/latest) 下载 `CodexQuota.zip`。
2. 解压后将 `CodexQuota.app` 拖入 macOS 的“应用程序”文件夹。
3. 首次打开若 macOS 无法验证开发者，请在确认下载来源后按住 Control 键点按应用，选择“打开”，再按系统提示确认。

Release ZIP 使用 ad-hoc 签名且未经 Apple 公证。它会在打开前经过 macOS Gatekeeper 检查，但不能提供已验证开发者身份；如需完整审查，可按下方步骤从源码构建。

### 从源码安装

先检查开发工具：

```bash
xcode-select -p
swift --version
```

如果第一条命令失败，可运行 `xcode-select --install`，按 macOS 提示完成安装。

```bash
git clone https://github.com/MMMuFF/CodexQuota.git
cd CodexQuota
./scripts/install.sh
```

安装脚本会：

1. 从当前源码构建 `.build/artifacts/CodexQuota.zip`
2. 校验 Bundle ID、版本和代码签名完整性
3. 安装到 `/Applications/CodexQuota.app`
4. 从固定路径启动应用

脚本不使用 `sudo`、不联网下载依赖、不主动清除 Gatekeeper 隔离属性，也不会修改 `/Applications/ChatGPT.app`。如果任意 CodexQuota 副本仍在运行，脚本会拒绝覆盖；请先全部退出。

从旧版的 `~/Applications/CodexQuota.app` 更新时，若系统“应用程序”目录还没有同名 App，安装器会先校验 Bundle ID，再以可回滚方式迁移。若两个目录已经同时存在副本，安装器会停止并请你先确认要保留哪一个，避免误删或覆盖其他同名应用。

非管理员账户若无权写入 `/Applications`，可改装到个人应用目录：

```bash
CODEX_QUOTA_INSTALL_DIR="$HOME/Applications" ./scripts/install.sh
```

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

1. 打开 `/Applications/CodexQuota.app`。
2. 打开 Codex 的普通任务页，并展开左侧栏。
3. 首次出现提示时，前往「系统设置 → 隐私与安全性 → 辅助功能」，允许“Codex 昵称额度”或 `CodexQuota`。
4. 回到 Codex；昵称右侧会显示额度，悬停即可打开详情卡。

如果昵称旁显示橙色“请开启辅助功能”，点击该提示可直接打开对应的系统设置页面；授权后应用会自动恢复额度显示。

辅助功能权限只用于读取 Codex 窗口、任务侧边栏和分隔线的几何结构，以保持额度位置正确。应用不需要屏幕录制、输入监控或完全磁盘访问，不监听全局键盘或鼠标；仅处理自身额度组件与详情卡上的悬停和点击。

应用使用 `LSUIElement` 运行，因此没有 Dock 图标、菜单栏图标或普通主窗口。退出后需要从 `/Applications/CodexQuota.app` 重新启动。

首次启动会请求通过 macOS `SMAppService` 注册登录启动。若系统要求批准，可在「系统设置 → 通用 → 登录项」中开启“Codex 昵称额度”。手动退出或崩溃后不会立刻自动拉起，只会在下次登录时启动。

## 如何读懂进度

昵称旁常显内容例如 `86% · 8月4日 · 7天`：

| 内容 | 含义 |
| --- | --- |
| `86%` | 当前剩余额度 |
| `8月4日` | 当前额度周期的刷新日期 |
| `7天` | 距离刷新剩余的天数 |

悬停后，详情卡会用同一个额度周期比较两条“已发生”进度：

- **时间**：本周期截至最近一次刷新数据时，已经过去的比例。
- **额度**：本周期已经消耗的比例，即 `100% - 剩余额度`。例如常显 `86%` 时，额度进度约为 `14%`。
- 多个额度窗口同时存在时，应用动态选择 Codex 返回的最长周期，不固定写死为 5 小时或 7 天。
- “预计用完”按本周期开始至最近一次刷新时的平均消耗速度线性估算，仅供参考；预计晚于重置时间时显示“本轮预计用不完”，尚未消耗或周期数据不完整时显示“暂无法估算”。

常显文字下方的细线表示“额度已用进度 − 时间已过进度”的绝对偏差：

| 绝对偏差 | 细线颜色 |
| --- | --- |
| 不超过 25 个百分点 | 中性色 |
| 大于 25、但不超过 50 个百分点 | 橙色 |
| 大于 50 个百分点 | 红色 |

正偏差表示额度消耗比时间进度快，负偏差表示更慢。细线颜色只表示偏差程度；方向请悬停后对比两条进度。悬停、详情卡展开、需要显示辅助功能警告或周期数据不可比较时，细线会隐藏。

详情卡还会显示当前套餐对应的 Plus、Pro、Team、Business 或 Enterprise 到期信息，以及所有可用重置券中最早到期的一张。“暂无”表示已确认当前为 0 张；“暂不可用”表示本次未能读取，不能理解为 0 张。数量可用但到期时间缺失时，应用会保留可用数量并明确提示到期时间暂不可用。

## 显示规则与操作

额度仅在以下条件同时满足时显示：

- Codex 位于前台
- 普通任务页处于打开状态
- Codex 主窗口可见
- 左侧栏已展开

进入设置页、收起侧边栏、最小化窗口、切换到其他应用，或当前 Space 没有前台可见的 Codex 普通任务窗口时隐藏，属于预期行为。

应用约每 5 分钟自动读取一次，也可以在详情卡中点击“刷新”。切换账户后建议手动刷新；若刷新失败但已有缓存，界面会继续显示上一次结果并给出提示。

“使用重置券”是不可逆操作，应用会显示二次确认；发送消费请求前会重新校验稳定账户 ID，不一致或无法读取时取消操作。

## 更新

### Release ZIP 用户

1. 在详情卡中点击“退出…”。
2. 从 [最新 Release](https://github.com/MMMuFF/CodexQuota/releases/latest) 下载并解压新的 `CodexQuota.zip`。
3. 用新版本替换 `/Applications/CodexQuota.app`，然后重新打开。
4. 如果额度不再显示，请在“辅助功能”设置中移除旧条目并重新授权稳定安装路径下的应用。

### 源码安装用户

先在详情卡中点击“退出…”，再运行：

```bash
cd /path/to/CodexQuota
git pull
./scripts/install.sh
```

请把 `/path/to/CodexQuota` 替换为首次克隆时的仓库目录。只在 `/Applications/CodexQuota.app` 保留一个稳定副本。不要从下载目录、临时解压目录或旧构建目录长期运行，否则 macOS 辅助功能授权和 Spotlight 可能指向不同副本。

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
codesign --verify --deep --strict "/Applications/CodexQuota.app"
```

### 已授权辅助功能但仍不显示

检查是否授权了下载目录或旧解压目录中的同名副本。退出应用，在辅助功能列表中移除旧条目，只保留 `/Applications/CodexQuota.app`，重新添加后再启动。

ad-hoc 重新构建会改变代码签名。如果旧授权失效，请退出应用、移除旧权限条目、重新添加稳定安装路径，再启动。

### 显示“读取失败”

确认 Codex 已登录、固定 `codex` 路径存在且网络/VPN 可访问 ChatGPT，然后在详情卡中点击“刷新”。

### 出现多个同名应用

只保留 `/Applications/CodexQuota.app`。删除下载目录和旧构建目录中手动解压的 `.app`，不要修改 Spotlight 数据库。仓库内的 `.build` 可以用 SwiftPM 常规清理命令重新生成。

### 错位、拖动后消失或悬停无响应

先退出并从稳定路径重开。若仍可复现，请在 Issue 中提供脱敏截图、macOS/Codex/CodexQuota 版本，以及是否使用副屏、设置页或临时对话框。

## 数据与隐私

- 额度百分比和刷新时间优先由本机 `codex app-server` 读取。
- 会员到期时间优先使用当前账户的本机登录态，从 `https://chatgpt.com/backend-api/subscriptions` 发出只读 HTTPS GET；失败时才回退 `~/.codex/auth.json` 中同账号 Token 的订阅日期。
- 实时订阅日期和套餐类型按同一账户原子更新；请求前后若检测到账户变化，会丢弃本次结果。插件不会自行推算续费日期。
- 订阅与重置券详情请求都只发往 `https://chatgpt.com`，使用无 Cookie、无缓存的临时会话，并拒绝重定向。
- Token 不写入日志、不进入 UI 状态、不持久化到项目，也不会发送给第三方。
- 不包含遥测、广告、统计或追踪。
- 重置券消费使用按账户和时间隔离的幂等请求 ID，降低网络结果不明时重复消费风险。

CodexQuota 不是 OpenAI 官方产品，与 OpenAI 无隶属或背书关系。应用依赖 Codex 本机协议和 ChatGPT 的非公开接口；上游更新可能导致部分功能暂时不可用。

## 卸载

1. 在详情卡中点击“退出…”。
2. 在「系统设置 → 通用 → 登录项」中关闭“Codex 昵称额度”。
3. 在「系统设置 → 隐私与安全性 → 辅助功能」中移除对应权限。
4. 将 `/Applications/CodexQuota.app` 移到废纸篓。

如需同时清除本机偏好，可在确认没有结果不明的重置券请求后运行：

```bash
defaults delete com.mufeng.codexquota
```

应用从未修改 `/Applications/ChatGPT.app`，因此无需修复或重装 Codex。

## 许可证

[MIT](LICENSE)
