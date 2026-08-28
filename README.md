# DeepSeek Harness Windows Desktop Launcher

一个面向 Windows 的轻量桌面启动器，把官方
[DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) Web UI 包装成独立的
Microsoft Edge 应用窗口。

项目仓库：<https://github.com/followTheWind223/dsh-Desktop>

> 本项目是非官方社区工具，不隶属于 DeepSeek，也不代表 DeepSeek 官方立场。

## 它做什么

- 双击桌面图标即可启动本机 Harness 和独立 Edge 应用窗口。
- 只监听 `127.0.0.1`，使用 Harness 生成的一次性信任令牌。
- 窗口关闭后，只终止本启动器创建的 Harness/Edge 进程。
- 不写入全局 `PATH`，不修改 Node、Git、Edge 或 Harness 的系统配置。
- 不读取、保存或硬编码 API Key；模型凭据仍由 Harness 自己管理。

窗口打开期间会有一个 Node.js 后端进程和若干 Edge 子进程，这是正常行为；关闭应用窗口后它们会被自动清理。

## 前置条件

- Windows 10/11 和 Windows PowerShell 5.1。
- Microsoft Edge。
- Git（仅首次克隆官方 Harness 时需要）。
- Node.js `^22.19.0` 或 `>=24.0.0`。Node 23 不在官方支持范围内。
- 已按官方说明安装并构建的 DeepSeek Harness 源码。

官方源码安装示例：

```powershell
git clone https://github.com/deepseek-ai/deepseek-harness.git D:\deepseek-harness
Set-Location D:\deepseek-harness
pnpm install
pnpm run build
```

DeepSeek Harness 目前是 developer preview，升级可能包含不兼容变更。部署前请阅读上游的
`SAFETY.md` 并考虑固定一个已验证的提交。

## 安装桌面启动器

克隆本项目并进入目录：

```powershell
git clone https://github.com/followTheWind223/dsh-Desktop.git D:\dsh-Desktop
Set-Location D:\dsh-Desktop
```

然后执行安装脚本：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1 `
  -HarnessDir 'D:\deepseek-harness' `
  -DataDir 'D:\deepseek-harness-data' `
  -NodePath 'D:\path\to\node.exe'
```

安装脚本会自动查找 Edge，并创建：

- 本地配置：`launcher.config.json`（已在 `.gitignore` 中排除）
- 桌面快捷方式：`DeepSeek Harness.lnk`

如果目标配置或快捷方式已存在，脚本默认拒绝覆盖。确认目标属于本项目后，可显式添加 `-Force` 更新。

D 盘安装示例：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1 `
  -HarnessDir 'D:\deepseek-harness' `
  -DataDir 'D:\deepseek-harness-data' `
  -NodePath 'D:\nvm\nvm\v24.20.0\node.exe' `
  -Force
```

## 启动与卸载

启动：双击桌面的 **DeepSeek Harness**，或直接运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\DeepSeek-Harness-Desktop.ps1
```

只移除快捷方式：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Uninstall.ps1
```

同时删除本启动器的本地路径配置：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Uninstall.ps1 -RemoveConfig
```

卸载脚本不会删除 Harness 源码、会话数据、Node.js 或 Edge，也不会修改环境变量。

## 配置文件

`launcher.config.json` 只有四个绝对路径，不应包含任何密钥：

```json
{
  "HarnessDir": "D:\\deepseek-harness",
  "DataDir": "D:\\deepseek-harness-data",
  "NodePath": "D:\\path\\to\\node.exe",
  "EdgePath": "C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe"
}
```

推荐总是通过 `Install.ps1` 生成配置，它会检查路径、构建产物和 Node 版本。

## 安全设计

- 后端绑定随机回环端口，不对局域网开放。
- 仅接受严格匹配 `http://127.0.0.1:<port>/?token=<token>` 的启动 URL。
- 令牌只保存在启动器进程内存和 Edge 启动参数中，不写日志或配置文件。
- 错误信息会遮盖信任令牌及常见 `sk-...` API Key。
- Edge 使用每次启动独立的临时配置目录，并关闭后台模式、同步和扩展。
- 清理操作同时校验进程可执行文件、专用 Edge 配置路径和目录边界。

更完整的威胁模型和漏洞报告方式见 [SECURITY.md](SECURITY.md)。

快捷方式里的 `-ExecutionPolicy Bypass` 只作用于该 PowerShell 子进程，不修改机器或用户的全局执行策略。发布前仍应审查源码、校验发布包哈希，并只从可信来源获取本项目和 Harness。

## 开发与贡献

提交更改前请运行本地验证：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Test-Release.ps1
```

不要提交 `launcher.config.json`、API Key、Harness 会话数据或本机临时文件。贡献说明见
[CONTRIBUTING.md](CONTRIBUTING.md)。发布衍生版本时，请保留“非官方”声明、`LICENSE`、
`SECURITY.md` 和 `THIRD_PARTY_NOTICES.md`，不要暗示 DeepSeek 对该启动器提供背书。

## English summary

This is an unofficial, MIT-licensed Windows desktop wrapper for an existing, built checkout of DeepSeek Harness. It launches the official Web UI on a random loopback port in Microsoft Edge app mode, keeps credentials out of the launcher configuration, and shuts down only the processes it owns when the window closes.

## License

Launcher scripts and documentation are released under the [MIT License](LICENSE).
The icon is an unmodified format conversion of the upstream DeepSeek Harness favicon; see
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). No trademark rights are granted.
