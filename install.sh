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

if [[ ! -x /usr/bin/xcrun ]]; then
  printf '%s\n' "Error: xcrun not found. Install Xcode Command Line Tools:" >&2
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

# On macOS betas, the standalone Command Line Tools can lag behind the installed
# OS/Xcode SDK and make swiftc appear to hang. Prefer a full Xcode installation
# when available, but do not change the user's global xcode-select setting.
CURRENT_DEV_DIR="$(xcode-select -p 2>/dev/null || true)"
TOOLCHAIN_CANDIDATES=()

if [[ -n "$CURRENT_DEV_DIR" && "$CURRENT_DEV_DIR" != "/Library/Developer/CommandLineTools" ]]; then
  TOOLCHAIN_CANDIDATES+=("$CURRENT_DEV_DIR")
fi

# Prefer Xcode beta on beta macOS, then stable Xcode.
[[ -d "/Applications/Xcode-beta.app/Contents/Developer" ]] && TOOLCHAIN_CANDIDATES+=("/Applications/Xcode-beta.app/Contents/Developer")
[[ -d "/Applications/Xcode.app/Contents/Developer" ]] && TOOLCHAIN_CANDIDATES+=("/Applications/Xcode.app/Contents/Developer")

# Finally fall back to whatever xcode-select currently points at, including CLT.
if [[ -n "$CURRENT_DEV_DIR" ]]; then
  TOOLCHAIN_CANDIDATES+=("$CURRENT_DEV_DIR")
fi

# Also discover unusually named Xcode apps such as "Xcode 26 beta.app".
while IFS= read -r xcode_app; do
  candidate="$xcode_app/Contents/Developer"
  [[ -d "$candidate" ]] && TOOLCHAIN_CANDIDATES+=("$candidate")
done < <(/usr/bin/find /Applications -maxdepth 1 -type d -name 'Xcode*.app' -print 2>/dev/null || true)

# Remove duplicate candidate paths while preserving order.
UNIQUE_TOOLCHAINS=()
for candidate in "${TOOLCHAIN_CANDIDATES[@]}"; do
  duplicate=false
  for existing in "${UNIQUE_TOOLCHAINS[@]:-}"; do
    if [[ "$existing" == "$candidate" ]]; then
      duplicate=true
      break
    fi
  done
  [[ "$duplicate" == false ]] && UNIQUE_TOOLCHAINS+=("$candidate")
done

if [[ ${#UNIQUE_TOOLCHAINS[@]} -eq 0 ]]; then
  printf '%s\n' "Error: no usable Apple developer toolchain found." >&2
  printf '%s\n' "Install Xcode or run: xcode-select --install" >&2
  exit 1
fi

compile_with_toolchain() {
  local developer_dir="$1"
  local compile_log="$TMP_DIR/swiftc.log"
  local timeout_flag="$TMP_DIR/compile-timeout"
  local compile_pid progress_pid watchdog_pid compile_status

  rm -f "$compile_log" "$timeout_flag" "$TMP_DIR/ClamshellToggle"

  if ! DEVELOPER_DIR="$developer_dir" /usr/bin/xcrun --sdk macosx --find swiftc >/dev/null 2>&1; then
    return 2
  fi

  printf '%s\n' "=> Compiling native menu bar app"
  printf '   Toolchain: %s\n' "$developer_dir"
  printf '   %s\n' "$(DEVELOPER_DIR="$developer_dir" /usr/bin/xcrun --sdk macosx swiftc --version 2>/dev/null | head -n 1 || echo 'Swift version unknown')"

  DEVELOPER_DIR="$developer_dir" /usr/bin/xcrun --sdk macosx swiftc \
    -Onone \
    -framework AppKit \
    -o "$TMP_DIR/ClamshellToggle" \
    "$TMP_DIR/main.swift" >"$compile_log" 2>&1 &
  compile_pid=$!

  (
    while kill -0 "$compile_pid" 2>/dev/null; do
      sleep 5
      if kill -0 "$compile_pid" 2>/dev/null; then
        printf '%s\n' "   …still compiling"
      fi
    done
  ) &
  progress_pid=$!

  # This source should compile quickly. If a toolchain stalls, try the next one.
  (
    sleep 45
    if kill -0 "$compile_pid" 2>/dev/null; then
      : > "$timeout_flag"
      /usr/bin/pkill -TERM -P "$compile_pid" 2>/dev/null || true
      kill -TERM "$compile_pid" 2>/dev/null || true
    fi
  ) &
  watchdog_pid=$!

  set +e
  wait "$compile_pid"
  compile_status=$?
  set -e

  kill "$progress_pid" "$watchdog_pid" 2>/dev/null || true
  wait "$progress_pid" "$watchdog_pid" 2>/dev/null || true

  if [[ -f "$timeout_flag" ]]; then
    printf '%s\n' "   Toolchain stalled after 45 seconds; trying another one…" >&2
    return 124
  fi

  if [[ "$compile_status" -ne 0 ]]; then
    printf '   Compile failed with exit %s.\n' "$compile_status" >&2
    if [[ -s "$compile_log" ]]; then
      sed 's/^/   /' "$compile_log" >&2
    fi
    return "$compile_status"
  fi

  [[ -x "$TMP_DIR/ClamshellToggle" ]]
}

COMPILED=false
for developer_dir in "${UNIQUE_TOOLCHAINS[@]}"; do
  if compile_with_toolchain "$developer_dir"; then
    COMPILED=true
    USED_DEV_DIR="$developer_dir"
    break
  fi
done

if [[ "$COMPILED" != true ]]; then
  printf '%s\n' "Error: every installed Swift toolchain failed or stalled." >&2
  printf '%s\n' "Current xcode-select path: ${CURRENT_DEV_DIR:-unknown}" >&2
  printf '%s\n' "If Xcode was just installed/updated, open it once and accept any setup prompts." >&2
  printf '%s\n' "You can also run: sudo xcodebuild -runFirstLaunch" >&2
  exit 1
fi

printf '%s\n' "=> Native app compiled successfully"
printf '   Used: %s\n' "$USED_DEV_DIR"

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

# Verify the exact command the app uses without changing the current state.
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
