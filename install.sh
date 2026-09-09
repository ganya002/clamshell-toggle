#!/bin/bash
set -euo pipefail

# Clamshell Toggle — one-click installer for macOS
# Builds a tiny native menu bar app that toggles `pmset disablesleep`.
# Repo: https://github.com/ganya002/clamshell-toggle

REPO="ganya002/clamshell-toggle"
APP_NAME="Clamshell Toggle.app"
APP_PATH="$HOME/Applications/$APP_NAME"
BIN_PATH="$APP_PATH/Contents/MacOS/ClamshellToggle"
PLIST_PATH="$HOME/Library/LaunchAgents/com.user.clamshell-toggle.plist"
SUDOERS_PATH="/etc/sudoers.d/clamshell"

printf '%s\n' "=> Clamshell Toggle installer"

if [[ "$(uname)" != "Darwin" ]]; then
  printf '%s\n' "Error: macOS only." >&2
  exit 1
fi

if ! command -v swiftc >/dev/null 2>&1; then
  printf '%s\n' "Error: swiftc not found. Install Xcode Command Line Tools:" >&2
  printf '%s\n' "  xcode-select --install" >&2
  exit 1
fi

if [[ ! -x /usr/sbin/visudo ]]; then
  printf '%s\n' "Error: /usr/sbin/visudo not found." >&2
  exit 1
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd || true)"
if [[ -n "$SCRIPT_DIR" && -f "$SCRIPT_DIR/Sources/main.swift" && -f "$SCRIPT_DIR/Resources/Info.plist" ]]; then
  printf '%s\n' "=> Using local sources"
  cp "$SCRIPT_DIR/Sources/main.swift" "$TMP_DIR/main.swift"
  cp "$SCRIPT_DIR/Resources/Info.plist" "$TMP_DIR/Info.plist"
else
  printf '%s\n' "=> Downloading sources from GitHub"
  curl -fsSL "https://raw.githubusercontent.com/$REPO/main/Sources/main.swift" -o "$TMP_DIR/main.swift"
  curl -fsSL "https://raw.githubusercontent.com/$REPO/main/Resources/Info.plist" -o "$TMP_DIR/Info.plist"
fi

printf '%s\n' "=> Compiling native menu bar app"
swiftc -O -framework AppKit -o "$TMP_DIR/ClamshellToggle" "$TMP_DIR/main.swift"

printf '%s\n' "=> Creating app bundle at $APP_PATH"
rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$TMP_DIR/ClamshellToggle" "$BIN_PATH"
cp "$TMP_DIR/Info.plist" "$APP_PATH/Contents/Info.plist"
chmod +x "$BIN_PATH"

# Ad-hoc signing is enough for a locally built personal utility.
codesign --force --sign - "$APP_PATH" 2>/dev/null || true

printf '%s\n' "=> Installing LaunchAgent (start at login)"
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

plutil -lint "$PLIST_PATH" >/dev/null

# Preserve the user's current sleep state while installing/updating permissions.
CURRENT_STATE="$(/usr/bin/pmset -g | awk '/SleepDisabled/{print $2; exit}')"
if [[ "$CURRENT_STATE" != "1" ]]; then
  CURRENT_STATE="0"
fi

printf '%s\n' "=> Configuring narrow passwordless pmset permission (sudo once)"
SUDO_RULE="$(id -un) ALL=(root) NOPASSWD: /usr/bin/pmset disablesleep 0, /usr/bin/pmset disablesleep 1"
printf '%s\n' "$SUDO_RULE" > "$TMP_DIR/clamshell-sudoers"
chmod 0440 "$TMP_DIR/clamshell-sudoers"

if ! /usr/sbin/visudo -cf "$TMP_DIR/clamshell-sudoers" >/dev/null; then
  printf '%s\n' "Error: generated sudoers rule failed validation." >&2
  exit 1
fi

sudo install -o root -g wheel -m 0440 "$TMP_DIR/clamshell-sudoers" "$SUDOERS_PATH"
sudo /usr/sbin/visudo -cf "$SUDOERS_PATH" >/dev/null

# Verify the exact commands the app uses, without changing the current state.
if ! sudo -n /usr/bin/pmset disablesleep "$CURRENT_STATE"; then
  printf '%s\n' "Error: passwordless pmset permission test failed." >&2
  exit 1
fi

printf '%s\n' "=> Starting Clamshell Toggle"
launchctl bootout "gui/$(id -u)/com.user.clamshell-toggle" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH" 2>/dev/null || launchctl load "$PLIST_PATH" 2>/dev/null || true

printf '\n%s\n' "✓ Installed! Look for the small laptop/moon icon in your menu bar."
printf '%s\n' "  Laptop = clamshell mode ON. Moon = normal sleep."
printf '%s\n' "  Your previous sleep state was preserved during installation."
printf '\n%s\n' "  Uninstall: curl -fsSL https://raw.githubusercontent.com/$REPO/main/uninstall.sh | bash"
printf '%s\n' "  Repo: https://github.com/$REPO"
