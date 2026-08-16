# OpenSeek 调研报告 03：Agent 会话与持久化

> 范围：`agent_session/`（含 `store/`、`log/`、`compact/`）
> 代码量：生产约 2,700 行 + 测试约 2,500 行

## 1. 核心模型（`types.mbt`，607 行）

```
pub struct Session { priv id: SessionId; priv system_prompt: String
  priv events: Vector[SessionEvent]; priv last_sequence: Int }   // 不可变
pub(all) enum SessionItem { User | Assistant | Tool | Runtime | Summary | Terminal }
pub fn Session::append(self, item, unix_ms?) -> Session          // 返回新值，共享 Vector
pub fn Session::chat_messages(self) -> Array[ChatMessage]        // projection.mbt:133
pub fn Session::compact(self, content~, from_sequence~, to_sequence~) -> Session raise
pub fn Session::current_goal(self) -> StandingGoal?
```

设计要点：

- **Session 不可变**：append 返回新 Session，内部 Vector 结构共享（copy-on-write 风格），天然线程安全；
- **事件带单调序号**（`last_sequence`），回放假设序号严格递增；
- **摘要不删原始事件**（append-only）：compaction 只追加一条 `Summary` 事件，投影时覆盖被覆盖区间的事件——这是"日志不可变"与"上下文有限"的统一；
- **context-yield 终端**复用 `Terminal(Finished)` + `ContextYieldAnswerPrefix` 前缀，避免破坏旧读者。

## 2. JSON 往返（`json.mbt`）

- 版本 1 快照；`{kind, payload}` 标签联合（:111）；Terminal 为 `{kind, message}`；
- **未知 kind/版本严格报错**（:101, :149）——拒绝静默升级；
- 已知不足：
  - `json.mbt:39` `Number.to_int()` 对 1.5 静默截断（与 deepseek 层同一问题）；
  - Session FromJson 缺 `events` 容忍为空（:207），可能掩盖损坏。

## 3. store — 文件系统持久化（`store.mbt`，765 行）

### 3.1 布局与并发控制

```
root/sessions/<id>/openseek_session-<id>.jsonl   # header 行 + 每事件一行 JSONL
                     /session.lock
```

- `validate_session_id`（:71）拒绝 `/`、`\`、NUL、`.`、`..`——防路径穿越；
- `SessionStore::append`（:717）**排他锁** + `ensure_session_is_current`（:296）：指纹（size/mtime/ctime，:50）fast path 跳过全量比对，常规追加 O(1)/append；
- **常规追加**：O_APPEND + fdatasync（:355-361）；
- **首写/撕裂尾部**：temp + rename + 目录链 sync 原子重写（:384）；
- **撕裂尾部容忍**（`needs_tail_repair`，:163-235）只限**末行**——多进程并发写同一 session 时，尾部撕裂可自愈。

### 3.2 可靠性设计亮点

- 指纹快路径 + 全量比对慢路径的组合，让"stale snapshot"检测既有 O(1) 快路径又有全量兜底；
- 原子重写走目录 sync，保证崩溃后 rename 已持久化；
- 尾部撕裂容忍把"崩溃窗口"缩到只有最后一行。

### 3.3 已知不足

- `write_text_atomic` 的 `.tmp` 文件在 rename 失败时不清理（残留垃圾）；
- `parse_session_file` 无行数上限、全量 split 解码（大会话读入开销 O(会话大小) × 每行解析）。

## 4. log — 宽容读取器（94 行）

- `SessionFileHeader{id, system_prompt}` + `classify_header`（:48）区分 UnsupportedVersion/NotHeader；
- **宽容**：按行读取、逐行捕获错误，单行损坏不影响整文件——与 store 的严格写入形成互补（写严读宽）；
- 被 `viz`、`inspect`、`eval/session_analyzer` 等只读消费者使用。

## 5. compact — 上下文检查点（106 行）

- `generate_compaction_summary`（:47）：替换系统提示为 `CompactionSystemPrompt`（**防摘要器输出工具调用标记**——防止模型在摘要里生成 `<tool_call>` 之类语法），追加 `CompactionUserPrompt`；
- 空摘要 fail（不接受空压缩结果）；
- 摘要失败在 `agent/auto_compact.mbt` 是 fail-open 的（只有摘要**生成**失败容错，append 失败照常传播）。

## 6. 投影（`projection.mbt`）

`chat_messages` 把 Session 事件流投影成 DeepSeek chat 消息数组：处理 Tool 消息的 tool_call_id 配对、Summary 覆盖区间、goal/plan 提醒注入等。

### 6.1 已知不足：**O(n²) 投影**

`projection.mbt:145-152` 存在双重嵌套扫描——每事件全量扫描找 summary 覆盖。长会话（数千事件）下，每个 step 都要做一次 `chat_messages`，会累积成显著的性能问题。这是本库最明确的性能短板之一。

## 7. goal 状态机（`goal.mbt`，约 200 行）

- `current_goal` 从原始日志扫描（summary 覆盖 set marker 时视为"已作答"重新提醒，goal.mbt:134）；
- `current_goal_baseline` 靠"前一条即 baseline"的位置配对——文档自承双重 store 故障下的残余风险（goal.mbt:225-230）。

## 8. 跨层观察

1. **写严读宽的持久化哲学**：store（引擎专用，严格、原子、加锁）与 log（消费者专用，宽容、逐行容错）分工明确；
2. **不可变 Session + append-only 事件**使重放、viz、eval 分析共享同一真相源；
3. 主要风险点：O(n²) 投影、浮点截断、tmp 文件清理、goal baseline 位置配对；
4. 值得注意：append 是全链路的承重墙（agent 主循环每 step 至少一次 append），store 的 O(1)/append 快路径是刻意为之的性能投资。
