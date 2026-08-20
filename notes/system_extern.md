
```mbt
#cfg(platform="windows")
#borrow(cmd)
extern "c" fn _system(cmd : Bytes) -> Int = "system"
```

```
Bytes 是指针类型，需要标注 #borrow 表示借用而非所有权转移。已修复。
```