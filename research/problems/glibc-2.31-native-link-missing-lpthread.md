# 问题记录：glibc < 2.34 系统上 MoonBit native 链接缺少 `-lpthread`

> 记录日期：2026-08-16
> 状态：已定位根因；已采用方案 A（cc 包装脚本 + MOON_CC）修复
> 影响范围：所有在 glibc < 2.34 的 Linux 上构建 native 目标的 MoonBit 项目（本仓库的 `cmd/openseek`、`cmd/tui`、`eval/*` 等全部 native 产物）

## 1. 现象

在 Ubuntu 20.04（glibc 2.31）上执行：

```sh
moon run cmd/openseek -- tui
```

链接阶段报大量未定义符号（全部是 pthread 函数）：

```
/usr/bin/ld: /home/YOUKNOWWHO/.moon/lib/libmoonbitrun.o: in function `mi_heap_set_default':
static.c:(.text+0x3970): undefined reference to `pthread_setspecific'
/usr/bin/ld: .../libevent_loop-7cde4104e87e4aad.a(thread_pool.o): undefined reference to `pthread_create'
/usr/bin/ld: ...(signal.o): undefined reference to `pthread_sigmask'
...（pthread_key_create / pthread_key_delete / pthread_kill / pthread_join 等）
collect2: error: ld returned 1 exit status
```

涉及两个对象：MoonBit 运行时 `libmoonbitrun.o`（mimalloc 用 pthread TLS）与 `moonbitlang/async` 的 `libevent_loop.a`（线程池/信号处理）。

## 2. 环境事实（诊断记录）

| 项 | 值 |
| --- | --- |
| 系统 | Ubuntu 20.04（WSL），glibc 2.31（`ldd --version`） |
| 编译器 | gcc 12.5.0（`cc`/`gcc`，无 clang），Ubuntu 默认 `--as-needed` |
| moon | 0.1.20260807 (4da23f8)，moonc v0.10.7+bc794d341 |
| 运行时 | `~/.moon/lib/libmoonbitrun.o` 含未定义 `pthread_key_create/key_delete/setspecific` |

## 3. 根因

用只读诊断逐步确认：

1. `nm -u ~/.moon/lib/libmoonbitrun.o | grep pthread` → 运行时确实引用 pthread 符号；
2. `gcc -dumpspecs | grep as-needed` → Ubuntu gcc 默认启用 `--as-needed`（库出现在引用它的目标文件**之前**会被丢弃，但**缺失**的库无论如何都不会被补）；
3. `moon build cmd/openseek --target native --dry-run --verbose` 打印出**真实链接命令**：

```
/usr/bin/cc -o ./_build/native/debug/build/bobzhang/openseek/cmd/openseek/openseek.exe \
  '$MOON_HOME/lib/libmoonbitrun.o' [所有包 .o/.a] -lm '$MOON_HOME/lib/libbacktrace.a'
```

**最终链接命令中根本没有 `-lpthread`**（`moonc` 二进制里搜到的 `-lm -ldl -lpthread` 是内嵌 OCaml 运行时配置，与 MoonBit 链接无关，是干扰项）。

结论：该 moon 版本生成 native 链接命令时只追加 `-lm`，不再携带 `-lpthread`/`-ldl`。其隐含假设是 **glibc ≥ 2.34**（pthread 与 dl 均已并入 libc，无需单独链接）。glibc < 2.34 的系统（Ubuntu 20.04 / Debian 10、11）pthread 符号仍在 `libpthread.so`、dl 符号仍在 `libdl.so`，缺失即链接失败。上游 CI 运行于 Ubuntu 22.04+（glibc 2.35+），因此从未暴露。

实际修复过程中还依次暴露了第二个同源缺口：`libtls.a(openssl.o)` 引用 `dlopen/dlsym` 缺 `-ldl`——一并由包装脚本补齐。

## 4. 修复方案

### 方案 A（已采用）：`cc`/`ar` 包装脚本 + `MOON_CC`（不动仓库，环境级修复）

