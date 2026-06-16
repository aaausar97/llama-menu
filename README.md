# llama-menu

Custom macOS menu bar app for managing a local llama.cpp server. Built for Apple Silicon Macs.

![Menu Bar](https://img.shields.io/badge/menu%20bar-%F0%9F%A4%96-blue)
![Platform](https://img.shields.io/badge/platform-macOS%20Apple%20Silicon-lightgrey)
![License](https://img.shields.io/badge/license-MIT-green)

## Features

- 🤖 Menu bar icon with live server status
- Switch between downloaded models on the fly
- **Context Size** picker (4K–128K)
- **KV Cache Type** picker (F16, Q8_0, Q4_K_S, etc.)
- **Memory Lock** and **High Priority** toggles
- **Advanced Settings** submenu for batch size, sampling, and special flags
- **Custom Command** — paste any llama-server flags to launch with
- **Unload Model** — free RAM without stopping the server
- **Open Web Chat** — launches http://127.0.0.1:11434 in your browser
- Server does NOT auto-start on launch — you control when models load
- Auto-unloads model from RAM after 3 minutes of idle time

## Screenshot

```
🤖 ○ Stopped
─────────────────
Qwen3.5-9B-Instruct ✓
Gemma 4 12B Instruct
Gemma 4 26B-A4B
─────────────────
Context: 16K          ← submenu
KV Cache: q8_0        ← submenu
Memory Lock: ON       ← toggle
High Priority: ON     ← toggle
─────────────────
Advanced Settings ▸   ← hover to expand
─────────────────
Unload Model
─────────────────
Start Server  Stop  Restart
─────────────────
View Logs  Open Web Chat  Open Models Folder
Refresh
─────────────────
Quit
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
git clone https://github.com/aaausar97/llama-menu.git ~/llama-menu-app
cd ~/llama-menu-app

# 3. Run the setup script
bash setup.sh

# 4. Download models
models download all

# 5. Set wired memory limit (one-time, persists across reboots)
bash setup-wired-memory.sh

# 6. Launch the menu bar app
open /Applications/llama-menu.app
```

## Model Lineup

All models stored in `~/.models/`. Only one model runs at a time.

| Alias | Model | File Size | RAM Usage | Best For |
|-------|-------|-----------|-----------|----------|
| `qwen9` | Qwen3.5-9B-Instruct Q4_K_M | 5.7GB | ~6.5GB | Daily driver — agentic, tool calling, coding |
| `gemma12` | Gemma 4 12B Instruct Q4_K_M | 7.1GB | ~7.5GB | Coding, 128K context, multimodal |
| `gemma26` | Gemma 4 26B-A4B Q4_K_M | 16GB | ~16GB | Best reasoning, MoE (4B active params) |
| `draft` | Qwen3.5-0.8B Q4_K_M | 553MB | ~0.5GB | Speculative decoding draft model |

### Downloading Models

Models are downloaded using the `hf` CLI (via `uvx hf`) which handles HuggingFace's Xet storage format, supports resume, and verifies checksums automatically. Falls back to `curl` if `hf` is not available.

```bash
# Download all models
models download all

# Download individual models
models download qwen9
models download gemma12
models download gemma26
models download draft

# Check what's downloaded
models list
```

**Download priority:** `uvx hf download` → `hf download` → `curl` (fallback)

**Important:** Some models (like Gemma 26B) are stored as Xet files on HuggingFace. The `uvx hf download` command handles these correctly. If you get stuck downloads with plain `hf`, use `uvx hf` instead — it runs the latest version in an isolated environment:

```bash
# Manual download with uvx hf (if models download fails)
uvx hf download bartowski/google_gemma-4-26B-A4B-it-GGUF \
  --include "google_gemma-4-26B-A4B-it-Q4_K_M.gguf" \
  --local-dir ~/.models
```
models download gemma26
models download draft

# Check what's downloaded
models list
```

## Server Flags Explained

### Default Flags (Smart Defaults for Apple Silicon)

These are applied automatically when you click "Start Server":

```bash
-m /path/to/model.gguf    # Model file path
-ngl 99                    # Offload ALL layers to Metal GPU
--ctx-size 16384           # Context window (configurable in menu)
--batch-size 2048          # Logical batch size (faster prefill)
--ubatch-size 2048         # Physical micro-batch size
--threads 8                # CPU threads (match P-cores)
--cache-type-k q8_0        # KV cache K quantization (configurable)
--cache-type-v q8_0        # KV cache V quantization (configurable)
-fa auto                   # Flash Attention (auto-enable)
--tools all                # Built-in server tools
--jinja                    # Jinja templates (function calling)
--ui-mcp-proxy             # MCP server CORS proxy
--mlock                    # Pin model in RAM (prevent swap)
--prio 2                   # Higher scheduling priority
--host 127.0.0.1           # Bind address
--port 11434               # Port
--sleep-idle-seconds 180   # Auto-unload after 3 min idle
```

### What Each Flag Does

| Flag | Why |
|------|-----|
| `-ngl 99` | Offloads all model layers to the Metal GPU. Without this, inference falls back to CPU (100x slower). |
| `--ctx-size` | Maximum context window. Higher = more memory. 16K is the sweet spot for most tasks. |
| `--batch-size 2048` | Larger batches = faster prefill. The article recommends 2048 for Apple Silicon. |
| `--ubatch-size 2048` | Micro-batch size for prompt processing. Match to batch-size. |
| `--threads 8` | Number of CPU threads. Set to your P-core count (not total cores). |
| `--cache-type-k/v q8_0` | Quantizes KV cache to 8-bit. Halves KV cache RAM with negligible quality loss. Requires Flash Attention. |
| `-fa auto` | Enables Metal Flash Attention. Faster prefill, smaller memory per token. Required for KV cache quantization. |
| `--tools all` | Enables built-in server-side tools: read_file, write_file, exec_shell, grep_search, file_glob_search, edit_file, apply_diff, get_datetime. |
| `--jinja` | Enables Jinja template engine. Required for modern model chat templates and function calling. |
| `--ui-mcp-proxy` | Proxies MCP server connections through llama-server. Fixes CORS errors when connecting MCP servers from the web UI. |
| `--mlock` | Pins model and KV cache in physical RAM. Prevents macOS from paging to disk. Safe if model uses <70% of RAM. |
| `--prio 2` | Higher scheduling priority. Reduces chance of inference threads being interrupted. |
| `--sleep-idle-seconds 180` | Auto-unloads model from RAM after 3 minutes of no requests. Server stays running, model reloads on next request. |

### Advanced Flags (in Advanced Settings submenu)

These are OFF by default and can be enabled as needed:

| Flag | Default | When to Use |
|------|---------|-------------|
| `--no-mmap` | OFF | Workaround if model loading hangs at ~75% on Apple Silicon |
| `--numa distribute` | OFF | x86 only, no-op on Apple Silicon. Don't enable. |
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

### Quick Settings (always visible)
- **Context Size** — pick 4K, 8K, 16K (default), 32K, 64K, 128K
- **KV Cache** — pick F16, Q8_0 (default), Q4_K_S, Q4_K_M, Q5_K_M
- **Memory Lock** — toggle --mlock on/off
- **High Priority** — toggle --prio 2 on/off

### Advanced Settings (hover to expand)
- Batch Size, Flash Attention, Continuous Batching, Parallel Slots
- Temperature, Top-P, Min-P, Repeat Penalty
- no-mmap (hang workaround), NUMA (x86 only)
- Custom Flags — paste any llama-server command
- Reset to Defaults

### Server Control
- **Start Server** — loads model and starts serving
- **Stop Server** — kills server process
- **Restart Server** — stop + start (applies new settings)
- **Unload Model** — frees model RAM, server stays running

### Other
- **View Logs** — opens server log file
- **Open Web Chat** — opens http://127.0.0.1:11434 in browser
- **Open Models Folder** — opens ~/.models/ in Finder
- **Refresh** — re-scans downloaded models

## Bash Scripts

### `llama` — Server Control

```bash
llama start              # Start with default model
llama start spec         # Start with speculative decoding
llama stop               # Stop server
llama restart            # Restart with current model
llama restart spec       # Restart with speculative decoding
llama status             # Check health + which model is loaded
```

### `models` — Model Management

```bash
models list                              # Show all models + status
models download all                      # Download full lineup
models download qwen9                    # Download specific model
models serve qwen9                       # Switch to model
models serve qwen9 draft                 # With speculative decoding
models current                           # Show running model
models delete qwen9                      # Remove model file
```

### Environment Overrides

```bash
# Override context size and KV cache for a single launch
CTX_SIZE=32768 KV_CACHE=q4_k_s models serve qwen9
```

## Building from Source

```bash
cd ~/llama-menu-app

# Build the menu bar app
swiftc -o llama-menu llama-menu.swift -framework Cocoa

# Install
cp llama-menu /Applications/llama-menu.app/Contents/MacOS/
cp llama models /usr/local/bin/
open /Applications/llama-menu.app
```

## Adding New Models

1. Add entry to `modelRegistry` in both `llama-menu.swift` and `models`:
   ```swift
   ("alias", "Display Name", "filename.gguf"),
   ```
   ```bash
   "alias|repo|filename.gguf|size_gb|Description"
   ```

2. Download: `models download <alias>`

3. Rebuild the Swift app (see above)

4. The model appears in the menu automatically when the file exists in `~/.models/`

## Performance

On an M5 Pro 24GB MacBook Pro:

| Model | Context | Speed | RAM |
|-------|---------|-------|-----|
| Qwen3.5-9B Q4_K_M | 16K | ~33 tok/s | ~6.5GB |
| Gemma 4 12B Q4_K_M | 16K | ~28 tok/s | ~7.5GB |
| Gemma 4 26B-A4B UD-Q4_K_M | 16K | ~12 tok/s | ~16GB |

Measured with default flags: `-ngl 99 -fa auto --cache-type-k/v q8_0 -b 2048 -ub 2048 --mlock --prio 2`

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
- Use a more aggressive KV cache quantization (Q4_K_S)
- Unload model when not in use (auto-unloads after 3 min idle)

## References

- [Tuning llama.cpp on Apple Silicon: 7 Flags That Matter](https://medium.com/@michael.hannecke/tuning-llama-cpp-on-apple-silicon-843f37a6c3dc)
- [llama.cpp Apple Silicon docs](https://github.com/ggml-org/llama.cpp/blob/master/docs/build.md#metal)
- [Google Gemma 4 docs](https://ai.google.dev/gemma/docs/core)
- [Qwen3.5 docs](https://qwen.readthedocs.io/)

## License

MIT
