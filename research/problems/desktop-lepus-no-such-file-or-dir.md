根目录的 `moon.work` 声明了全部 workspace 成员，包括 `./desktop/lepus/config` 等 14 个 lepus 子包。moon 在启动任何命令时，第一步就是解析 `moon.work` 并校验所有成员路径存在。

所以现在在使用 CLI 等命令之前，必须执行：

```bash
git submodule update --init desktop/lepus
```

（不代表 TUI 等依赖于 desktop/lepus，只是 moon 解析 workspace 时要求路径存在）