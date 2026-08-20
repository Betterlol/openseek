# OpenSeek 调研报告 06：MCP 集成

> 范围：`mcp/`（含 `config/`、`stdio/`、`streamhttp/`、`tools/`）
> 依赖链：mcp→jsonrpc；stdio→jsonrpc+mcp+async/process；streamhttp→jsonrpc+mcp+async/http+utf8；tools→mcp/{config,stdio,streamhttp}+agent_tool+agent_runtime+protocol+protocol/emit

## 1. 整体架构

```
mcp.json ──config──> McpServer{Stdio|Http}
                         │
              ┌──────────┴──────────┐
         stdio/connect       streamhttp/connect
         （子进程+NDJSON）      （每消息一个 POST）
              └──────────┬──────────┘
                      jsonrpc.Client（复用）
                         │
              McpClient（initialize/初始化协商/list_tools 分页/call_tool）
                         │
              tools/（bridge_tool：命名空间化 + 消毒 + 截断防护）
                         │
              agent_tool 注册表（mcp__<server>__<tool>）
```

## 2. MCP 客户端层（`client.mbt`，105 行）

- `McpClient` 包一层 `@jsonrpc.Client`——复用双常驻任务架构；
- `initialize`（:44-68）声明 `protocolVersion: "2025-11-25"`、空 capabilities；协商结果须在 `is_supported_version` 集合内（2025-11-25/2025-06-18/2025-03-26/2024-11-05，:16-23），然后发 `notifications/initialized`；
- `list_tools` 跟随 `nextCursor` 分页循环（:74-91）；
- `call_tool`（:97-105）返回 `CallToolResult`。
- `types.mbt`（223 行）：`McpTool/McpToolError/ContentBlock{Text,Image(mime),Resource(uri,text?),Other}/InitializeResult` 及手写解码器；`CallToolResult::render_text`（:175-211）把非文本块渲染成占位符、`structuredContent` 不丢（去重判断 `text.contains(serialized)`）。

## 3. config（`config.mbt`，128 行）

- 解码 Claude 风格 `{"mcpServers": {name: {command|url, args?, env?/headers?}}}`（:46-55）；
- `McpServer { Stdio(name,command,args,env); Http(name,url,headers) }`；
- "字段存在但类型错"视为配置错误而非省略（:69-82）——严格；
- `decode_string_map`（:109-128）统一了 env/headers 两处重复逻辑。

## 4. stdio 传输（`stdio/`，connect 166 + ndjson 64）

- `@process.write_to_process/read_from_process/spawn` 建子进程（`no_wait=true`，组 teardown 时终止）；
- `NdjsonTransport`：`send` 一行 `stringify()+"\n"`，`recv` 逐行读、**跳过非 JSON 行**（容忍服务器泄漏的日志）、非法 UTF-8 返回 None 关闭连接；
- teardown 幂等（Ref[Bool] 守卫）且**取消任务才是唤醒挂起 read 的手段**（connect.mbt:98-103 注释）；
- 握手 30s 超时，任何失败路径都 teardown 防泄漏。

## 5. Streamable HTTP 传输（`streamhttp/transport.mbt`，592 行——全库最复杂的一块）

核心机制：

1. **每消息一个独立 POST**：`send` 只派发任务即返回（:163-232），入站消息来自 POST 响应（单个 JSON 体或 SSE 流），进 `inbound` 队列供 reader 消费；
2. **并发上限** `MaxInFlightExchanges=32`（:28）：超限时对请求合成 -32000 错误、对通知丢弃；
3. **单 POST 总时限** `ExchangeTimeoutMs=150s`；
4. **`initialized_gate`**（:57-61, 191-199）：`notifications/initialized` 的 POST 完成前，后续 POST 一律在任务体内 `gate.get()` 排队——保证生命周期顺序；
5. **`initialize_id` 快照**（:65-68, 582-590）：从 initialize 回复捕获协商版本，后续请求带 `MCP-Protocol-Version` 头；
6. **session id** 只在 initialize 响应捕获（:387-391），后续请求带 `Mcp-Session-Id`；
7. **close 时 best-effort DELETE**（5s 限时，:260-281）释放会话；
8. **SseLineReader**（:473-545）：支持 LF/CRLF/孤立 CR 三种终止符（防 CR-only 流被 `read_until("\n")` 卡死），4096 字节滑动压缩，严格 UTF-8 解码；
9. **应答即断流**（:443-445）：应答送达后主动断开 SSE——防服务器不关流占住配额；
10. **`deliver_error`**（:567-577）：POST 失败/超时/未应答时合成 -32000 错误快速失败。

未实现 standing GET 流与 SSE 断点续传（模块注释 14-20 行声明）。

## 6. 工具桥接（`tools.mbt`，343 行）

- `build/build_grouped` 逐服务器 `connect_server`（stdio 以 `workspace_root` 为 cwd，:197-206）→ `tools_for_client`（去重同名原始工具）→ `bridge_tool`（:253-284）命名空间化 `mcp__<server>__<tool>`；
- **名称消毒**：字符消毒 + 64 字符截断；跨服务器消毒冲突用 `uniquify` 加 `-N` 后缀（:71-83）；
- **全局预算** `MaxTotalMcpTools=100`（:36，服务端 128 上限留余量给内置工具）；
- **四重截断防护**：描述 1KB、schema 16KB（超限降级为 `{"type":"object"}`）、调用结果 50KB（附 `<system>truncated=true…` 标记）、单次调用 120s 超时（:8-31）；
- **失败不阻断**：服务器启动/握手/list 失败只记日志（`McpConnectFailed` 等事件）跳过，MCP 永不破坏会话；空工具服务器立即 shutdown（:244-247）。

## 7. 已知不足

| 问题 | 位置 | 说明 |
| --- | --- | --- |
| "按配置顺序分组"存疑 | `tools.mbt` | `decode` 遍历 `Object(servers)` 的 Map——若 MoonBit Map 迭代非插入序，顺序承诺与后缀分配（谁保留原名）不确定 |
| list_tools 分页无迭代上限 | `client.mbt:74-91` | 恶意服务器靠无限 cursor 拖时间（外层有 discovery 超时兜底） |
| stdio 杀进程不杀孙进程 | `connect.mbt:101-104` | `process.cancel()` 只杀直接子进程，`npx` 类 fork 型启动器可能遗留孙进程（自述） |
| headers 无脱敏/告警 | `config` | `mcp.json` 的 `headers`（如 Authorization）原样透传，HTTP URL 无 scheme 校验 |
| 长会话连接不回收 | `tools.mbt` | 成功服务器的连接在 scope 结束前从不主动关闭，长会话累积进程/连接 |
| close 时 DELETE 会被取消 | `streamhttp` | 组 teardown 期间 spawn 的 DELETE 可能被取消，会话靠服务端过期 |

## 8. 跨层观察

1. Streamable HTTP 传输层是全书并发正确性最密集的代码之一：initialized_gate + initialize_id 快照 + 应答即断流，每一处都在处理"协议生命周期 vs 并发"的边界；
2. 安全防护（名称消毒、四重截断、预算上限、失败不阻断）与 MCP 规范（版本协商、分页、session 头）并重，是"生产级 MCP 客户端"的成熟度；
3. 不足集中在两类：**理论边界**（Map 顺序、id 精度、分页上限）与**资源回收**（孙进程、长连接、DELETE 被取消）；
4. 与 README 一致：Resources/Prompts 两种 MCP 能力刻意不消费——tool-driven 设计，保持表面积小。
