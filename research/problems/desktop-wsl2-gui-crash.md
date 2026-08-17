# 问题记录：SeekMoon 桌面端（Linux AppImage）在 WSL2 + Ubuntu 20.04 上启动即崩溃

> 记录日期：2026-08-17
> 状态：**已搁置**（环境不兼容，未给出完整解决方案）
> 命令：`./SeekMoon-linux-x86_64.AppImage`（或解包后 `./AppRun` / `openseek-desktop-bin`）
> 产物：`desktop/dist/SeekMoon-linux-x86_64.AppImage`（约 404MB）

## 1. 现象

- 前提全部就绪：AppImage 打包成功、WSLg 显示环境可用（`DISPLAY=:0`、`/mnt/wslg` 存在）、`ldd` 无缺失共享库、CEF 的 `libcef.so` 仅要求 GLIBC_2.25（本机 glibc 2.31 满足）。
- 但启动即静默崩溃：退出码 **133**（SIGTRAP），stdout/stderr 无任何输出，`chrome_debug.log` 为空，宿主日志（`OPENSEEK_DESKTOP_LOG`）未生成。
- AppImage 自身的 runtime stub 也在本机崩溃（exit 133），故用 `unsquashfs -o <offset> -d <dir>` 解包后直接运行 `AppRun`。

## 2. 诊断记录

| 步骤 | 结果 |
| --- | --- |
| `APPIMAGE_EXTRACT_AND_RUN=1` 直接运行 | exit 133，无输出 |
| strace -f 全量追踪 | 主进程完成 shell 环境探测（`zsh -i -l -c '<bin> --print-env-json <mark>'`，正常退出 0）→ CEF 初始化（写 `/proc/self/oom_score_adj` 成功）→ 线程启动 → **内核 SIGTRAP（si_code=SI_KERNEL，即 int3/`ud2`）**，全部线程被杀 |
| gdb 抓 SIGTRAP 回溯 | 崩溃指令 `ud2`（= `__builtin_trap`，Chromium 的 `IMMEDIATE_CRASH`）；回溯指向 `CefInitialize → ContentMainRunnerImpl::Initialize → ChromeMainDelegate::SandboxInitialized → AdjustOOMScore → base::WriteFile → close()` |
| 复核 Chromium 147 源码 | `file_util_posix.cc` 的 `WriteFile`/`close` 路径本身无 crash 分支——回溯受 LTO/缺失 DWARF 影响，**帧归属不可靠**，真实崩溃点未知 |
| 手工验证 `/proc/self/oom_score_adj` | shell 与 Python 写入+close 均正常，排除该路径本身问题 |
| `/dev/shm` | 3.9G，充足，排除 |
| `PROTON_CEF_LOG=1` 调试开关 | 未及验证（用户选择搁置） |

## 3. 结论（判断）

**CEF 147（Chromium 147）在 WSL2 + Ubuntu 20.04（glibc 2.31）环境下于 `CefInitialize` 阶段硬崩溃**。符号层面（GLIBC_2.25）虽满足，但 Chromium 对运行环境有符号之外的隐式要求（内核/发行版组合、WSL 特有的 proc/信号语义等），此组合不在官方支持面内：

- 上游 CI 与发布流水线只覆盖 macOS（`desktop-release.yml` 仅 macOS 任务）与常规 Linux 发行版；
- **官方没有针对 WSL 内运行 GUI 并呈现到宿主 Windows 的场景做过验证/支持**（README 的 Linux 打包说明只提系统依赖与 FUSE，未提 WSL）；
- 该环境还叠加了 glibc 2.31（2019 年）与 Chromium 147（2026 年）的巨大代差。

## 4. 搁置记录（后续可选方向，未实施）

1. **换环境**：WSL 发行版升级到 Ubuntu 22.04+（glibc ≥ 2.34），大概率规避该崩溃；或换真实 Linux 桌面。
2. **用 Windows 原生版**：用户宿主是 Windows，`package/windows` 可产出 NSIS 安装器/便携版，属官方构建面内。
3. **继续深挖 Chromium 崩溃**：`PROTON_CEF_LOG=1` 取 CEF 内部日志、crashpad 抓 minidump、或逐库二分——成本高，收益低（官方不支持该组合）。
4. **上游反馈**：向 proton/CEF 侧报告 WSL2 启动崩溃，附本记录与 strace/gdb 证据。

## 5. 前置问题回顾（已解决，供上下文）

- 本问题之前的构建链路阻塞点均已修复并另文记录：
  - glibc 2.31 native 链接缺 `-ldl -lpthread` → `~/.local/bin/mooncc` + `MOON_CC`（`glibc-2.31-native-link-missing-lpthread.md`）
  - 旧 curl 不支持 `--retry-all-errors` → 手动下载 CEF 预置缓存（`desktop-linux-curl-cef-download.md`）
  - 本机 cmake 3.16 < proton 要求的 3.20 → 用 `~/.local/bin/cmake`（4.4.2）
  - `cli.moonbitlang.com` 被墙（直连/代理均 SSL 失败）→ 从 `cli.moonbitlang.cn` 镜像下载工具链 seed 预置缓存
