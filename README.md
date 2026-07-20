# Force System WebView

KernelSU 优先的 WebUI 模块，用于手动选择目标 APP，删除并锁定其内置 X5/TBS/U4/MTWebView 私有内核目录，让 APP 回退调用 Android System WebView。

## 文件结构

- `module.prop`：模块元数据。
- `customize.sh`：安装时设置可执行权限。
- `action.sh`：模块动作按钮入口，默认处理全部内置 APP。
- `scripts/apps.conf`：内置 APP 与私有 WebView 目录配置。
- `scripts/force_system_webview.sh`：核心执行脚本。
- `webroot/index.html`：KernelSU Manager 中显示的 WebUI。
- `webroot/kernelsu.js`：WebUI 调用 KernelSU `ksu.exec` 的轻量封装。
- `build.ps1`：本地打包脚本，输出可刷入 ZIP。

## 打包方式

在仓库根目录执行：

```powershell
powershell -ExecutionPolicy Bypass -File .\build.ps1
```

生成文件位于 `dist/force_system_webview-v版本号.zip`。ZIP 根目录会直接包含 `module.prop`、`customize.sh`、`action.sh`、`scripts/` 与 `webroot/`，可在 KernelSU Manager 的模块页面中刷入。（其他管理器自行尝试）

注意：此包面向 KernelSU Manager 模块页面安装，不支持在第三方 Recovery 中刷入。

## 使用方式

1. 执行 `build.ps1` 生成模块 ZIP。
2. 在 KernelSU Manager 中刷入 `dist/force_system_webview-v版本号.zip`。
3. 重启后打开模块 WebUI，勾选需要处理的 APP，点击执行。
4. 彻底关闭对应 APP 后重新打开。

脚本只处理配置中的私有 WebView 目录、`cache` 与 `code_cache`，不会主动删除账号、聊天记录或业务数据库。当前版本不包含还原功能。