moon 支持 `MOON_CC` 环境变量指定 C 编译器驱动（moon 二进制内有明确报错提示：*"new native backend requires a C compiler/linker driver; install clang/cc or set MOON_CC"*）。注意：**设置 `MOON_CC` 后，moon 会按 `cc`→`ar` 的名称推导归档器路径**（`MOON_CC=$HOME/.local/bin/mooncc` 时要求 `$HOME/.local/bin/moonar` 存在），因此需要配套的 `ar` 包装。

包装脚本 `~/.local/bin/mooncc`：

```sh
#!/bin/sh
# 编译调用（含 -c）原样透传；链接调用追加 -ldl -lpthread
case " $* " in
  *" -c "*) exec /usr/bin/cc "$@" ;;
esac
exec /usr/bin/cc "$@" -ldl -lpthread
```

配套 `~/.local/bin/moonar`：

```sh
#!/bin/sh
exec /usr/bin/ar "$@"
```

- 链接命令里 `-ldl -lpthread` 追加在目标文件之后，`--as-needed` 下会被保留；
- 编译（`-c`）路径不受影响；
- `ld -r`（stub 归档）不经包装脚本，无副作用；
- 生效方式：`export MOON_CC=$HOME/.local/bin/mooncc`（本机已写入 `~/.zshrc`），或单次 `MOON_CC=... moon run ...`。

适用性说明：`-ldl -lpthread` 对 glibc ≥ 2.34 系统是空操作（兼容），但**没有此问题的机器不需要该包装脚本**，仅在 glibc < 2.34 上必需。

### 方案 B（备选，仓库级修复）：moon.pkg 声明 native link flags

moon 二进制内存在 `NativeLinkConfig{ cc-link-flags, stub-cc, ... }` 配置结构。可在可执行包（如 `cmd/openseek/moon.pkg`）尝试声明：

```json
{ "link": { "native": { "cc-link-flags": ["-lpthread"] } } }
```

或新 `moon.pkg` 格式对应的 link 段。优点：仓库内修复，老系统用户直接可构建；缺点：需要验证 schema 与 flag 插入位置（是否在目标文件之后），且属针对旧 glibc 的 workaround，上游未必接纳。

### 方案 C（治本）：升级环境

- `moon upgrade` 到更新的 nightly/stable——不保证修复（行为可能是有意依赖 glibc ≥ 2.34）；
- 把 WSL 发行版升级到 Ubuntu 22.04+（glibc 2.35）——pthread 并入 libc，问题彻底消失。

### 方案 D：报告上游

glibc < 2.34 的 Linux 用户均会受影响，建议到 moonbitlang 提 issue：native 链接应检测工具链目标系统的 glibc 版本，或无条件追加 `-lpthread`（旧系统必需、新系统无害）。

## 5. 验证结果

1. 构建前用 `--dry-run --verbose` 对比链接命令：确认命令切换为 `mooncc`（末尾由包装脚本补 `-ldl -lpthread`）；
2. `MOON_CC=$HOME/.local/bin/mooncc moon build cmd/openseek --target native` 链接通过（59 tasks，产物 `openseek.exe` 37MB ELF x86-64）；
3. `moon run cmd/openseek -- --help` 正常输出命令树；
4. `moon run cmd/openseek -- tui`（原失败命令）正常走到预期行为：`error: an API key is required for deepseek-v4-pro: pass --api-key`（与 `tests/cram/tui.md` 的离线行为一致）；
5. 修复已写入 `~/.zshrc`（`export MOON_CC="$HOME/.local/bin/mooncc"`），新 shell 自动生效。

遗留警告（不阻塞）：async 的 `thread_pool.c` 引用 `posix_spawn_file_actions_addchdir_np`（glibc ≥ 2.32 才有），本机 glibc 2.31 下产生 implicit-declaration 警告——async 源码内置了旧 glibc 回退，属其上游兼容性处理，与本次修复无关。

## 6. 备注

- 本问题与 OpenSeek 代码无关，是 MoonBit 工具链在旧 glibc 平台的兼容性缺口（`-lm` 保留但 `-ldl -lpthread` 被移除）；
- 该机器上所有 native 构建（agent、TUI、eval harness、桌面端 `package/*`）均受影响，方案 A 一次性解决全部。
