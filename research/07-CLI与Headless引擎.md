# OpenSeek 调研报告 07：CLI 与 Headless 引擎

> 范围：`cmd/openseek/`（12 文件 7,766 行，含 `internal/subtask/` 2,138 行）、`internal/`、`agent_subrun/`
> 命令树：`tui`（默认）/ `run` / `serve` / `review` / `subrun` / `mcp` / `sessions`

## 1. 入口与命令树（`main.mbt`，2,058 行）

- 单 argparse 命令树；裸 `openseek` 重解析为 `["tui", ..argv]`（:24-51）；
- `with_jsonl_stdout`（:90）是 **JSONL 流式协议的承重墙**：`@xlog` Handler 是同步的而 `@stdio.stdout` 是异步的，`FlushedStdout` 把日志行入队、`drain()` 后台任务顺序写出，`defer close()` 保证失败路径不丢终态事件；
- `configure_logging()`（logging.mbt:69-79）强制 `set_level(Info)`——防 `MOON_XLOG=warn` 吞掉协议事件；
- `random_salt()`（main.mbt:491）用 `mkdtemp` 的内核随机后缀做盐（异步运行时读不了 `/dev/urandom`），并过滤非字母数字；
- **prompt 组装顺序**刻意把环境段放最后以命中 DeepSeek 前缀上下文缓存（:1093-1118）；
- `self_executable()`（subrun.mbt:327）：父子必须同一二进制，否则 typed report 编解码漂移。

## 2. serve 模式状态机（`serve.mbt`，1,230 行）

```
ServeStep 枚举（Wire/TurnDone/CompactDone/BackgroundNotice/Shutdown）
    所有事件 funnel 进 @async.Queue
serve~: 单消费者 for 循环逐一处理
    active_work（ActiveTurn/ActiveCompact）唯一模式状态 + pending 队列
```

- **JSONL 命令协议**：stdin 读 `@protocol.Command`（prompt/steer/compact/cancel/goal），stdout 发 `@protocol.Event`；
- `decode_serve_command`（:155）协议→内部命令映射，`GoalSet` 空白文本拒绝；
- **goal auto-continue 的 promotion 机制**（serve.mbt:41）："pending intent → 持久化 marker 后 promotion"，`goal_command_serial` 单调序号防旧命令超车——防 append 失败却武装了自动循环；
- 取消只中断 active work 不杀进程；stdin EOF 是关停信号；
- 不足：`pending.remove(0)` O(n)；`run_subrun` 中 `steps.try_put(...) |> ignore` 的队列关闭竞态被文档化接受。

## 3. subtask — 多仓库并行子任务（`internal/subtask/`，2,138 行）

git worktree 为基础的并行任务系统，含完整的生命周期与证据链：

- **provision.mbt（340）**：`repo_mutexes`（进程内 Map，按 common git dir 键控）互斥事务——保留区检查（名字/路径重叠）→ 钉住 base_oid → 拒绝 submodule slice → 写 `.worktrees/` 到 info/exclude → **先落 Provisioning 状态 registry 条目再建 worktree**（崩溃可发现）→ 解析私有 admin dir；
- **capture.mbt（202）**：只信 git 证据——`add -A` → `write-tree` 钉住不可变 tree → **对 tree object 做 scope 校验**（防迟到 worker 进程塞入未验证路径）→ `commit-tree` + `update-ref`（无 hooks）；
- **integrate.mbt（442）**：用**后置条件**（MERGE_HEAD、unmerged 条目、HEAD 位移）而非退出码分类结果（:153-222）；
- **scope.mbt（171）**：手写 `git status -z`/`diff --name-status -z` 解析器（rename 双方都要在 scope 内）；
- **gitrun.mbt（64）**：环境白名单只传 `PATH`/`HOME`，丢弃可能带恶意的 `GIT_DIR` 等；
- **geometry.mbt（110）**：路径几何计算。

不足：

- `copy_mooncakes`（provision.mbt:281）shell 出 `cp -R`——Windows 无 `cp`，静默失败（仅日志）；
- `lifecycle_test.mbt`（588 行真实 git 仓库 e2e）对 integrate 的"foreign merge 保护"等路径覆盖不足（如 `merge --abort` 后状态回写无断言）。

## 4. subrun 模式与 `agent_subrun/`（约 1,500 行）

### 4.1 核心类型

