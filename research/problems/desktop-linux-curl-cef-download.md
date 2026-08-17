# 问题记录：Ubuntu 20.04 上桌面端 Linux 打包（CEF 下载失败）

> 记录日期：2026-08-16
> 状态：CEF 下载问题已用缓存预置解决；构建仍需安装 `libgtk-3-dev`
> 命令：`moon -C desktop run --target native package/linux -- --release`

## 1. 现象

proton_cli 执行 `cef setup` 下载 CEF 时失败：

```
$ proton_cli -C desktop/lepus cef setup
[INFO] Downloading CEF: https://cef-builds.spotifycdn.com/cef_binary_147.0.14+..._linux64_minimal.tar.bz2
curl: option --retry-all-errors: is unknown
...（3 次尝试全部失败）
error: Download failed for ...: curl exited with code 2
```

## 2. 根因

`desktop/lepus/cli/cef/cef_download.mbt:32` 的下载命令：

```
curl -L --fail --retry 5 --retry-all-errors --retry-delay 2 ...
```

`--retry-all-errors` 是 **curl 7.71.0**（2020-04）才加入的参数；Ubuntu 20.04 自带 curl 7.68.0 不识别，curl 直接 exit 2。同前一个问题（native 链接缺 `-ldl -lpthread`）一样，这是旧发行版工具版本缺口，上游 CI（Ubuntu 22.04+）不会暴露。

## 3. 修复：手动下载 + 预置 CEF 缓存

proton_cli 的缓存复用逻辑（`lepus/cli/cef/cef_cache.mbt` 的 `ensure_cef_cache`）：命中条件 = 目录存在 + `version.txt` == CEF name + `sha256.txt` == 期望校验和。因此完全不需要改子模块：

```sh
# 1. 下载（用系统 curl 即可，不带 --retry-all-errors）
curl -L --fail -C - -o /tmp/opencode/cef_linux64_minimal.tar.bz2 \
  "https://cef-builds.spotifycdn.com/cef_binary_147.0.14+g76d2442+chromium-147.0.7727.138_linux64_minimal.tar.bz2"

# 2. 校验（sha256 来自 lepus/cli/cef/cef_platform.mbt:150）
echo "a2cef000527e9952bae470a292f12384c790523dadcbbcbee807743a539c6de0  <file>" | sha256sum -c -

# 3. 解压到全局缓存目录（布局：<cache>/<platform.id>/<name>/）
mkdir -p ~/.proton/cache/cef/linux-x64/
tar -xjf <file> -C ~/.proton/cache/cef/linux-x64/

# 4. 写入版本与校验和标记（enable_cef_cache 的命中判据）
cd ~/.proton/cache/cef/linux-x64/cef_binary_147.0.14+g76d2442+chromium-147.0.7727.138_linux64_minimal
printf '%s\n' "cef_binary_147.0.14+g76d2442+chromium-147.0.7727.138_linux64_minimal" > version.txt
printf '%s\n' "a2cef000527e9952bae470a292f12384c790523dadcbbcbee807743a539c6de0" > sha256.txt

# 5. 重跑 setup，应从缓存组装运行时
proton_cli -C desktop/lepus cef setup
```

验证：setup 成功输出 `Assembling Proton runtime: .../runtimes/linux-x64/proton-0.1.16_cef-147...`。

备用方案（未采用）：给 `cef_download.mbt` 去掉 `--retry-all-errors`（修改子模块，submodule update 时丢失）；或安装新版 curl。

## 4. 构建的其余系统依赖（Ubuntu 20.04）

proton native CMake（`lepus/native/CMakeLists.txt:59-60`）实际只要求：

- `pkg-config`（已有）
- `gtk+-3.0`（**缺失**，需 `sudo apt install libgtk-3-dev`）
- `x11`（已有）
- cmake（已有 4.4.2）、curl（已有）

注意：README 提到 `libwebkit2gtk-4.1-dev`，但那是 22.04+ 的包名；20.04 只有 webkit2gtk-4.0，且 proton native 构建并不需要它（CEF 自带 Chromium），可忽略。

## 5. 遗留风险

- Chromium 147（CEF）运行时代码可能要求比 glibc 2.31 更新的 glibc——AppImage 能否在 20.04 上运行待构建后实测；若失败，属于"打包产物无法在本机跑"，需要升级发行版（glibc ≥ 2.34）或换台机器。
