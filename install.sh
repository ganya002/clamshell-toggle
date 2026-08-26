#!/bin/bash
set -e

# Clamshell Toggle — one-click installer for macOS
# Builds a tiny native menu bar app that toggles `pmset disablesleep`
# Repo: https://github.com/ganya002/clamshell-toggle

REPO="ganya002/clamshell-toggle"
APP_NAME="Clamshell Toggle.app"
APP_PATH="$HOME/Applications/$APP_NAME"
BIN_PATH="$APP_PATH/Contents/MacOS/ClamshellToggle"
PLIST_PATH="$HOME/Library/LaunchAgents/com.user.clamshell-toggle.plist"

echo "=> Clamshell Toggle installer"

# Checks
if [[ "$(uname)" != "Darwin" ]]; then
  echo "Error: macOS only." >&2
  exit 1
fi

if ! command -v swiftc >/dev/null 2>&1; then
  echo "Error: swiftc not found. Install Xcode Command Line Tools:" >&2
  echo "  xcode-select --install" >&2
  exit 1
fi

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# Locate sources: prefer local checkout, fallback to downloading from GitHub
SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd || echo "")"
if [[ -f "$SCRIPT_DIR/Sources/main.swift" && -f "$SCRIPT_DIR/Resources/Info.plist" ]]; then
  echo "=> Using local sources"
  cp "$SCRIPT_DIR/Sources/main.swift" "$TMPDIR/main.swift"
  cp "$SCRIPT_DIR/Resources/Info.plist" "$TMPDIR/Info.plist"
else
  echo "=> Downloading sources from GitHub"
  curl -fsSL "https://raw.githubusercontent.com/$REPO/main/Sources/main.swift" -o "$TMPDIR/main.swift"
  curl -fsSL "https://raw.githubusercontent.com/$REPO/main/Resources/Info.plist" -o "$TMPDIR/Info.plist"
fi

echo "=> Compiling (swiftc)..."
swiftc -O -o "$TMPDIR/ClamshellToggle" "$TMPDIR/main.swift"

echo "=> Creating app bundle at $APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$TMPDIR/ClamshellToggle" "$BIN_PATH"
cp "$TMPDIR/main.swift" "$APP_PATH/Contents/Resources/main.swift"
cp "$TMPDIR/Info.plist" "$APP_PATH/Contents/Info.plist"
chmod +x "$BIN_PATH"
# ad-hoc sign so Gatekeeper is happier
codesign --force --sign - "$APP_PATH" 2>/dev/null || true

echo "=> Installing LaunchAgent (auto-start at login)"
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key><string>com.user.clamshell-toggle</string>
	<key>ProgramArguments</key>
	<array>
		<string>$BIN_PATH</string>
	</array>
	<key>RunAtLoad</key><true/>
	<key>KeepAlive</key><false/>
	<key>LimitLoadToSessionType</key><string>Aqua</string>
</dict>
</plist>
EOF

# (re)load
launchctl bootout "gui/$(id -u)/com.user.clamshell-toggle" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH" 2>/dev/null || launchctl load "$PLIST_PATH" 2>/dev/null || true

echo "=> Configuring passwordless pmset (requires sudo once)"
if sudo -n /usr/bin/pmset disablesleep 1 2>/dev/null; then
  echo "   Already configured (or just enabled)."
  # keep current state? leave as enabled for immediate feedback
  pmset -g | grep -q SleepDisabled || true
else
  echo "   Requesting sudo to create /etc/sudoers.d/clamshell ..."
  echo "$USER ALL=(root) NOPASSWD: /usr/bin/pmset disablesleep *" | sudo tee /etc/sudoers.d/clamshell >/dev/null
  sudo chmod 0440 /etc/sudoers.d/clamshell
  if sudo visudo -cf /etc/sudoers.d/clamshell 2>/dev/null; then
    echo "   Sudoers rule installed."
  else
    echo "   Warning: visudo check failed. Removing file." >&2
    sudo rm -f /etc/sudoers.d/clamshell
    exit 1
  fi
  # test
  sudo -n /usr/bin/pmset disablesleep 1
fi

echo ""
echo "✓ Done! Look for 'Clamshell ON/OFF' in your menu bar."
echo "  Click the menu item to toggle. Disable sleep = lid-closed stays awake on battery."
echo ""
echo "  To uninstall: ./uninstall.sh  or  curl -fsSL https://raw.githubusercontent.com/$REPO/main/uninstall.sh | bash"
echo "  Repo: https://github.com/$REPO"
