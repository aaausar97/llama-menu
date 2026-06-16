# llama-menu

Custom macOS menu bar app for managing a local llama.cpp server.

## Features

- 🤖 Menu bar icon with server status
- Switch between downloaded models on the fly
- Custom command — paste any llama-server flags to launch with
- Unload model (free RAM without stopping server)
- Open Web Chat at http://127.0.0.1:11434
- Server auto-starts on boot via launchd
- `--tools all` for built-in server tools
- `--jinja` + `--ui-mcp-proxy` for MCP server CORS fix

## Files

| File | Purpose |
|------|---------|
| `llama-menu.swift` | Swift source for menu bar app |
| `llama-menu.app` | Compiled app bundle |
| `llama` | Bash script for server control |
| `models` | Bash script for model management |
| `com.llama.server.plist` | Launchd plist (auto-start on boot) |
| `MODELS.md` | Model lineup |

## Setup

1. Install llama.cpp: `brew install --HEAD llama.cpp`
2. Download models: `models download all` (or individually)
3. Copy scripts to PATH:
   ```bash
   cp llama models /usr/local/bin/
   ```
4. Install app:
   ```bash
   cp -r llama-menu.app /Applications/
   open /Applications/llama-menu.app
   ```
5. (Optional) Add to Login Items: System Settings → General → Login Items → Add llama-menu.app

## Usage

```bash
# Server control
llama start / stop / restart / status

# Model management
models list / serve <alias> / download <alias> / current

# From the menu bar
# Click 🦙 → Start Server / Switch Models / Custom Command / Open Web Chat
```

## Building from Source

```bash
swiftc -o llama-menu llama-menu.swift -framework Cocoa
cp llama-menu /Applications/llama-menu.app/Contents/MacOS/
open /Applications/llama-menu.app
```

## Adding New Models

Edit the `modelRegistry` array in both `llama-menu.swift` and `models`:
```
("alias", "Display Name", "filename.gguf")
```
Place the `.gguf` file in `~/.models/` and it appears in the menu automatically.
