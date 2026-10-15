#!/bin/bash
set -euo pipefail

# Clamshell Toggle — one-line install for macOS 26+
# Repo: https://github.com/ganya002/clamshell-toggle

REPO="ganya002/clamshell-toggle"
APP_NAME="Clamshell Toggle.app"
APP_PATH="$HOME/Applications/$APP_NAME"
BIN_PATH="$APP_PATH/Contents/MacOS/ClamshellToggle"
PLIST_PATH="$HOME/Library/LaunchAgents/com.user.clamshell-toggle.plist"
LABEL="com.user.clamshell-toggle"

echo "=> Clamshell Toggle installer"

if [[ "$(uname)" != "Darwin" ]]; then
  echo "Error: macOS only." >&2
  exit 1
fi

if ! command -v swiftc >/dev/null 2>&1; then
  echo "Error: swiftc not found. Install Xcode Command Line Tools:" >&2
  echo "  xcode-select --install" >&2
  exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd || echo "")"
if [[ -f "$SCRIPT_DIR/Sources/App.swift" && -f "$SCRIPT_DIR/Resources/Info.plist" ]]; then
  echo "=> Using local sources"
  SRC="$SCRIPT_DIR"
else
  echo "=> Downloading sources from GitHub"
  curl -fsSL "https://codeload.github.com/$REPO/tar.gz/refs/heads/main" -o "$WORK/src.tgz"
  tar -xzf "$WORK/src.tgz" -C "$WORK"
  SRC="$(find "$WORK" -type d -name 'clamshell-toggle-*' | head -1)"
  if [[ -z "$SRC" || ! -f "$SRC/Sources/App.swift" ]]; then
    echo "Error: could not download the source." >&2
    exit 1
  fi
fi

echo "=> Compiling"
mkdir -p "$WORK/build"
swiftc -O -o "$WORK/build/ClamshellToggle" "$SRC"/Sources/*.swift

echo "=> Replacing $APP_PATH"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
osascript -e 'quit app "Clamshell Toggle"' >/dev/null 2>&1 || true
killall ClamshellToggle >/dev/null 2>&1 || true
sleep 0.3
rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$WORK/build/ClamshellToggle" "$BIN_PATH"
cp "$SRC/Resources/Info.plist" "$APP_PATH/Contents/Info.plist"
chmod +x "$BIN_PATH"
codesign --force --sign - "$APP_PATH" >/dev/null 2>&1 || true

echo "=> Installing LaunchAgent"
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key><string>$LABEL</string>
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

launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH" 2>/dev/null || launchctl load "$PLIST_PATH" 2>/dev/null || true

echo "=> Checking passwordless pmset"
CURRENT="$(pmset -g | awk '/SleepDisabled/ { print $2; exit }')"
CURRENT="${CURRENT:-0}"
if sudo -n /usr/bin/pmset disablesleep "$CURRENT" >/dev/null 2>&1; then
  echo "   Permission already in place."
else
  echo "   Requesting sudo once to install /etc/sudoers.d/clamshell"
  echo "$USER ALL=(root) NOPASSWD: /usr/bin/pmset disablesleep *" | sudo tee /etc/sudoers.d/clamshell >/dev/null
  sudo chmod 0440 /etc/sudoers.d/clamshell
  if ! sudo visudo -cf /etc/sudoers.d/clamshell >/dev/null 2>&1; then
    echo "   The sudoers rule did not validate. Removing it." >&2
    sudo rm -f /etc/sudoers.d/clamshell
    exit 1
  fi
  sudo -n /usr/bin/pmset disablesleep "$CURRENT" >/dev/null
fi

echo ""
echo "Installed. A laptop mark in the menu bar is Clamshell Toggle."
echo "Open Settings from that menu for the timer, schedule, and agents."
echo ""
echo "Uninstall:"
echo "  curl -fsSL https://raw.githubusercontent.com/$REPO/main/uninstall.sh | bash"