```
pub enum SubrunTerminal { Captured | NoReport | MaxSteps | ContextYield | TimedOut | Failed }
pub struct SubrunResult[T] { value/terminal/steps_used/prompt_tokens/completion_tokens/subrun_id }
pub async fn run_subrun[T](command~, args~, input~, parse_report~, wall_deadline_ms~, kind~, label~,
                           cwd?, child_session?, emit_event?) -> SubrunResult[T]   // runner.mbt:146
pub struct SubrunBudget { max_calls_per_turn=10, used_calls }                      // budget.mbt:30
```

### 4.2 机制

- 父写一行 JSON 到子 stdin 并**保持管道打开**（EOF=优雅取消信号）；
- `with_timeout_opt(wall_deadline_ms)` 后先关 stdin 给 5s grace（`cancel_grace_ms`），报告在 grace 内仍有效，再 `process.cancel()`；
- `ChildObservations::observe` 从子 stdout 的 xlog 事件流中累加 `usage`（**精确计费**）、max(`agent_step`)、识别 max_steps_exhausted/context_yield/失败事件；
- 最后一行 `{"subrun_report": ...}` 是**类型化通道**（父子同一二进制，派生编解码不漂移，child.mbt:59-66）；
- `SubrunStarted/SubrunFinished` 生命周期括号在取消路径上也先发再 re-raise（runner.mbt:308-313）；
- **预算策略**：每轮调用次数上限而非步数池——文档记录步数池会饿死后调用的子进程的真实教训（budget.mbt:14-21）；
- `child_session` 使子会话持久化为 `<parent>-sr-N` 兄弟会话，`first_free` 防 resume 后复用旧 id（runner.mbt:161-171）。

### 4.3 不足

- 干净 EOF 后仍无条件 `process.cancel()`（依赖 `@process` 幂等性，runner.mbt:303-305）；
- `min_useful_subrun_steps=8` 魔法数；
- spawn 异步失败（EAGAIN）靠 group 出口兜底 catch（:199-204）——脆弱点被注释识别但依赖运行时行为。

## 5. 其他子命令

- **`run_fleet`**（concurrent.mbt，609 行）：best-of-N 并行；`copy_tree`（:244）跳过 `_build`/`node_modules`/session 存储，`.git` 文件（worktree 指针）不复制以防污染原仓库——文档化的权衡；
- **review 模式**（review.mbt，79 行）：固定 `Deepseek(V4Pro)`（:25），**`--model` 被静默忽略**（有注释但用户易困惑）；
- **mcp 子命令**（mcp.mbt，215 行）：仅校验配置；`terminal_safe_line`（:151）防终端转义注入。

## 6. `internal/`

- `internal/cli/cli.mbt`（31 行）：唯一 `parse_positive_int` 共享访问器——从各 main 提取的去重（有测试）；
- `internal/workspace_path/workspace_path.mbt`（159 行）：词法路径工具；`is_under_workspace_root` 不解析 `.`/`..`/symlink（注释承认，调用方需先 normalize）——潜在越界检查盲区，依赖调用方自律。

## 7. 已知不足汇总

1. **三份重复的转义清洗循环**：`compact_prompt_label`（main.mbt:918）、`terminal_safe_line`（mcp.mbt:151）、`mcp_safe`（cmd/tui/internal/event/decode.mbt:147）是同一逻辑的三份拷贝；
2. **`self_executable()` 与 TUI 的 tcc 调试路径不对称**：TUI 对 Moon `tcc -run` 用 rspfile 重新进入（cmd/tui/main.mbt:319-326），但引擎侧对 `.c` argv0 只回落 PATH 找 `openseek`（subrun.mbt:336-338）——调试路径下子进程 spawn 会失败；
3. review 模式硬编码 V4Pro 静默忽略 `--model`；
4. `copy_mooncakes` 用 `cp -R` 有 Windows 缺口；
5. `serve.mbt` pending 队列 O(n) remove。

## 8. 跨层观察

1. `with_jsonl_stdout` + `configure_logging` 这对组合解决了"同步日志 vs 异步 stdout + 用户环境变量干扰协议"两个实际问题，是嵌入式协议输出层的范式；
2. subtask 的证据式 git 操作（write-tree 钉快照、postcondition 分类、-z 解析器）代表了"以 git 原生证据为准，不用 shell 文本"的工程品味；
3. agent_subrun 的"EOF=取消 + grace + 类型化终行 + 精确计费"是完整的子进程协议，同时被 subrun CLI、review 引擎、worker/explore 子代理复用——一处实现多处受益；
4. 平台缺口（Windows cp/pwsh）与调试路径不对称是真实项目留债的典型样例——都有文档注释，但无测试钉死。
