
```mbt
@decode.EditInput
```

```mbt
pub struct EditInput {
  path : String           // 要编辑的文件路径
  old_string : String     // 要替换的精确文本（空 = 插入模式）
  new_string : String     // 替换文本
  replace_all : Bool      // 已废弃，返回迁移错误
  replace_all_preview : Bool  // 设为 true 时不应用编辑，返回所有匹配位置做 review
  start_line : Int        // 搜索起始行（1-based，锚定搜索范围）
  end_line : Int?         // 搜索结束行（可选，None 表示到文件末尾）
  revert_on_parse_errors : Bool  // 默认 true，编辑结果引入新语法错误时回滚
}
old_string_context 用到的字段：
- start_line / end_line — 决定搜索范围，也用于提取附近内容做上下文展示
- old_string — 用于和文件实际内容逐字符比较，找第一个差异位
```

```mbt
// 目的：提供多一行的上下文。
let context_before = 2
let context_after = 2

```

上下文：
```mbt
for line_no in first_line..=last_line {
    let ls = line_start_offset(content, line_no)
    let le = line_end_offset(content, line_no)
    let line_text = if le > ls && content[le - 1] == '\n' {
        content.unsafe_substring(start=ls, end=le - 1)
    } else {
        content.unsafe_substring(start=ls, end=le)
    }
    let gutter = if line_no >= start_line && (input.end_line is None || line_no <= end_line) { " >" } else { "  " }
    lines.push("\{gutter} \{line_no} | \{line_text}")
}
```