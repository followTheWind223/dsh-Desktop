# DSH Desktop

DSH Desktop 是一个面向 Windows 10/11 的非官方开源 DeepSeek Harness 桌面端。它把官方 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) 的本地 Web UI 放进原生 WebView2 窗口，并提供图形安装、环境检测、便携 Node.js、快捷方式和安全卸载。

本项目不隶属于 DeepSeek，也不代表 DeepSeek 官方立场。仓库地址：[followTheWind223/dsh-Desktop](https://github.com/followTheWind223/dsh-Desktop)。

## Code signing policy

For approved signed releases: Free code signing provided by [SignPath.io](https://signpath.io/), certificate by [SignPath Foundation](https://signpath.org/). Releases published before the signing integration is approved remain unsigned and are identified as such in the release documentation. See the full [Code signing policy](CODE_SIGNING_POLICY.md) and [Privacy policy](PRIVACY.md).

## v0.4.1 主要功能

- 高 DPI 清晰渲染：启用 Per-Monitor V2，在 125%、150%、175% 等 Windows 缩放比例下按显示器原生像素重绘 WebView2，避免系统位图拉伸造成文字发虚。

- 原生桌面窗口：不再用 Edge `--app` 模式，直接使用 Microsoft WebView2 承载 Harness。
- 图形安装器：用户可选择安装区域、界面语言、Node.js 方案、桌面快捷方式和开始菜单入口。
- 智能复用：先检查已有 Harness、数据目录、Node.js 和 WebView2；满足条件就跳过对应安装。
- 迁移修复：能识别“目录存在但 pnpm 链接已失效”的 Harness，并只修复依赖和构建。
- 便携 Node.js：仅在用户选择或没有兼容版本时，从 `nodejs.org` 下载官方 ZIP，校验官方 SHA-256，不修改系统 `PATH`。
- 双语界面：默认跟随 Windows 自动切换简体中文/English，也可手动指定。
- 可选入口：即使不创建任何快捷方式，也可以从安装目录运行 `DSH-Desktop.exe`。
- 安全卸载：默认只删除桌面端、配置和快捷方式；Harness、Node.js 和数据必须由用户单独勾选，而且只允许删除安装器自己创建并记录的组件。
- 单文件与便携包：Release 同时提供一个安装器 EXE 和一个可完整解压运行的 ZIP。

## 下载与安装

签名状态、签名责任人与发布验证流程见 [Code signing policy](CODE_SIGNING_POLICY.md)。SignPath 接入获批前发布的 EXE 仍为未签名版本。

从 [GitHub Releases](https://github.com/followTheWind223/dsh-Desktop/releases/latest) 下载以下任一文件：

- `DSH-Desktop-Setup-v<版本>.exe`：推荐。双击后选择安装区域。
- `DSH-Desktop-v<版本>-windows-portable.zip`：完整解压后双击 `DSH-Setup.exe`。

安装器会显示检测结果，再由用户决定：

1. 安装到哪个区域，例如 `D:\deepseek`。
2. 自动复用兼容 Node.js、下载官方便携 Node.js，或手动选择 `node.exe`。
3. 是否创建桌面快捷方式和开始菜单入口。
4. 安装后是否立即启动。

选择 `D:\deepseek` 时，默认布局为：

```text
D:\deepseek\dsh-desktop               # 桌面程序和维护入口
D:\deepseek\deepseek-harness          # 官方 Harness 源码与构建结果
D:\deepseek\deepseek-harness-data     # 用户配置、凭据和会话数据
D:\deepseek\nodejs\node-v...         # 仅在下载便携 Node.js 时创建
```

### 环境复用规则

| 检测结果 | 安装器行为 |
|---|---|
| 官方 Harness 已构建且依赖可解析 | 直接复用，不执行 `pnpm install` 和构建 |
| 官方 Harness 源码存在，但构建缺失或迁移后链接失效 | 复用源码，按锁文件修复依赖并重新构建 |
| Harness 不存在 | 只从官方 GitHub 仓库克隆 |
| 找到 `^22.19.0` 或 `>=24.0.0` 的 Node.js | 直接复用 |
| 只找到不兼容 Node.js（例如 Node 23） | 忽略它，并让用户选择或下载兼容版本 |
| WebView2 Runtime 不存在 | 下载微软官方 Evergreen Bootstrapper，验证 Microsoft 代码签名后安装 |

现有非空目录不会被当作新项目直接覆盖。没有 Git 元数据的 Harness 默认不会被信任或接管。

### Windows SmartScreen

当前发布的 EXE 尚未使用商业代码签名证书。它们仍可运行，但 SmartScreen 可能显示“未知发布者”。可先核对 Release 中的 `SHA256SUMS-v<版本>.txt`，或审查源码后自行构建。

## 日常使用

安装后可从以下任一入口启动：

- 桌面上的 **DeepSeek Harness**（如果安装时勾选）；
- 开始菜单中的 **DSH Desktop / DeepSeek Harness**（如果勾选）；
- 安装目录里的 `DSH-Desktop.exe`。

桌面端会启动一个只监听 `127.0.0.1` 随机端口的 Harness 后端，再在原生 WebView2 窗口中打开它。关闭窗口后，桌面端会终止自己创建的 Node.js 和 WebView2 进程，并清理本次临时浏览器目录。

API Key 或登录凭据仍由 Harness 自己的界面处理。DSH Desktop 不硬编码、不收集，也不把凭据写入启动器配置。

再次运行安装目录中的 `DSH-Setup.exe` 可以调整配置和快捷方式。

## 卸载

双击 `Uninstall-DSH-Desktop.exe`。默认选项会删除：

- 桌面端程序和 `launcher.config.json`；
- 本项目创建的桌面与开始菜单快捷方式；
- 已知的桌面端脚本、运行库和文档。

Harness、便携 Node.js 和用户数据默认保留。只有它们确实由当前安装器创建并记录时，对应复选框才可用；删除用户数据还需要二次确认。目录中的未知文件永远不会被清理脚本删除。

## PowerShell 自动化

查看某个区域的检测结果，不进行写入：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Setup.ps1 `
  -DestinationRoot 'D:\deepseek' -NonInteractive -Inspect
```

复用已有环境并配置桌面端：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Setup.ps1 `
  -DestinationRoot 'D:\deepseek' `
  -NonInteractive `
  -CreateDesktopShortcut `
  -CreateStartMenuShortcut
```

如果缺少兼容 Node.js，可增加 `-DownloadNode`。只有需要安装依赖或构建 Harness 时，非交互模式才要求 `-AcceptUpstreamScripts`。

## 配置文件

`launcher.config.json` 只保存本地路径、界面语言和组件所有权标记：

```json
{
  "SchemaVersion": 2,
  "HarnessDir": "D:\\deepseek\\deepseek-harness",
  "DataDir": "D:\\deepseek\\deepseek-harness-data",
  "NodePath": "D:\\deepseek\\nodejs\\node-v24.20.0-win-x64\\node.exe",
  "Language": "auto",
  "HarnessManaged": false,
  "DataManaged": false,
  "NodeManaged": false
}
```

该文件不应包含 API Key、登录令牌或 Harness 的本地访问 URL。

## 安全设计

- Harness 下载源固定为官方 HTTPS GitHub 仓库，并验证 `origin` 与提交哈希。
- Node.js 固定从 `https://nodejs.org/dist/` 下载，校验官方 `SHASUMS256.txt`，并检查 ZIP 路径和大小边界。
- WebView2 Bootstrapper 必须具有有效的 Microsoft Authenticode 签名。
- 构建使用上游声明的精确 pnpm 版本、`pnpm-lock.yaml` 和 `--frozen-lockfile`。
- 后端仅绑定 `127.0.0.1` 随机端口；启动器只接受严格的本机可信 URL，并在诊断文本中隐藏访问令牌。
- WebView2 禁用开发者工具、密码保存、自动填充、权限申请和跨来源窗口内导航；外部 HTTPS 链接交给系统浏览器。
- 子进程放入 Windows Job Object，桌面窗口退出时统一清理。
- 不修改系统或用户级环境变量，不覆盖用户的已有项目，不执行自动 `audit fix`。

完整说明与漏洞报告方式见 [SECURITY.md](SECURITY.md)。DeepSeek Harness 仍处于 developer preview，也应阅读其官方 `SAFETY.md`。

## 开发与构建

构建环境：Windows 10/11、Windows PowerShell 5.1、.NET SDK 8、.NET Framework 4.8 Developer Pack。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Build-Exe.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\Build-Setup.ps1 `
  -PayloadDirectory . -OutputPath .\DSH-Setup.exe
powershell -NoProfile -ExecutionPolicy Bypass -File .\Test-Release.ps1
```

生成正式 Release 产物：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Build-Release.ps1
```

产物写入忽略版本控制的 `artifacts` 目录，包括单文件安装器、便携 ZIP 和统一 SHA-256 清单。推送与 `VERSION` 一致的 `v<版本>` 标签后，GitHub Actions 会在干净的 Windows Runner 中重建并创建 Release。

## English summary

DSH Desktop is an unofficial, MIT-licensed Windows desktop app and installer for the official DeepSeek Harness. It provides a native WebView2 window, graphical location selection, Chinese/English UI, reuse-first environment detection, checksum-verified portable Node.js, optional shortcuts, a standalone setup EXE, a portable ZIP, and ownership-aware uninstall behavior. It does not modify global PATH or store API keys.

## License

Launcher code and documentation are released under the [MIT License](LICENSE). The icon is derived from the upstream DeepSeek Harness favicon; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). No trademark rights are granted.
