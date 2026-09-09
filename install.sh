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

# Full Swift optimization is pointless for this tiny utility and can be painfully slow
# on beta Xcode/Swift toolchains. -Onone produces the same app behavior and installs much faster.
printf '%s\n' "=> Compiling native menu bar app (fast build)"
printf '   %s\n' "$(swiftc --version 2>/dev/null | head -n 1 || echo 'Swift version unknown')"
COMPILE_LOG="$TMP_DIR/swiftc.log"
TIMEOUT_FLAG="$TMP_DIR/compile-timeout"

swiftc -Onone -framework AppKit -o "$TMP_DIR/ClamshellToggle" "$TMP_DIR/main.swift" >"$COMPILE_LOG" 2>&1 &
COMPILE_PID=$!

# Give useful feedback instead of appearing frozen.
(
  while kill -0 "$COMPILE_PID" 2>/dev/null; do
    sleep 5
    if kill -0 "$COMPILE_PID" 2>/dev/null; then
      printf '%s\n' "   …still compiling"
    fi
  done
) &
PROGRESS_PID=$!

# A 2 minute compile for this app means the local Swift toolchain is unhealthy/stuck.
(
  sleep 120
  if kill -0 "$COMPILE_PID" 2>/dev/null; then
    : > "$TIMEOUT_FLAG"
    /usr/bin/pkill -TERM -P "$COMPILE_PID" 2>/dev/null || true
    kill -TERM "$COMPILE_PID" 2>/dev/null || true
  fi
) &
WATCHDOG_PID=$!

set +e
wait "$COMPILE_PID"
COMPILE_STATUS=$?
set -e

kill "$PROGRESS_PID" "$WATCHDOG_PID" 2>/dev/null || true
wait "$PROGRESS_PID" "$WATCHDOG_PID" 2>/dev/null || true

if [[ -f "$TIMEOUT_FLAG" ]]; then
  printf '%s\n' "Error: Swift compilation took longer than 2 minutes and was stopped." >&2
  printf '%s\n' "This usually points to a stuck/broken Xcode or Command Line Tools installation." >&2
  printf '%s\n' "Selected developer directory: $(xcode-select -p 2>/dev/null || echo 'unknown')" >&2
  if [[ -s "$COMPILE_LOG" ]]; then
    printf '%s\n' "--- swiftc output ---" >&2
    cat "$COMPILE_LOG" >&2
  fi
  printf '%s\n' "Try: sudo xcodebuild -runFirstLaunch" >&2
  printf '%s\n' "Then run this installer again." >&2
  exit 1
fi

if [[ "$COMPILE_STATUS" -ne 0 ]]; then
  printf '%s\n' "Error: Swift compilation failed (exit $COMPILE_STATUS)." >&2
  printf '%s\n' "Selected developer directory: $(xcode-select -p 2>/dev/null || echo 'unknown')" >&2
  if [[ -s "$COMPILE_LOG" ]]; then
    printf '%s\n' "--- swiftc output ---" >&2
    cat "$COMPILE_LOG" >&2
  fi
  exit "$COMPILE_STATUS"
fi

printf '%s\n' "=> Native app compiled successfully"

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
