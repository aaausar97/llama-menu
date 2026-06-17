# llama-menu

Custom macOS menu bar app for managing a local llama.cpp server. Built for Apple Silicon Macs.

![Menu Bar](https://img.shields.io/badge/menu%20bar-%F0%9F%A4%96-blue)
![Platform](https://img.shields.io/badge/platform-macOS%20Apple%20Silicon-lightgrey)
![License](https://img.shields.io/badge/license-MIT-green)

## Features

- 🤖 Menu bar icon with live server status + model name + idle time
- **Zero-config model management** — just drop `.gguf` files into `~/.models/`
- **One-click model switching** — click any model in the menu to load it
- **Seamless agent integration** — Pi, Claude Code, and other agents keep working when you swap models (inspired by llama-swap)
- **Context Size** picker (4K–128K) — pop-out submenu, no typing
- **KV Cache Type** picker (F16, Q8_0, Q4_0, Q4_1, Q5_0, Q5_1, IQ4_NL) — pop-out submenu
- **Batch Size** picker (512, 1024, 2048, 4096) — pop-out submenu
- **Memory Lock** and **High Priority** toggles (OFF by default)
- **Flash Attention** toggle (ON by default)
- **Speculative Decoding** — submenu with draft model selection (hidden unless draft models exist in `~/.models/`)
- **Custom Flags** — paste any llama-server command for full control
- **Unload Model** — stops server, frees RAM
- **Open Web Chat** — opens `http://127.0.0.1:11434` in browser
- **Refresh** — re-scans `~/.models/` for new files
- Server does NOT auto-start on launch — you control when models load
- Auto-unloads model from RAM after 3 minutes of idle time

## Screenshot

```
🤖 ● Running (Qwen3.5-9B-Q4_K_M.gguf) idle 3m
─────────────────────────────────────────────
Qwen3.5-9B-Q4_K_M.gguf (5.3 GB) ✓
Qwen_Qwen3.5-9B-Q4_K_M.gguf (5.7 GB)
gemma-4-12B-it-Q4_K_M.gguf (7.1 GB)
google_gemma-4-26B-A4B-it-Q4_K_M.gguf (16 GB)
─────────────────────────────────────────────
Advanced Settings
  Memory Lock: OFF
  High Priority: OFF
  Flash Attention: ON
  ▸ Context: 16K        ← pop-out: 4K, 8K, 16K ✓, 32K, 64K, 128K
  ▸ KV Cache: q8_0      ← pop-out: F16, Q8_0 ✓, Q4_0, Q4_1, Q5_0, Q5_1, IQ4_NL
  ▸ Batch Size: 2048     ← pop-out: 512, 1024, 2048 ✓, 4096
  ─────────────────────
  ▸ Speculative Decoding
    Enable
    Draft: Qwen_Qwen3.5-0.8B-Q4_K_M.gguf (553 MB)
  ─────────────────────
  Custom Flags...
  Reset to Defaults
─────────────────────────────────────────────
Unload Model
─────────────────────────────────────────────
Start Server  Stop Server  Restart Server
─────────────────────────────────────────────
Open Web Chat  Refresh  Quit
```

## Requirements

- macOS 14+ (Apple Silicon)
- [Homebrew](https://brew.sh)
- ~20GB free disk space (for models)

## Quick Start

```bash
# 1. Install llama.cpp (HEAD build for latest Apple Silicon optimizations)
brew install --HEAD llama.cpp

# 2. Clone this repo
git clone https://github.com/aaausar97/llama-menu.git ~/dev/llama-menu
cd ~/dev/llama-menu

# 3. Run the setup script
bash setup.sh

# 4. Download a model (any HuggingFace repo ID works)
models download unsloth/Qwen3.5-9B-GGUF

# 5. Set wired memory limit (one-time, persists across reboots)
bash setup-wired-memory.sh

# 6. Launch the menu bar app
open /Applications/llama-menu.app
```

## Model Management

### Downloading from HuggingFace

Any HuggingFace repo ID works — no registry needed:

```bash
# Download by repo ID (auto-detects Q4_K_M quantization)
models download unsloth/Qwen3.5-9B-GGUF
models download bartowski/gemma-4-12B-it-GGUF
models download bartowski/google_gemma-4-26B-A4B-it-GGUF

# Check what's downloaded
models list
```

Files are saved to `~/.models/` and appear in the menu bar app automatically.

### Model Lineup (tested on M5 Pro 24GB)

| Model | File Size | RAM Usage | Best For |
|-------|-----------|-----------|----------|
| Qwen3.5-9B-Instruct Q4_K_M | 5.3GB | ~6.5GB | Daily driver — agentic, tool calling |
| Gemma 4 12B Instruct Q4_K_M | 7.1GB | ~7.5GB | Coding, 128K context, multimodal |
| Gemma 4 26B-A4B Q4_K_M | 16GB | ~16GB | Best reasoning, MoE (4B active) |
| Qwen3.5-0.8B Q4_K_M (draft) | 553MB | ~0.5GB | Speculative decoding (hidden from main list) |

## Seamless Model Switching (llama-swap inspired)

When you switch models in the menu bar app, the server restarts with the new model. **Connected agents like Pi and Claude Code keep working** — they just use the new model on the next request.

### How it works

llama-server ignores the `model` field in OpenAI API requests — it always uses whatever model was loaded with `-m`. So agents can send any model name (e.g., `local-model`) and the server uses the currently loaded model.

### Configuring third-party agents

Point agents to `http://127.0.0.1:11434/v1` and set the model name to anything (e.g., `local-model`):

**Pi** (`~/.pi/agent/models.json` and `~/.pi/agent/settings.json`):
```json
// models.json — change model id to "local-model"
{
  "providers": {
    "llamacpp": {
      "baseUrl": "http://127.0.0.1:11434/v1",
      "models": [{"id": "local-model"}]
    }
  }
}

// settings.json — change defaultModel
{
  "defaultModel": "local-model",
  "defaultProvider": "llamacpp"
}
```

**Claude Code** (`~/.claude/settings.json`):
```json
{
  "model": "local-model"
}
```

**Hermes** (`~/.hermes/config.yaml`):
```yaml
providers:
  llamacpp:
    api: http://127.0.0.1:11434/v1
    default_model: local-model
    models: ["local-model"]
    name: llama.cpp
```

**OpenRouter / other providers**: Set base URL to `http://127.0.0.1:11434/v1` and model to `local-model`.

When you switch models in the menu bar, the next agent request uses the new model automatically. No need to restart agents.

### Speculative Decoding

If you have a small draft model in `~/.models/`, it appears under Advanced → Speculative Decoding. Enable it to use the draft model for faster generation. The draft model is automatically hidden from the main model list.

## Server Flags Explained

### Default Flags (Smart Defaults for Apple Silicon)

Applied automatically when you click "Start Server":

```bash
-m /path/to/model.gguf    # Model file path
-ngl 99                    # Offload ALL layers to Metal GPU
--ctx-size 16384           # Context window (configurable in menu)
--threads 8                # CPU threads (match P-cores)
--cache-type-k q8_0        # KV cache K quantization (configurable)
--cache-type-v q8_0        # KV cache V quantization (configurable)
-fa auto                   # Flash Attention (auto-enable)
--tools all                # Built-in server tools
--jinja                    # Jinja templates (function calling)
--ui-mcp-proxy             # MCP server CORS proxy
--host 127.0.0.1           # Bind address
--port 11434               # Port
--sleep-idle-seconds 180   # Auto-unload after 3 min idle
```

### What Each Flag Does

| Flag | Why |
|------|-----|
| `-ngl 99` | Offloads all model layers to the Metal GPU. Without this, inference falls back to CPU (100x slower). |
| `--ctx-size` | Maximum context window. Higher = more memory. 16K is the sweet spot for most tasks. |
| `--threads 8` | Number of CPU threads. Set to your P-core count (not total cores). |
| `--cache-type-k/v q8_0` | Quantizes KV cache to 8-bit. Halves KV cache RAM with negligible quality loss. Requires Flash Attention. Allowed values: `f16`, `q8_0`, `q4_0`, `q4_1`, `q5_0`, `q5_1`, `iq4_nl`. |
| `-fa auto` | Enables Metal Flash Attention. Faster prefill, smaller memory per token. **Required** for KV cache quantization to work. |
| `--tools all` | Enables built-in server-side tools: read_file, write_file, exec_shell, grep_search, file_glob_search, edit_file, apply_diff, get_datetime. |
| `--jinja` | Enables Jinja template engine. Required for modern model chat templates and function calling. |
| `--ui-mcp-proxy` | Proxies MCP server connections through llama-server. Fixes CORS errors when connecting MCP servers from the web UI. |
| `--mlock` | Pins model and KV cache in physical RAM. Prevents macOS from paging to disk. Safe if model uses <70% of RAM. OFF by default. |
| `--prio 2` | Higher scheduling priority. Reduces chance of inference threads being interrupted. OFF by default. |
| `--sleep-idle-seconds 180` | Auto-unloads model from RAM after 3 minutes of no requests. Server stays running, model reloads on next request. |

### Advanced Flags (in Advanced Settings submenu)

| Flag | Default | When to Use |
|------|---------|-------------|
| `--no-mmap` | OFF | Workaround if model loading hangs at ~75% on Apple Silicon |
| `-cb` (continuous batching) | OFF | Multi-user server setups |
| `-np N` (parallel slots) | 1 | Multiple concurrent users/agents. Each slot needs its own KV cache. |
| `--temp` | 0.7 | Sampling temperature. 0.7 for general tasks, 1.0 for reasoning models. |
| `--top-p` | 0.9 | Nucleus sampling. 0.9 for general, 1.0 for reasoning models. |
| `--min-p` | 0.05 | Minimum probability threshold. |
| `--repeat-penalty` | 1.1 | Penalize repetition. 1.1 for general, 1.0 for reasoning models. |

### Flags That Do Nothing on Apple Silicon

From the [Tuning llama.cpp on Apple Silicon](https://medium.com/@michael.hannecke/tuning-llama-cpp-on-apple-silicon-843f37a6c3dc) article:

- `--numa` — NUMA is for multi-socket x86. Apple Silicon has unified memory.
- `--main-gpu`, `--tensor-split`, `--split-mode` — Multi-GPU coordination. Macs have one GPU.
- `--cpu-mask`, `--cpu-strict`, `--poll` — CPU affinity. macOS ignores these.
- `--no-kv-offload` — Forces KV cache to CPU. Bad on Apple Silicon (shared memory).
- `--cuda-*`, ROCm flags — NVIDIA/AMD only.

## Wired Memory Setup

The single most important tuning step for Apple Silicon. The GPU driver has a wired memory limit that can prevent large models from loading even when you have enough RAM.

```bash
# Run once — sets limit to 70% of your RAM and persists across reboots
bash setup-wired-memory.sh
```

For a 24GB Mac, this sets the limit to ~16GB. This is a **ceiling**, not a reservation — the GPU only uses what it needs.

## Menu Bar App Usage

### Quick Settings (always visible in Advanced)
- **Context Size** — pick 4K, 8K, 16K (default), 32K, 64K, 128K
- **KV Cache** — pick F16, Q8_0 (default), Q4_0, Q4_1, Q5_0, Q5_1, IQ4_NL
- **Batch Size** — pick 512, 1024, 2048 (default), 4096
- **Memory Lock** — toggle --mlock on/off
- **High Priority** — toggle --prio 2 on/off
- **Flash Attention** — toggle -fa on/off

### Speculative Decoding (hover to expand)
- Enable/disable toggle
- Pick draft model from available files in `~/.models/`

### Server Control
- **Start Server** — loads model and starts serving
- **Stop Server** — kills server process, frees RAM
- **Restart Server** — stop + start (applies new settings)
- **Unload Model** — stops server, frees model RAM

### Other
- **Open Web Chat** — opens `http://127.0.0.1:11434` in browser
- **Refresh** — re-scans `~/.models/` for new files

## Bash Scripts

### `models` — Model Management (no registry needed)

```bash
models list                                    # Show all .gguf files in ~/.models/
models download unsloth/Qwen3.5-9B-GGUF       # Download any HF repo
models serve Qwen3.5-9B-Q4_K_M.gguf          # Start server with model
models current                                 # Show running model
models delete Qwen3.5-9B-Q4_K_M.gguf         # Remove model file
```

### `llama` — Server Control

```bash
llama start              # Start with default model
llama stop               # Stop server
llama restart            # Restart with current model
llama status             # Check health + which model is loaded
```

## Building from Source

```bash
cd ~/dev/llama-menu

# Build the menu bar app
swiftc -o llama-menu llama-menu.swift -framework Cocoa

# Install
cp llama-menu /Applications/llama-menu.app/Contents/MacOS/
cp llama models /usr/local/bin/
open /Applications/llama-menu.app
```

## Performance

On an M5 Pro 24GB MacBook Pro:

| Model | Context | Speed | RAM |
|-------|---------|-------|-----|
| Qwen3.5-9B Q4_K_M | 16K | ~33 tok/s | ~6.5GB |
| Gemma 4 12B Q4_K_M | 16K | ~28 tok/s | ~7.5GB |
| Gemma 4 26B-A4B Q4_K_M | 8K | ~12 tok/s | ~16GB |

Measured with default flags: `-ngl 99 -fa auto --cache-type-k/v q8_0`

## Troubleshooting

### "Model won't load" / Metal allocation failures
Run the wired memory setup:
```bash
bash setup-wired-memory.sh
```

### Model loading hangs at ~75%
Enable `--no-mmap` in Advanced Settings (workaround for a known Apple Silicon bug).

### MCP servers won't connect from web UI
Make sure `--ui-mcp-proxy` is enabled (it is by default).

### Server is slow
- Make sure `-ngl 99` is set (GPU offload)
- Make sure `-fa auto` is set (Flash Attention)
- Check that you're not accidentally on CPU: `ps aux | grep llama-server` should show high GPU usage

### Out of memory
- Reduce context size (try 8K instead of 16K)
- Use a more aggressive KV cache quantization (Q4_0)
- Unload model when not in use (auto-unloads after 3 min idle)

## References

- [Tuning llama.cpp on Apple Silicon: 7 Flags That Matter](https://medium.com/@michael.hannecke/tuning-llama-cpp-on-apple-silicon-843f37a6c3dc)
- [llama.cpp Apple Silicon docs](https://github.com/ggml-org/llama.cpp/blob/master/docs/build.md#metal)
- [llama-swap](https://github.com/mostlygeek/llama-swap) — seamless model switching inspiration
- [Google Gemma 4 docs](https://ai.google.dev/gemma/docs/core)
- [Qwen3.5 docs](https://qwen.readthedocs.io/)

## License

MIT
