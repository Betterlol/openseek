
## 判断是否支持 `pwsh`
`pwsh_available()`

执行 `which pwsh` | `where pwsh` 来判断是否支持 `pwsh`，如果返回值为 0，则表示支持 `pwsh`，否则不支持。
> 只查 PATH，不启动 pwsh