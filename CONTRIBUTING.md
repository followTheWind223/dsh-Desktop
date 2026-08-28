# Contributing

感谢你帮助改进这个非官方 Windows 启动器。

## 提交前

1. 不要把 `launcher.config.json`、API Key、信任 URL、会话数据或本机路径配置提交到 Git。
2. 修改任一 C# 入口后，用 Windows PowerShell 5.1 重新构建两个 EXE：

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\Build-Exe.ps1
   ```

3. 运行发布检查：

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\Test-Release.ps1
   ```

4. 修改安装流程时，至少测试一个新的隔离目录，并验证已有目标目录不会被覆盖。
5. 修改进程逻辑时，验证后端只监听回环地址；关闭 Edge 应用窗口后，启动器创建的 Node/Edge 进程与临时配置目录均被清理，其他进程不受影响。
6. 修改便携 Node.js 下载时，验证官方主机白名单、LTS 选择、SHA-256、ZIP 路径边界、失败清理和全局环境不变。
7. 修改一键卸载时，在隔离副本中验证已知文件被删除、用户额外文件被保留，并且 Harness、数据和 Node.js 均不受影响。

## Pull Request

- 说明问题、解决方案、测试目录和验证结果。
- 安装器必须固定官方仓库地址，校验用户路径，并在运行上游依赖脚本前取得明确确认。
- 保持默认不覆盖已有源码、配置或快捷方式；覆盖必须通过显式参数授权。
- 不增加全局环境变量修改、凭据落盘、非回环监听或自动强制依赖修复。
- 修改任一 EXE 时必须同时提交对应 C# 源码，且两个二进制版本都应与 `VERSION` 一致。
- 新增第三方代码或素材时，同步更新许可证与 `THIRD_PARTY_NOTICES.md`。

安全问题请按 [SECURITY.md](SECURITY.md) 私下报告，不要在公开 Issue 中放入利用细节或敏感数据。
