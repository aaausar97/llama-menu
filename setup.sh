#!/bin/bash
# setup.sh — Restore llama-menu app and scripts
# Run from the repo directory: cd ~/llama-menu-app && bash setup.sh

set -e

echo "=== Setting up llama-menu ==="

# Check for llama.cpp
if ! command -v llama-server &> /dev/null; then
    echo "Installing llama.cpp..."
    brew install --HEAD llama.cpp
fi

# Create .models directory
mkdir -p ~/.models

# Copy scripts to /usr/local/bin
echo "Installing scripts..."
cp -f llama /usr/local/bin/llama
cp -f models /usr/local/bin/models
chmod +x /usr/local/bin/llama /usr/local/bin/models

# Install app
echo "Installing menu bar app..."
cp -rf llama-menu.app /Applications/

# Copy launchd plist
cp -f com.llama.server.plist ~/Library/LaunchAgents/
launchctl unload ~/Library/LaunchAgents/com.llama.server.plist 2>/dev/null

echo ""
echo "=== Setup complete ==="
echo ""
echo "Next steps:"
echo "  1. Download models:  models download all"
echo "  2. Launch app:       open /Applications/llama-menu.app"
echo "  3. (Optional) Add to Login Items in System Settings"
echo ""
echo "Commands:"
echo "  llama start / stop / restart / status"
echo "  models list / serve <alias> / download <alias>"
