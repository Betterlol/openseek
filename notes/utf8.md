`agent_tool/shell/shell.mbt`

```md
let output = agent_shell_output_from_exec(exec, launch)

`When a wired foreground command emits one malformed byte before completing, wait_or_invalid() returns immediately and this call cancels the still-running child. The new path then renders exit_code=None as exit 0/non-error, so a command such as printf '\377'; sleep 1; touch marker is reported as a lossy success even though touch marker never executes. To degrade output without changing command semantics, wait for normal completion (subject to the existing timeout/output limits) rather than stopping on the first invalid byte.`

```

*解释*:
```md
之前的行为是：
`exec.stop() → Killed → ShellBinaryOutput → 硬错误（is_error=true）`
子进程被杀了，但反正报的是硬错误，exit code 没人关心，没问题。
我的 commit 改成了：
exec.stop() → Killed → ShellExecuted → exit_code=None → unwrap_or(0) → exit=0 → is_error=false
你把输出从硬错误降级为 lossy 文本（这是正确的方向），但保留了 exec.stop()，结果 None 被 unwrap_or(0) 吞成了 exit 0。这是 exec.stop() 和新的 ShellExecuted 路径之间不匹配导致的——之前 ShellBinaryOutput 根本不走 shell_response，所以 None 从来没被渲染成 exit 0。
所以 bug 是你改代码时引入的，但这是非常合理的遗漏——原来的 exec.stop() 一直就在那里，之前没人发现它有问题，因为它藏在硬错误路径后面。你改 lossy 降级时没注意到 exec.stop() 需要同步改成 exec.wait()，很正常的疏忽。
```

```md
@utf8.decode_lossy(bytes) 

`On Windows, where the agent deliberately uses the unwired collection path, a short command with malformed output still reaches the None/EOF branch and is strictly decoded by @utf8.decode(buffer.to_bytes()), raising the same Malformed error as before. This lossy fallback is only used while checking an intermediate prefix, so [Console]::OpenStandardOutput().WriteByte(255) never receives the promised lossy text or encoding warning; the final buffer must also be decoded lossily while preserving whether invalid bytes were seen. `
```


*当初实现为这样的目的（3db598e7）*

把二进制输出从硬错误（`ShellBinaryOutput` → 直接返回 "Malformed" tool error）降级为 lossy 文本 + encoding warning，让模型能看到部分输出而不是盲区。当时保留了 `exec.stop()` 的逻辑——检测到非法 UTF-8 时仍然立即杀死子进程——因为语义是"尽快报错，不等命令结束"。`decode_valid_utf8_prefix` 的 fallback 从 `@utf8.decode(bytes)`（抛异常）改为 `@utf8.decode_lossy(bytes)`（不抛），但 EOF 分支的 `@utf8.decode(buffer.to_bytes())` 被遗漏了，没有同步改为 lossy。

```md

2. binary output 改为 lossy text

这是最大争议点。

原逻辑：

invalid UTF8
    ↓
ShellBinaryOutput
    ↓
tool error

现在：

invalid UTF8
    ↓
decode_lossy
    ↓
返回文本 + warning

优点

用户体验明显提升。

以前：

cat file.bin


error:
Malformed binary output

模型完全不知道发生什么。

现在：

���
<system>
encoding=lossy
</system>

模型至少知道：

有输出
输出损坏
可以决定下一步

这个设计符合 agent tool 思路。

但是存在一个工程风险
binary 数据被伪装成文本

例如：

cat image.png

以前：

错误

现在：

PNG乱码...
encoding=lossy

模型可能误认为：

"这是文件内容"

而不是：

"这是二进制流"

尤其：

base64检测
文件分析
自动修复任务

可能产生误判。

建议

不要完全删除 binary 状态。

更好的设计：

ShellBinaryOutput
        |
        +--> text preview
        |
        +--> binary metadata

例如：

Output contains non UTF-8 bytes.


Preview:
xxxxxx


bytes:
1024


encoding=lossy

比现在安全。
```

*现在的修复的目的*

解决两个遗留问题：
1. `exec.stop()` 杀死子进程导致 exit_code=None → 被渲染为 exit 0，`&&` 链中后续命令被静默跳过。改为 `exec.wait()` 让子进程正常结束，保留真实 exit code。
2. EOF 分支的 `@utf8.decode(buffer.to_bytes())` 严格解码与 `Some(chunk)` 分支的 `decode_valid_utf8_prefix()` 不一致，短命令输出非法字节仍然抛 `Malformed`。改为 `decode_valid_utf8_prefix()` 保持行为一致。

*details*

