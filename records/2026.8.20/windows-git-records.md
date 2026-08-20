# Windows 桌面端 Shell 工具 git 命令超时 — 排查记录（2026.8.20）

> 本文记录一次完整的根因排查过程：从报告的 `git --version` 在 Windows 桌面端 shell 工具中超时，到最终确认根因并修复。所有结论均有受控实验支撑，实验可复现。

---

## 1. 问题现象

在 OpenSeek Windows 桌面端（`openseek-desktop.exe`）的 shell 工具中执行：

```
git --version
```

或：

```
D:\Git\mingw64\bin\git.exe version
```

均返回：

```
error: shell command timed out after 120000ms
```

但：
- 宿主 PowerShell 中 `git --version` 正常；
- WSL 中 `git --version` 正常；
- 引擎（`openseek.exe serve`）通过 shell 工具执行其他命令（如 `dir`）可能正常，唯独 git 系列命令超时。

超时错误源：`agent_tool/shell/shell.mbt:420` — `"error: shell command timed out after \{effective_timeout_ms}ms\{budget}"`。

---

## 2. 排查过程（按时间线）

### 2.1 第一阶段：依据报告盲修（无效）

排查报告，重点怀疑：
- H1：Windows 子进程 stdout/stderr pipe 死锁（★★★★★）
- H2：Process Job Object 杀进程逻辑异常（★★★★★）
- H3：环境变量被 sandbox 修改（★★★★☆）
- H4：Shell backend 默认 Unix 假设（★★★★☆）

**第一轮修复**（均基于 H1/H2 猜测）：

1. `desktop/lepus/sys/process/native_windows.c`：
   - `bInheritHandles FALSE → TRUE`
   - `creation_flags 0 → CREATE_NO_WINDOW | CREATE_BREAKAWAY_FROM_JOB`
   - 新增 Job Object 创建/Assign，kill 改用 `TerminateJobObject`，cleanup 关闭 `h_job`
2. `desktop/lepus/sys/process/native_stub.h`：`process_state_t` 新增 `void *h_job`
3. `agent_tool/internal/platform_shell/platform_shell.mbt`：PowerShell 参数新增 `-NonInteractive`

**结果：无效。** 复测仍超时。

### 2.2 第二阶段：确认真实 spawn 路径（关键认知修正）

排查发现：shell 工具实际使用的 spawn 路径**不是** `desktop/lepus/sys/process`，而是 **`moonbitlang/async/process`**（async@0.20.4）：

- `agent_tool/shell/shell.mbt:725` `collect_process_output`：
  `@process.read_from_process()` + `@process.spawn(group, program, args, stdout=writer, stderr=writer, no_console_window=true, no_wait=true)`
- `agent_tool/shell_exec/execution.mbt:92` `ShellExecution::start`：同样的模式

**推论**：第一轮对 `desktop/lepus` 的修改与 git 超时无关（该模块是 Proton 的独立 process 封装，shell 工具根本不经过它）——已在后续 revert。

async/process 的 Windows 实现（`src/internal/event_loop/thread_pool.c`，spawn_job_worker 850-990 行）本身实现完整：使用 `PROC_THREAD_ATTRIBUTE_HANDLE_LIST` 精确继承、Job Object、`CREATE_NO_WINDOW`。**独立探针全部通过**，说明 spawn 层本身无问题，问题在调用方的参数组合。

### 2.3 第三阶段：独立探针实验（全部通过，排除 spawn 层）

| # | 探针 | 内容 | 结果 |
|---|------|------|------|
| 1 | 基础 PowerShell 管道 | `powershell -Command "git --version"`，.NET Process 捕获输出 | ✅ 正常 |
| 2 | 精确复刻 shell 工具模式 | `read_from_process` + 同一 writer 给 stdout/stderr + spawn + 后台 drain + `process.wait()` | ✅ 322ms 正常 |
| 3 | 无控制台 | gcc 编写 `CREATE_NO_WINDOW` launcher 跑 git | ✅ 正常 |
| 4 | stdin 为保持打开的管道 | 显式传独立 stdin 管道（写端保持打开） | ✅ 正常 |
| 5 | `@process.collect_output_merged("git", ["--version"], no_console_window=true)` | 直接跑 git 而非 powershell 包装 | ✅ 正常 |

