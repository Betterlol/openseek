# OpenSeek 调研报告 04：Agent 主循环与运行时

> 范围：`agent/`、`agent_runtime/`
> 代码量：生产约 3,350 行 + 测试约 4,000 行（agent）；生产 253 行（agent_runtime）

## 1. `agent_runtime/` — 双通道运行时（253 行）

```
pub(all) enum SteerInput { Prompt(String) | Command(String) | Notice(String) }
pub(all) extenum AgentEvent {}        // 开放事件类型，工具包可扩展
pub struct AgentRuntime { priv workspace_root; priv events: Queue[AgentEvent]; priv steers: Queue[SteerInput] }
pub struct[X] AgentTaskScope[X] { priv group: TaskGroup[X] }   // 结构化并发能力对象
```

### 1.1 核心设计

- **双通道分离**：有损事件总线（`DiscardOldest` 容量 32，`try_put` 失败即丢，exports.mbt:16）与**无界无损** steer 队列分离（runtime.mbt:48-51）——steer（用户 steer/命令输入）永不被事件洪水冲掉，测试"steering input survives an event-bus flood"（:185）钉死了该语义；
- `AgentEvent` 用 `extenum` 使工具包可加事件而 runtime 不依赖工具——开闭原则；
- `AgentTaskScope` 仅包装 `TaskGroup`，是结构化并发的能力对象；
- 构造函数**不**规范化 workspace_root（:57-59 文档化）——依赖上游。

### 1.2 已知不足

- `queue_steer` 吞掉 put 错误（静默）；
- `drain_queue` 将队列关闭视为"无更多项"，异常静默。

## 2. `agent/` — 单 turn 状态机

### 2.1 核心类型与入口

```
struct AgentLoop {   // 全部 priv
  runtime: AgentRuntime; client: Client; summary_client: Client
  tools: Tools; append_item: async (Session, SessionItem) -> Session
  messages: Array[ChatMessage]    // turn 本地请求缓冲
  plan_cadence: PlanCadence; goal_cadence: GoalCadence
  on_goal_met: (async (String, GoalBaseline?) -> String?)?   // goal 审查门
  mut last_session: Session
}
enum FinishOutcome { Sealed(Session) | ContinueTurn(Session) }
enum AgentStepOutcome { StepContinue(Session) | StepDone(Session) | StepYield(Session) }
pub async fn run_turn_with_append(...)                  // agent.mbt:118
pub async fn[X] run_turn_in_scope(runtime~, scope~, ...) // agent.mbt:229
pub async fn[X] build_tools(runtime, scope, on_background_wake?, extra_tools?) // tool_definition.mbt:124
```

### 2.2 Step 主循环（`turn_loop.mbt`，1,296 行）

```
AgentLoop::run（:130）
 ├─ prepare_step（:389）：drain steers → 跑 pending review → 注入 goal/plan 提醒
 ├─ client.chat（每 step 一轮 provider 调用）
 ├─ 无工具调用 → goal-check → finish 链
 ├─ 有工具调用 → handle_tool_calls（:456）
 │    ├─ 相邻 concurrent_safe 调用分组并发执行（spawn_bg，:579）
 │    ├─ goal 工具被 loop 拦截（:656 handle_goal_tool_call）
 │    └─ salvage_control_calls_at_ceiling（:854）
 └─ 出口三态：StepContinue / StepDone / StepYield
```

### 2.3 关键机制

1. **上下文预算三层防护**（auto_compact.mbt，详见报告 01）：
   - 70% 软 / 80% 硬 ceiling；
   - `next_call_fits`（:86）每次调用前做运行中预算检查（实际尺寸 + 最坏结果 + 16,384 token checkpoint 预留）；
   - `checkpoint_at_ceiling`（:118）用 `summary_client`（thinking=No）生成摘要，摘要**生成**失败 fail-open、append 失败照常传播。
2. **控制工具抢救**（`salvage_control_calls_at_ceiling`，turn_loop.mbt:854）：ceiling 下仅放行 `is_control()` 声明的工具（finish/goal），其余 skip-close。
3. **goal 状态机**（goal.mbt）：`met` 置 pending_tombstone、`blocked`/`continuing` 走 PendingBlockTransition，均在批次边界 `flush_goal_tombstone`（goal.mbt:275）落盘——避免 mid-batch 通知干扰回放；`on_goal_met` 审查门（:1021）失败退化为 `[review] unavailable` 通知，绝不断 turn。
4. **steer-beats-finish**：finish 在飞时用户输入到达 → 答案降级为普通 assistant 消息并继续 turn（:721, :1213）。
5. **并发预取**：相邻 concurrent_safe 调用分组并发执行，但 durable session 与顺序执行字节一致，仅 live 事件流顺序不同（:576-578 自述）。
6. **cadence 提醒**：`PlanCadence`（plan 提醒节奏）与 `GoalCadence`（goal 提醒 + finish 检查 + 审查）跟踪工具注册时机与静默步数。

### 2.4 已知不足

- **`turn_loop.mbt` 单文件 1,296 行**承载全部状态机分支，可读性/可维护性压力大；
- `messages` 缓冲与 durable session 的锁步不变量靠注释维系（:10-14），无类型化保证；
- prefetch 并发使 live 事件与落盘顺序分离，靠 id 配对——是刻意的折衷，但增加消费者心智负担；
- `clamp_tool_result_content` 60K 上限与工具内 12K/50K 自限是隐式契约（:951），散落各处。

## 3. 跨层观察

1. 主循环的全部状态都收敛在 `Session`（持久真相）与 `messages`（turn 缓冲）两个数据结构上，架构简单但锁步不变量脆弱；
2. 上下文预算体系是本库最精巧的部分：不是"估计"而是"实际尺寸 + 最坏情况"的运行中检查，配合控制工具抢救，把"上下文天花板"从硬错误变成了优雅降级；
3. 测试覆盖极高（goal_gate/goal_check/plan_reminder/auto_compact/steer/concurrent 各有专项测试），但 1,296 行状态机仍靠人工测试拼凑覆盖，缺少基于状态的生成式测试；
4. `agent_runtime` 小而稳，双通道设计值得借鉴——有损事件 + 无损控制通道是事件驱动系统的通用模式。
