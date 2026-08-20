## 问题根因

一个三层进程的 stdin 句柄继承链：

1. **桌面 host** 以 `stdin=管道` 方式启动引擎，且**管道写端在整个会话期间保持打开**（host 要靠它给引擎发 prompt 命令）——这是正常的、有意的。
2. **引擎**内部 spawn powershell/git 时**没有传 stdin**（`shell.mbt:734`、`execution.mbt:92` 原来都是 `spawn(..., stdout, stderr, ...)`，缺 `stdin`）。
3. `moonbitlang/async/process` 的 Windows 实现里，未传 stdin 时回退到 `GetStdHandle(STD_INPUT_HANDLE)`（thread_pool.c ~866-895 行）——即**继承引擎自己的 stdin**，也就是 host 那条管道。

结果：git（MSYS2 运行时）继承了一个**永远不会有 EOF 的管道读端**（写端在 host 手里，会话结束前不关），于是 git 探查/读取 stdin 时挂起 → 120s 超时。变量分离实验证明：**只有"stdin 写端保持打开"这一个变量决定卡死与否**，与 `no_console_window`、env 无关。

## 修复是否可解释、有无风险

改动：两个 spawn 点各加 3 行——创建独立 stdin 管道，**写端立即关闭**，把读端传给子进程。子进程从此拿到"自己的、立即 EOF 的空 stdin"。

**可解释性**：完全符合预期语义。shell 工具的参数只有 `cmd/cwd/timeout_ms/max_output_chars`，**从来没有向子进程写 stdin 的通道**——子进程读 stdin 本来就是"意外继承"而非"有意设计"，现在变成干净的 EOF。

**风险评估**：

| 关注点 | 结论 |
|---|---|
| 依赖读 stdin 的命令（`git commit -F -`、`vim` 等） | 此前继承的也是 host 命令管道而非终端，本就不可用/危险；现在得到空 EOF，行为更符合预期，无回退 |
| 交互式命令 | 引擎环境无 tty，此前也不可用，无变化 |
| 性能 | 每次 spawn 多一对管道句柄，可忽略 |
| 其他 spawn 点 | `agent_subrun`/`mcp/stdio`/`tui` 均已显式传 stdin，无同类问题 |
| 接口 | `.mbti` 无内容变化，纯内部修复 |
| 测试 | 新增 3 条回归测试通过，16 个失败为预存环境问题（stash 基线对比过） |

唯一需要留意的边界：**将来若给 shell 工具加"向子进程写输入"的功能，必须显式传 stdin 参数**，不能依赖继承——这一点已写进测试注释和记录文档。第一轮对 lepus 的盲改不在此路径上、已 revert，无遗留。