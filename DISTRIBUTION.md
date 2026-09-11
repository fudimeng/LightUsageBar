# LightUsageBar 0.1.0 测试分发

支持 macOS 14+，包含 Apple Silicon 和 Intel 两种架构。

解压 ZIP，将 LightUsageBar.app 拖到“应用程序”，双击后在菜单栏查看。
上排为 5 小时剩余额度，下排为周剩余额度；未提供的额度显示 —。

本版本使用临时签名，未经 Apple 公证。从网络下载后 macOS 可能阻止打开。
确认来源可信后，可在“系统设置 → 隐私与安全性”中选择“仍要打开”。
如果没有该选项或设备策略不允许，请等待 Developer ID 签名并公证的版本。

Codex 需要本机已登录的 Codex CLI，目前从 /opt/homebrew/bin、/usr/local/bin
及系统 PATH 目录查找。Claude 需要 Claude Code 已有的有效 Keychain 登录凭据；
首次启动可能请求访问 Keychain。遇到登录过期，请打开 Claude Code 或执行 /login 后刷新。
应用只查询额度，不包含提供者账户或令牌；安装者使用自己的账户。

构建分发包：在工程目录运行 `zsh scripts/package-distribution.sh`。
产物在 dist/，含 ZIP 和 SHA-256 校验文件。
公开正式发布前需配置 Developer ID Application 证书、签名、公证并装订公证票据。
