# Model Lineup for 24GB M5 Pro

All models stored in `~/.models/` (one at a time).

| Alias | Model | Size | RAM | Best For |
|-------|-------|------|-----|----------|
| qwen9 | Qwen3.5-9B-Instruct Q4_K_M | 5.7GB | ~6.5GB | Daily driver — agentic, tool calling |
| gemma12 | Gemma 4 12B Instruct Q4_K_M | 7.1GB | ~7.5GB | Coding, 128K context |
| gemma26 | Gemma 4 26B-A4B UD-Q4_K_M | 16GB | ~16GB | Best reasoning, MoE draft |
| draft | Qwen3.5-0.8B Q4_K_M | 553MB | ~0.5GB | Speculative decoding |

## Default Server Flags

```
-ngl 99
--ctx-size 16384
--batch-size 512
--threads 8
--cache-type-k q8_0
--cache-type-v q8_0
-fa auto
--tools all
--jinja
--ui-mcp-proxy
--host 127.0.0.1
--port 11434
--sleep-idle-seconds 180
```

- `--tools all` — enables built-in server tools (read_file, write_file, exec_shell, grep, etc.)
- `--jinja` — enables Jinja template engine for model function calling
- `--ui-mcp-proxy` — proxies MCP server connections through llama-server (fixes CORS)
- `--sleep-idle-seconds 180` — auto-unloads model from RAM after 3 min idle
