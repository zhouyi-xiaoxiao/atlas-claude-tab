#!/bin/bash
# Remove the atlas-claude-tab helper, LaunchAgent, and TCC entry.
set -uo pipefail

LABEL="com.$(whoami).atlas-claude-tab"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist"
rm -rf "$HOME/Applications/AtlasClaudeTab.app"
rm -rf "$HOME/.local/atlas-claude-tab"
tccutil reset Accessibility "$LABEL" 2>/dev/null
echo "Removed. (Optional: defaults delete com.openai.atlas NSUserKeyEquivalents)"
