#!/bin/bash
# setup-wired-memory.sh
# Run once to set the wired memory limit for Apple Silicon GPU
# This is the single most important tuning step per the article

# Detect total RAM in GB
TOTAL_RAM_GB=$(sysctl -n hw.memsize | awk '{printf "%.0f", $1/1073741824}')

# Calculate 70% of total RAM in MB (the safe limit per the article)
WIRED_LIMIT_MB=$(echo "$TOTAL_RAM_GB * 0.7 * 1024" | bc | cut -d. -f1)

echo "Detected RAM: ${TOTAL_RAM_GB}GB"
echo "Setting wired limit to: ${WIRED_LIMIT_MB}MB (70% of RAM)"
echo ""

# Set it now (temporary, resets on reboot)
sudo sysctl iogpu.wired_limit_mb=$WIRED_LIMIT_MB

# Create a LaunchDaemon to persist it across reboots
sudo tee /Library/LaunchDaemons/com.llama.wired-memory.plist > /dev/null << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.llama.wired-memory</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/sbin/sysctl</string>
        <string>iogpu.wired_limit_mb=$WIRED_LIMIT_MB</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
EOF

sudo launchctl load /Library/LaunchDaemons/com.llama.wired-memory.plist 2>/dev/null

echo ""
echo "✓ Wired memory limit set to ${WIRED_LIMIT_MB}MB"
echo "✓ Persisted via LaunchDaemon (survives reboots)"
echo ""
echo "To undo:"
echo "  sudo rm /Library/LaunchDaemons/com.llama.wired-memory.plist"
echo "  sudo sysctl iogpu.wired_limit_mb=0"
