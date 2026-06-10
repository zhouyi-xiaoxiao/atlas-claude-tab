#!/bin/bash
# atlas-claude-tab installer: build the helper .app, install a LaunchAgent, start it.
set -euo pipefail

LABEL="com.$(whoami).atlas-claude-tab"
SRC_DIR="$HOME/.local/atlas-claude-tab"
APP="$HOME/Applications/AtlasClaudeTab.app"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
UID_NUM=$(id -u)

if [ ! -d "/Applications/ChatGPT Atlas.app" ]; then
  echo "ChatGPT Atlas not found in /Applications — aborting." >&2
  exit 1
fi
if ! command -v swiftc >/dev/null; then
  echo "swiftc not found — install Xcode Command Line Tools: xcode-select --install" >&2
  exit 1
fi

mkdir -p "$SRC_DIR" "$APP/Contents/MacOS" "$HOME/Library/LaunchAgents"
cp main.swift "$SRC_DIR/main.swift"
[ -f "$SRC_DIR/config.json" ] || cp config.example.json "$SRC_DIR/config.json"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>$LABEL</string>
  <key>CFBundleName</key><string>AtlasClaudeTab</string>
  <key>CFBundleExecutable</key><string>AtlasClaudeTab</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
EOF

echo "Building…"
swiftc -O "$SRC_DIR/main.swift" -o "$APP/Contents/MacOS/AtlasClaudeTab" -framework AppKit -framework Carbon
codesign -s - --force "$APP"

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array><string>$APP/Contents/MacOS/AtlasClaudeTab</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ProcessType</key><string>Background</string>
</dict>
</plist>
EOF

launchctl bootout "gui/$UID_NUM/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$UID_NUM" "$PLIST"

cat <<EOF

Installed and started ($LABEL).

NEXT STEPS
1. In Atlas, make sure a bookmark named "Claude" -> https://claude.ai/new exists.
2. Grant Accessibility: System Settings > Privacy & Security > Accessibility > enable AtlasClaudeTab
   (a prompt should have just appeared).
3. Restart the helper so it picks up the grant:
   launchctl kickstart -k gui/$UID_NUM/$LABEL
4. Switch to Atlas and press Cmd+T.

Log: ~/Library/Logs/atlas-claude-tab.log
EOF
