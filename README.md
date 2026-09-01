# DSH Desktop

DSH Desktop 是一个面向 Windows 10/11 的非官方开源 DeepSeek Harness 桌面端。它把官方 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) 的本地 Web 界面放进原生 WebView2 窗口，并提供真正的单文件 Windows 安装程序。

本项目不隶属于 DeepSeek，也不代表 DeepSeek 官方立场。

## 普通用户只需要一个 EXE

从 [GitHub Releases](https://github.com/followTheWind223/dsh-Desktop/releases/latest) 下载：

```text
DSH-Desktop-Setup-v<版本>-win-x64.exe
```

双击后即可选择安装位置。安装器已经包含：

- DSH Desktop 桌面程序；
- 锁定的官方 `@deepseek-ai/dsh@0.1.2-alpha.3` 生产运行包；
- 私有 Node.js `v24.20.0` 运行时；
- Microsoft WebView2 Evergreen Bootstrapper。

用户不需要下载源码仓库，也不需要预装 Git、Node.js、npm 或 pnpm。内置 Node.js 只供 DSH Desktop 使用，不修改系统或用户 `PATH`，也不会覆盖电脑上已经安装的 Node.js。

> GitHub 自动生成的 `Source code (zip)` 和 `Source code (tar.gz)` 是开发者源码，不是一键安装包。

## 安装体验

安装器支持：

- 简体中文和英文界面；
- 自由修改安装目录；
- 可选桌面快捷方式；
- 开始菜单启动与卸载入口；
- 同版本修复和后续版本原地升级；
- 检测并拒绝把程序覆盖到已有源码仓库中；
- WebView2 已存在时直接复用，不重复安装；缺失时运行随包附带且经签名验证的微软引导程序。

默认安装目录：

```text
%LOCALAPPDATA%\Programs\DSH Desktop
```

安装完成后的主要布局：

```text
DSH Desktop\
├─ DSH-Desktop.exe
├─ launcher.config.json
├─ runtime\harness\       # 官方 Harness 生产运行包
├─ runtime\node\          # 项目私有 Node.js，不进入 PATH
├─ redist\                # 微软 WebView2 引导程序
└─ data\                  # 用户设置、会话和凭据数据
```

即使不创建桌面快捷方式，也可以从开始菜单或安装目录中的 `DSH-Desktop.exe` 启动。

## 启动与安全边界

桌面端启动后会：

1. 通过绝对路径启动随包附带的 Node.js 和 Harness；
2. 强制 Harness 只监听 `127.0.0.1` 的随机端口；
3. 只接受格式严格的本机可信 URL；
4. 在原生 WebView2 窗口中显示界面；
5. 关闭窗口时通过 Windows Job Object 终止它创建的 Node.js 进程树。

API Key 和登录凭据由 Harness 自己的界面处理。安装器和桌面启动器不会硬编码 API Key，也不会把访问令牌写入 `launcher.config.json`。

## 升级与卸载

再次运行新版安装 EXE 并选择原安装目录即可升级。安装器使用固定 AppId 保存升级关系，并重新生成与当前安装目录匹配的配置。

从 Windows“已安装的应用”或开始菜单选择“卸载 DSH Desktop”：

- DSH Desktop、内置 Harness、内置 Node.js、WebView2 引导程序、快捷方式和卸载注册项会一起删除；
- 用户数据默认保留；
- 交互式卸载会询问是否同时永久删除用户数据和会话；
- 静默卸载始终保留用户数据；
- 数据目录若是重解析点不会被递归删除。

## Windows 安全警告与签名

未签名版本仍可运行，但 Windows SmartScreen 或浏览器可能显示“未知发布者”或低信誉提示。请只从本仓库 Release 下载，并先核对同一 Release 中的 `SHA256SUMS-v<版本>-win-x64.txt`。

项目已申请 SignPath Foundation。获批后的正式版本将按照 [代码签名政策](CODE_SIGNING_POLICY.md) 在公开 CI 中签名；获批前的产物仍会明确标为未签名。自签名证书只对安装了该证书的测试电脑有效，不能解决普通用户的 SmartScreen 信誉问题。

## 可复现构建

构建环境：Windows PowerShell 5.1。第一次构建会把 .NET SDK 8 和 Inno Setup 6.7.3 安装到忽略版本控制的 `artifacts\tools`，不修改 PATH。

```powershell
.\Install-BuildTools.ps1

.\Build-Release.ps1 -Architecture win-x64 `
  -DotNetPath .\artifacts\tools\dotnet\dotnet.exe
```

正式产物位于 `artifacts\release`：

- 单文件安装器；
- 运行时来源和哈希清单；
- SHA-256 校验清单。

运行包构建会执行以下检查：

- Node.js 官方 ZIP 的锁定 SHA-256；
- npm lockfile 中 Harness 的精确版本和 integrity；
- 三个经审查的原生依赖生命周期脚本；
- 生产依赖高危漏洞审计；
- WebView2 引导程序的 Microsoft Authenticode 签名；
- Harness CLI 和桌面程序版本冒烟测试。

具体锁定信息见 `runtime/runtime.lock.json`。安全设计与报告方式见 [SECURITY.md](SECURITY.md)，第三方许可见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

## English summary

DSH Desktop is an unofficial, MIT-licensed Windows desktop host for DeepSeek Harness. The Release is a single self-contained installer containing the locked official Harness production package and a private Node.js runtime. End users do not need Git, Node.js, npm, pnpm, or a source checkout. It uses a loopback-only backend, a native WebView2 window, optional shortcuts, in-place upgrades, and an uninstaller that removes the bundled runtime while preserving user data by default.

## License

Launcher code and documentation are released under the [MIT License](LICENSE). The upstream name and icon are used only to identify compatibility; no trademark rights are granted.
