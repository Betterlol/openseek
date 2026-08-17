## `cmd/tui/` 文件夹内

### 命令逻辑（后端）
`main.mbt`: `slash_commands` 数组为命令注册表，每条命令 name+description 驱动补全菜单。
1. /exit
2. /compact
3. /loop : 
4. /goal
`loop.mbt`: `handle_slash_command` 是分发入口，分别转发各个命令注册表中的命令
`loop.mbt`, `goal.mbt`, `scheduler.mbt` 分别有不同命令的处理器函数。
1. `handle_compact_command`
2. `handle_goal_command`
3. `handle_loop_command`
> 目前 ` /exit` 等命令不会变识别，即前面有空格的话不被识别为命令，后续可以考虑改成 trim 后再识别，不过这个其实无伤大雅。
> 目前命令是带参数的，但是补全没有跟上（命令参数列表），这不太好上手...，感觉起来是参考了 `codex` 的实现，以为 `codex` 也是有 `/goal` 而且有参数，参数还没有提示....
>> 比如 `/goal` 之后出现列表：
>>> `set <goal_name> <goal_value>`
>>> `clear`
>> 然后对于非命令名的参数，用 `placeholder` 来提示用户输入参数：
>>> 输入 `/btw` 后输入栏：`/btw <question>`
>>> 输入 `/background` 后输入栏：`/background <prompt>`
>>> 输入 `/loop` 后输入栏：`/loop <interval> <prompt>`
> 另一个可参考的方案：`opencode` 中命令都是无参数，它们使用 `打开窗体` 的方式来实现 `命令参数` 的输入。比如 `/models` 命令会打开一个窗体，窗体中有一个下拉框，用户选择模型后点击确认，窗体关闭后命令参数就被传入了。
> 通常这两种方式会结合起来
> 无参数命令：`/models`, `/sessions | /resume` 都是执行后打开窗体或列表栏
> 有参数命令：`/goal`, `/background`, `/btw` 都是执行后在输入栏中提示用户输入参数 



### 命令机制（输入/补全/配置等前端逻辑）
- `slash/slash_command.mbt`: SlashCommandSpec/SlashCommandInvocation 类型与解析（parse）
- `completion.mbt`: 斜杠补全菜单；框架默认 command_specs 只有 exit，其余由宿主注入
- `input.mbt`: 输入流中识别斜杠并产出 SlashCommand 事件
- `config.mbt`: slash_commands 配置项（Config::new(slash_commands=...) 注入）
- `internal/composer.mbt`: 提交时把斜杠命令文本合成为提交行