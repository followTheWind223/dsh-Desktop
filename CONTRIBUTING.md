# Contributing

感谢你帮助改进 DSH Desktop。

## 提交前

1. 不要提交 `launcher.config.json`、API Key、会话数据、本机绝对路径、证书私钥或 `artifacts` 构建产物。
2. 不要手工修改 `runtime/package-lock.json`。升级 Harness 时应同时更新 `runtime/package.json`、lockfile、`runtime/runtime.lock.json`、变更日志和第三方声明。
3. 新增或改变依赖生命周期脚本时，必须先审查具体包版本和脚本文本，再更新 `Build-BundledRuntime.ps1` 的精确允许列表。
4. 安装器不得修改全局 PATH，不得覆盖源码仓库，不得把 API Key 写入配置。

## 构建与验证

```powershell
.\Install-BuildTools.ps1

.\Build-BundledRuntime.ps1 -Architecture win-x64 `
  -OutputDirectory .\artifacts\bundled-runtime-win-x64 `
  -DotNetPath .\artifacts\tools\dotnet\dotnet.exe -Force

.\Build-BundledSetup.ps1 `
  -BundleDirectory .\artifacts\bundled-runtime-win-x64 `
  -Architecture win-x64 `
  -OutputDirectory .\artifacts\release
```

涉及安装流程的 PR 至少验证：

- 新目录静默安装成功，配置路径全部位于所选目录；
- 已有 WebView2 时不会重复安装；
- Harness 启动后只监听 loopback；
- 关闭桌面端后内置 Node 进程退出；
- 升级/修复不会删除 `data`；
- 卸载删除桌面端和内置 runtime，默认保留数据；
- 源码仓库目录会被安装器拒绝。

安全问题请使用仓库的私有安全报告入口，不要在公开 Issue 中附上真实凭据或可利用细节。
