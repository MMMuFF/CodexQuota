# 安全说明

## 支持范围

当前仅维护 `main` 分支的最新版本。CodexQuota 是本机伴生工具，不提供云端服务。

## 报告问题

请勿在公开 Issue 中粘贴以下内容：

- `~/.codex/auth.json`
- Access Token、JWT、Cookie 或请求头
- macOS 钥匙串内容
- 含邮箱、账户 ID 或私人任务内容的完整日志与截图

请通过 GitHub 的
[Private Vulnerability Reporting](https://github.com/MMMuFF/CodexQuota/security/advisories/new)
私下报告。不要为安全漏洞创建包含细节的公开 Issue。

## 数据边界

- 应用不会修改、注入或重新签名 `/Applications/ChatGPT.app`。
- 额度数据优先通过本机 Codex `app-server` 读取。
- 会员日期仅从本机登录态解码，不上传给第三方。
- 重置券详情的 HTTPS 请求仅发往 `chatgpt.com`，且拒绝 HTTP 重定向。
- 不包含遥测、广告、统计或后台数据收集。
- 使用重置券是不可逆操作，必须由用户在详情卡中二次确认。