**结论**：在独立 MoonBit 进程里，shell 工具的完整调用模式跑 git 不超时。问题一定出在**引擎进程本身被 spawn 的方式**。

### 2.4 第四阶段：引擎级复现（核心突破）

编写 `engprobe`（MoonBit 程序），用与桌面 host 完全相同的方式 spawn 打包引擎 `openseek.exe serve`：

- `inherit_env=false` + `extra_env=@env.get_env_vars()`（全量 env）
- `stdin=write_to_process()` 管道（写端保持打开）
- `stdout/stderr` 管道
- `no_console_window=true`
- `cwd=workspace root`
- 写入 prompt：`{"command":"prompt","text":"Run the shell tool with exactly this command and report its output: git --version"}`

**第一次成功复现卡死**：引擎输出 `agent_step` + `reasoning_message` 后，**200 秒内无 `tool_result`、无 timeout 错误返回**——与桌面端现象完全一致。

### 2.5 第五阶段：变量分离实验（锁定根因）

对 engprobe 的 spawn 参数做组合实验：

| 配置 | 结果 |
|------|------|
| `no_console_window=true` + stdin 写端**保持打开** | ❌ 卡死（复现） |
| `no_console_window=true` + stdin 写端**关闭**（`writer.close()`） | ✅ 正常，`git version 2.46.2.windows.1` exit=0 |
| 无 `no_console_window` + stdin 写端保持打开 | ❌ 卡死 |
| 无 `no_console_window` + stdin 写端关闭 | ✅ 正常 |

**根因确认：引擎的 stdin 管道写端是否保持打开是唯一决定变量，与 `no_console_window` 无关。**

对照实验（gitprobe，独立进程）：显式传独立 stdin 管道（写端打开或关闭）→ 均正常。说明问题不是"写端打开"本身，而是 **"子进程继承引擎的 stdin 管道句柄"**：

- 桌面 host spawn 引擎时 `stdin=child_stdin`（管道读端），写端在 host 侧保持打开（host 需持续向引擎发命令）；
- 引擎内 shell 工具 spawn powershell 时**不传 stdin** → async/process 的 `spawn_job_worker` 中 `job->stdio[0] == INVALID_HANDLE_VALUE` 时回退到 `GetStdHandle(STD_INPUT_HANDLE)` → **powershell/git 继承了引擎的 stdin 管道读端**；
- 该管道写端在 host 侧永不关闭 → git（MSYS2 运行时）感知到 stdin 管道无 EOF，行为异常挂起；
- 独立进程探针的 stdin 是终端或独立管道，不构成"写端永不关闭的共享管道"，所以全部正常。

---

## 3. 修复方案

**给 shell 子进程显式传一个写端立即关闭的独立 stdin 管道**，切断与引擎 stdin 的句柄共享：

```moonbit
// agent_tool/shell/shell.mbt — collect_process_output
let (reader, writer) = @process.read_from_process()
@async.with_task_group() <| group => {
  defer reader.close()
  let (stdin_reader, stdin_writer) = @process.write_to_process()
  stdin_writer.close()
  let process = @process.spawn(
    group,
    program,
    args,
    stdin=stdin_reader,
    stdout=writer,
    stderr=writer,
    cwd?=cwd.map(cwd => cwd.view()),
    cancel_handler=@process.hard_cancel(),
    no_wait=true,
    no_console_window=true,
  )
  ...
}
```

```moonbit
// agent_tool/shell_exec/execution.mbt — ShellExecution::start
let (reader, writer) = @process.read_from_process()
let (stdin_reader, stdin_writer) = @process.write_to_process()
stdin_writer.close()
let process = @process.spawn(
  group,
  program,
  args,
  stdin=stdin_reader,
  stdout=writer,
  stderr=writer,
  cwd?=cwd.map(cwd => cwd.view()),
  cancel_handler=@process.hard_cancel(),
  no_wait=true,
  no_console_window=true,
)
```

---

## 4. 验证

1. **引擎级验证**：engprobe 指向新构建的引擎二进制（`moon build cmd/openseek --target native --release`），保持**真实桌面配置**（stdin 写端保持打开 + no_console_window + inherit_env=false + 全量 env）：
   ```
   PROMPTING
   STEP: ... agent_step 1
   TOOL_RESULT: ... tool_name=shell, is_error=false, content="git version 2.46.2.windows.1\n<system>exit=0</system>"
   agent_finished ...
   SAW_TOOL_RESULT=true
   SAW_FINISH=true
   ```
   修复前同一配置 200s 卡死；修复后约 2 秒完成。

