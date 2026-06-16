# Model Lineup

All models stored in `~/.models/`. Only one model runs at a time on 24GB RAM.

| Alias | Model | File Size | RAM Usage | Best For |
|-------|-------|-----------|-----------|----------|
| `qwen9` | Qwen3.5-9B-Instruct Q4_K_M | 5.7GB | ~6.5GB | Daily driver — agentic, tool calling, coding |
| `gemma12` | Gemma 4 12B Instruct Q4_K_M | 7.1GB | ~7.5GB | Coding, 128K context, multimodal |
| `gemma26` | Gemma 4 26B-A4B Q4_K_M | 16GB | ~16GB | Best reasoning, MoE (4B active params) |
| `draft` | Qwen3.5-0.8B Q4_K_M | 553MB | ~0.5GB | Speculative decoding draft model |

## Performance (M5 Pro 24GB)

| Model | Context | Speed | RAM |
|-------|---------|-------|-----|
| Qwen3.5-9B | 16K | ~33 tok/s | ~6.5GB |
| Gemma 4 12B | 16K | ~28 tok/s | ~7.5GB |
| Gemma 4 26B-A4B | 16K | ~12 tok/s | ~16GB |

## Default Server Flags

```bash
-ngl 99                    # Offload all layers to Metal GPU
--ctx-size 16384           # Context window
--batch-size 2048          # Batch size (faster prefill)
--ubatch-size 2048         # Micro-batch size
--threads 8                # CPU threads
--cache-type-k q8_0        # KV cache K quantization
--cache-type-v q8_0        # KV cache V quantization
-fa auto                   # Flash Attention
--tools all                # Built-in server tools
--jinja                    # Jinja templates (function calling)
--ui-mcp-proxy             # MCP server CORS proxy
--mlock                    # Pin model in RAM
--prio 2                   # Higher scheduling priority
--host 127.0.0.1
--port 11434
--sleep-idle-seconds 180   # Auto-unload after 3 min idle
```

## Wired Memory

Run once to set the GPU wired memory limit to 70% of RAM:

```bash
bash setup-wired-memory.sh
```

For 24GB Mac: sets limit to ~16GB. This is a ceiling, not a reservation.
