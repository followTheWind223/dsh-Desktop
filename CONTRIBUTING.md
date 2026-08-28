# Contributing

感谢你帮助改进这个非官方 Windows 启动器。

## 提交前

1. 从官方 DeepSeek Harness 仓库准备一个已安装、已构建的源码目录。
2. 不要把 `launcher.config.json`、API Key、信任 URL、会话数据或本机路径配置提交到 Git。
3. 使用 Windows PowerShell 5.1 运行：

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\Test-Release.ps1
   ```

4. 对进程启动或清理逻辑的修改，应实际验证：后端只监听回环地址；关闭 Edge 应用窗口后，启动器创建的 Node/Edge 进程与临时配置目录均被清理；其他进程不受影响。

## Pull Request

- 说明问题、解决方案和验证结果。
- 保持安装器默认不覆盖已有配置或快捷方式；需要覆盖时必须显式使用 `-Force`。
- 不增加全局环境变量修改、凭据落盘或非回环监听。
- 新增第三方代码或素材时，同步更新许可证与 `THIRD_PARTY_NOTICES.md`。

安全问题请按 [SECURITY.md](SECURITY.md) 私下报告，不要在公开 Issue 中放入利用细节或敏感数据。