2. **回归测试**：`moon test agent_tool/shell agent_tool/shell_exec --target native` — 69 测试中 16 个失败，但**基线（stash 掉修复后）同样 69 测试 16 个失败**，均为预先存在的 Windows 环境问题（symlink 权限 `A required privilege is not held by the client` 等），与本次改动无关，无回归。

3. **接口检查**：`moon info && moon fmt` 后 `agent_tool/shell/pkg.generated.mbti` 无内容变化（仅行尾差异）——内部修复，对外接口不变。

4. **桌面端生效**：桌面端运行的是打包引擎 `desktop/dist/windows-x64/SeekMoon/openseek.exe`（源码改动不生效），需将修复后构建的引擎二进制复制进 dist 并重启桌面 app。实测确认问题解决。

---

## 5. 结论与经验

1. **真正的根因**：shell 工具 spawn 子进程时未显式传 stdin，导致子进程继承引擎的 stdin 管道句柄；该管道写端被桌面 host 长期保持打开（用于发送命令），形成"写端永不关闭的共享管道"，git（MSYS2 运行时）挂起直至超时。

2. **第一轮修复为何无效**：`desktop/lepus/sys/process` 不是 shell 工具的 spawn 路径；shell 工具走 `moonbitlang/async/process`。修改了一个不相关的模块。

3. **经验教训**：
   - 定位"哪个模块真的被执行"先于"这个模块哪里错了"——本案例因未先确认 spawn 路径，浪费了一轮修复；
   - 独立进程探针通过不代表引擎场景通过——**必须在与生产环境完全一致的进程树/句柄拓扑下复现**；
   - Windows 下"stdin 继承"是隐蔽陷阱：`GetStdHandle(STD_INPUT_HANDLE)` 回退会把父进程的管道读端传给孙进程，写端生命周期由更上层决定；
   - 对照实验的价值：把 `no_console_window`、stdin 写端、继承方式拆开逐一验证，才从"看起来都有关"收敛到唯一决定变量。

4. **遗留**：引擎级复现工具保留在 `C:\Users\17376\AppData\Local\Temp\opencode\engprobe\`（含 gitprobe 对照探针），可用于后续 Windows 子进程行为验证。

---

## 6. 沉淀到项目的回归测试

排查中形成的验证思想已固化为自动化测试，防止此问题回归：

### 6.1 `agent_tool/shell/shell_test.mbt`

| 测试 | 平台 | 验证思想 |
|------|------|----------|
| `shell child sees an immediately-closed stdin pipe on Windows` | Windows | 子进程探针 `[Console]::IsInputRedirected` + `ReadToEnd()`：显式传 stdin 管道时 IsInputRedirected=True，写端关闭时 ReadToEnd 立即返回 0。若继承引擎的 host-held 管道则阻塞/返回 NOT-REDIRECTED → 测试失败 |
| `shell child sees an immediately-closed stdin pipe on Unix` | Unix | 探针 `wc -c`：关闭管道立即读到 EOF 输出 0；继承终端/打开管道则阻塞直到工具超时 |
| `shell runs git --version on Windows` | Windows | 直接复刻用户报告的原始症状（git 探 stdin 挂起）；git 未安装时跳过 |

### 6.2 `agent_tool/shell_exec/execution.mbt`

| 测试 | 平台 | 验证思想 |
|------|------|----------|
| `execution child sees an immediately-closed stdin pipe on Windows` | Windows | 覆盖 `ShellExecution::start` 这一第二条 spawn 路径，同样的 IsInputRedirected+ReadToEnd 探针 |

### 6.3 核心断言

三条测试共享的断言模式：**探针在有限超时内返回 + 输出为预期 EOF 特征值**。把"子进程 stdin 必须是写端立即关闭的独立管道"这一契约固化为行为测试，而不是测试内部实现细节——即使将来 spawn 库换了（如不再 fallback 到 `GetStdHandle`），测试依然有效。

运行方式：`moon test agent_tool/shell agent_tool/shell_exec --target native`（Windows 平台下 3 条新测试均执行）。