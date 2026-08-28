# DeepSeek Harness Windows Desktop Launcher

面向 Windows 的非官方社区启动器。它可以从 DeepSeek 官方仓库自动下载、安装和构建
[DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)，再用独立的 Microsoft Edge
应用窗口运行 Web UI。

项目仓库：<https://github.com/followTheWind223/dsh-Desktop>

> 本项目不隶属于 DeepSeek，也不代表 DeepSeek 官方立场。

## 下载 Release

普通用户建议从 [GitHub Releases](https://github.com/followTheWind223/dsh-Desktop/releases/latest) 下载
`DSH-Desktop-v<版本>-windows.zip`，完整解压后双击 `DSH-Desktop.exe`。不要只单独下载或复制 EXE，
因为入口文件还需要压缩包内的 PowerShell 脚本。

每个 Release 同时提供 ZIP 的 `.sha256` 文件，压缩包内部的 `SHA256SUMS.txt` 则记录两个 EXE 的校验值。
例如验证下载的 ZIP：

```powershell
(Get-FileHash .\DSH-Desktop-v0.3.0-windows.zip -Algorithm SHA256).Hash
Get-Content .\DSH-Desktop-v0.3.0-windows.zip.sha256
```

两处哈希值应完全一致。当前 EXE 未进行商业代码签名，Windows SmartScreen 仍可能显示“未知发布者”。

## 最快安装

先准备：

- Windows 10/11、Windows PowerShell 5.1 和 Microsoft Edge。
- [Git for Windows](https://git-scm.com/download/win)。
- Node.js 可选。已有兼容版本可以直接使用；没有时可让启动器下载官方便携 LTS。DSH 要求 `^22.19.0` 或 `>=24.0.0`，Node 23 不受支持。
- 至少 4 GB 可用空间。

然后下载本仓库 ZIP 并解压，或使用 Git：

```powershell
git clone https://github.com/followTheWind223/dsh-Desktop.git D:\dsh-Desktop
```

双击 `DSH-Desktop.exe`。首次运行会：

1. 弹出文件夹选择器，由用户选择 DSH 的安装位置。
2. 只从 `https://github.com/deepseek-ai/deepseek-harness.git` 克隆官方源码。
3. 让用户选择使用已发现的 Node.js、手动选择 `node.exe`，或从 `nodejs.org` 下载官方便携 LTS。
4. 下载 Node.js 时自动选择 x64/ARM64 ZIP，核对官方 SHA-256 后解压到用户选择的区域。
5. 读取上游 `packageManager`，使用其固定的 pnpm 版本和锁文件安装依赖。
6. 执行官方构建，并检查必要产物。
7. 创建本地配置和带图标的桌面快捷方式；安装成功后直接打开 DSH。

例如选择 `D:\AI` 后，会使用：

```text
D:\AI\deepseek-harness
D:\AI\deepseek-harness-data
D:\AI\nodejs\node-v<version>-win-<architecture>   # 仅选择便携 Node.js 时
```

安装器不会覆盖已有的 `deepseek-harness` 目录，不修改全局 `PATH`，也不会硬编码或收集 API Key。

### Windows SmartScreen

仓库中的 `DSH-Desktop.exe` 和 `Uninstall-DSH-Desktop.exe` 都从公开的 C# 源码构建，但目前没有商业代码签名证书。Windows
SmartScreen 可能显示“未知发布者”。可以先检查 `src/DSH-Desktop`，再通过
`Build-Exe.ps1` 在本机重新编译。

## 日常启动

安装后可以：

- 双击桌面的 **DeepSeek Harness**；或
- 双击仓库目录中的 `DSH-Desktop.exe`。

窗口打开期间会运行一个 Node.js 后端进程和若干 Edge 子进程。关闭应用窗口后，启动器会停止自己创建的进程并删除本次运行的临时 Edge 配置。

## PowerShell 自动化安装

需要脚本化部署时，可以绕过文件夹选择器：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Setup.ps1 `
  -DestinationRoot 'D:\AI' `
  -NonInteractive `
  -AcceptUpstreamScripts
```

常用参数：

- `-DestinationRoot`：用户选择的父目录。
- `-NodePath`：显式指定兼容的 `node.exe`。
- `-DownloadNode`：从 `https://nodejs.org/dist/` 下载并校验最新兼容的官方便携 LTS。
- `-NodeOnly`：只配置便携 Node.js；必须与 `-DownloadNode` 一起使用，不下载 DSH。
- `-HarnessRef`：下载指定的上游分支或标签；默认使用官方默认分支。
- `-DownloadOnly`：只克隆官方源码，不安装依赖、不构建、不创建快捷方式。
- `-SkipAudit`：跳过上游依赖审计；不建议。
- `-ForceLauncherConfig`：显式替换本项目已有的配置/快捷方式。

非交互完整安装必须传入 `-AcceptUpstreamScripts`，以明确授权运行上游锁定依赖所允许的安装脚本。

非交互安装并使用便携 Node.js：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Setup.ps1 `
  -DestinationRoot 'D:\AI' `
  -DownloadNode `
  -NonInteractive `
  -AcceptUpstreamScripts
```

只下载、校验并配置便携 Node.js：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Setup.ps1 `
  -DestinationRoot 'D:\AI' `
  -DownloadNode `
  -NodeOnly `
  -NonInteractive
```

## 已有 DSH 源码时

如果已经按官方说明安装并构建 DSH，可只配置桌面入口：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1 `
  -HarnessDir 'D:\deepseek-harness' `
  -DataDir 'D:\deepseek-harness-data' `
  -NodePath 'D:\path\to\node.exe'
```

`Install.ps1` 会验证源码、构建产物、Node、Edge 和绝对路径，再生成 `launcher.config.json` 与桌面快捷方式。目标已存在时默认拒绝覆盖，只有显式传入 `-Force` 才更新。

## 卸载

双击 `Uninstall-DSH-Desktop.exe`，确认后会一键移除：

- 桌面的 **DeepSeek Harness** 快捷方式；
- `launcher.config.json`；
- 本项目已知的启动器脚本、EXE、文档、图标和源码文件。

卸载器使用严格文件白名单。若启动器目录包含 `.git` 或用户自己添加的文件，这些内容不会被删除，目录也会保留。

只移除桌面快捷方式：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Uninstall.ps1
```

同时移除启动器的本地路径配置：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Uninstall.ps1 -RemoveConfig
```

卸载器不会删除 DSH 源码、会话数据、便携 Node.js、Edge 或环境变量。源码、数据和 Node.js 必须由用户确认路径后自行处理。

## 配置文件

`launcher.config.json` 只保存四个绝对路径，并已被 `.gitignore` 排除：

```json
{
  "HarnessDir": "D:\\deepseek-harness",
  "DataDir": "D:\\deepseek-harness-data",
  "NodePath": "D:\\path\\to\\node.exe",
  "EdgePath": "C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe"
}
```

配置文件不应包含任何密钥。

## 安全设计

- 下载地址固定为 DeepSeek 官方 HTTPS GitHub 仓库，并在克隆后再次校验 `origin` 和提交哈希。
- 便携 Node.js 只从官方 `https://nodejs.org/dist/` 下载；版本来自官方索引，ZIP 必须匹配官方 `SHASUMS256.txt`，并通过归档路径与大小边界检查。
- 用户选择的目标必须是本机绝对路径；网络路径和已有 DSH 目录会被拒绝。
- 使用上游声明的精确 pnpm 版本、`pnpm-lock.yaml` 和 `--frozen-lockfile`。
- 上游当前使用严格的依赖构建白名单；完整安装前仍要求用户明确确认。
- 安装后执行 `pnpm audit --audit-level high`。发现问题时显示警告，但不会擅自执行 `audit fix` 或修改上游锁文件。
- DSH 后端只绑定随机回环端口；启动器只接受严格的 `127.0.0.1` 信任 URL。
- 信任令牌仅存在于进程内存和 Edge 启动参数中，不写入日志或配置。
- 清理操作校验 Node 可执行文件、进程树、专用 Edge 参数和临时目录边界。
- 一键卸载要求明确确认，只删除严格白名单中的启动器文件，任何未识别文件都会被保留。
- 快捷方式中的执行策略只作用于对应 PowerShell 子进程，不修改系统全局策略。

完整威胁模型及漏洞报告方式见 [SECURITY.md](SECURITY.md)。DeepSeek Harness 仍是 developer preview，使用前也应阅读其官方 `SAFETY.md`。

## 构建 EXE

在 Windows 10/11 上运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Build-Exe.ps1
```

构建脚本使用 Windows 自带的 .NET Framework C# 编译器，将官方鲸鱼 ICO 嵌入
`DSH-Desktop.exe` 和 `Uninstall-DSH-Desktop.exe`。两个 EXE 只负责调用同目录中公开的 PowerShell 脚本，不内嵌 API Key 或隐藏脚本。

## 发布 Release

维护者可以先在本机生成与 GitHub Actions 相同结构的发布包：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Build-Release.ps1
```

产物会写入忽略版本控制的 `artifacts` 目录。正式发布时，先同步 `VERSION`、`CHANGELOG.md` 和两个 C#
入口文件中的版本号，提交并推送 `main`，然后创建与 `VERSION` 完全匹配的标签：

```powershell
$version = (Get-Content .\VERSION -Raw).Trim()
git tag -a "v$version" -m "DSH Desktop v$version"
git push origin main
git push origin "v$version"
```

标签推送后，GitHub Actions 会在干净的 Windows Runner 中重新构建和验证文件，生成 ZIP 与 SHA-256，
并自动创建对应的 GitHub Release。工作流只使用仓库临时 `GITHUB_TOKEN`，无需保存个人访问令牌。

## 开发与验证

提交更改前运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Build-Exe.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\Test-Release.ps1
```

贡献说明见 [CONTRIBUTING.md](CONTRIBUTING.md)。不要提交 `launcher.config.json`、API Key、信任 URL、会话数据或本机路径配置。

## English summary

This is an unofficial, MIT-licensed Windows setup and desktop entry point for DeepSeek Harness. On first run, `DSH-Desktop.exe` lets the user choose an installation root and either use an existing Node.js runtime or download a checksum-verified portable LTS from the official Node.js distribution site. `Uninstall-DSH-Desktop.exe` removes only known launcher files after confirmation while preserving Harness, data, Node.js, and unrecognized user files.

## License

Launcher code and documentation are released under the [MIT License](LICENSE). The icon is an unmodified format conversion of the upstream DeepSeek Harness favicon; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). No trademark rights are granted.
