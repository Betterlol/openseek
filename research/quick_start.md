
## CLI

```bash
moon update
```

```bash
export DEEPSEEK=sk-...   # DeepSeek；用 Kimi 则 export KIMI=sk-...
# sk-a53b2ea4197d4533b3feeeff3725642a
# 指定模型（默认 deepseek-v4-pro）
export OPENSEEK_MODEL=deepseek-v4-flash
moon run cmd/openseek -- tui
```

## GUI

```bash
git submodule update --init desktop/lepus
```

```bash
moon -C desktop run --target native package/linux -- --release
```
