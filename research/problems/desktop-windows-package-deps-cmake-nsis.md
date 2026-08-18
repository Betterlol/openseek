# 问题记录：Windows 桌面端打包缺少 CMake / NSIS（含完整打包流程）

> 记录日期：2026-08-18
> 状态：已解决（winget 安装 CMake 4.4.2、NSIS 3.12 后打包成功）
> 命令：`moon -C desktop run --target native package/windows`
> 环境：Windows 11，PowerShell，moon 0.10.x，已有 MSVC（Visual Studio 17 2022）

## 1. 背景：打包产物从哪里来

`moon build cmd/openseek --target native --release` 只构建**引擎**二进制
（产物在 `_build/native/release/build/cmd/openseek/openseek.exe`），
**不生成**桌面产物。桌面 bundle / zip / NSIS 安装器由桌面打包脚本产出：

```powershell
moon -C desktop run --target native package/windows -- --release
```

产物（注意在 `desktop/dist/` 下，不是仓库根 `dist/`）：

```text
desktop/dist/windows-x64/SeekMoon/     # bundle
desktop/dist/SeekMoon-windows-x64.zip  # 便携 zip
desktop/dist/SeekMoon-Setup.exe        # NSIS 安装器（装到 %LOCALAPPDATA%\Programs\SeekMoon，无需管理员）
```

不带 `-- --release` 时构建 debug 产物；带 `-- --release` 才构建优化产物。

## 2. 现象

依次报两个环境缺依赖错误：

1. `package error: CMake is required to package SeekMoon, but 'cmake --version' could not be run. ...`
2. `package error: makensis.exe not found. Install NSIS on PATH or extract portable NSIS to desktop/dist/tools/nsis-3.12/makensis.exe.`

## 3. 修复：winget 安装缺失工具

### CMake（需要打包 Proton native / CEF）

```powershell
winget install Kitware.CMake --accept-package-agreements --accept-source-agreements --disable-interactivity
```

首次尝试曾因网络问题失败（`InternetOpenUrl() failed. 0x80072efd`），重试即成功。
安装后 CMake 在 `C:\Program Files\CMake\bin\cmake.exe`，但**当前终端不刷新 PATH**，
需新开终端或本会话临时加入：

```powershell
$env:PATH = "C:\Program Files\CMake\bin;" + $env:PATH
cmake --version   # 验证
```

### NSIS（用于生成安装器）

```powershell
winget install NSIS.NSIS --accept-package-agreements --accept-source-agreements --disable-interactivity
```

装到 `C:\Program Files (x86)\NSIS\makensis.exe`（同样不刷 PATH）：

```powershell
$env:PATH = "C:\Program Files (x86)\NSIS;" + $env:PATH
```

## 4. 完整打包流程（本次实际执行的完整顺序）

前置（一次性的）：

```powershell
# 1. 初始化 lepus 子模块（moon.work 解析 workspace 时要求路径存在）
git submodule update --init desktop/lepus

# 2. 本会话注入 PATH（新开终端会自动带上）
$env:PATH = "C:\Program Files\CMake\bin;C:\Program Files (x86)\NSIS;" + $env:PATH
```

打包命令：

```powershell
moon -C desktop run --target native package/windows
# 优化产物：
moon -C desktop run --target native package/windows -- --release
```

该命令自动完成（均为一次性/可缓存步骤）：

- 构建并 stage Lepus codegen CLI（`desktop/lepus` 下的 `moon install ./cli --bin target/lepus-tools`）及 `proton_cli`
- 下载并解压 CEF（约 151 MB，缓存于 `~/.proton/cache/cef/win32-x64/`），组装 Proton runtime（`desktop/lepus/.proton/runtimes/win32-x64/`）
- CMake 构建 Proton native（MSVC 19.42，Windows SDK 10.0.22621）
- 构建桌面前端（`moon build frontend/desktop --target js`，下载 mermaid 11.16.0 / xterm 5.5.0 / esbuild 并校验）
- 构建桌面宿主（`moon build . --target native`）和引擎（`moon build cmd/openseek --target native`）
- 下载 MoonBit 工具链 seed（moonbit 0.10.7 windows-x86_64 + core）放入 bundle 的 `toolchains/`
- 组装 `desktop/dist/windows-x64/SeekMoon/`，压缩 zip，调用 makensis 生成安装器

## 5. 结果验证

```text
desktop/dist/
  windows-x64/SeekMoon/       # bundle：openseek-desktop.exe、openseek.exe、cef_process.exe、
                              #   proton.dll、libcef.dll、assets/、Resources/、toolchains/
  SeekMoon-windows-x64.zip    290.7 MB（debug）
  SeekMoon-Setup.exe          190.1 MB（debug，lzma 压缩后 25.4%）
```

## 6. 遗留事项

- 本次产物为 **debug** 构建；正式分发请用 `-- --release` 重新打包。
- 运行 `SeekMoon-Setup.exe` 的目标机器需已安装 Microsoft WebView2 Runtime。
- 从仓库根执行 `moon build cmd/openseek` 只是引擎构建，若再遇到"没看到产物"，先确认跑的是 `moon -C desktop run --target native package/windows`。
