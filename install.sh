#!/bin/bash
set -euo pipefail

# Clamshell Toggle — one-line install for macOS
# Repo: https://github.com/ganya002/clamshell-toggle
#
# Usage:
#   ./install.sh            full install (asks for sudo once)
#   ./install.sh --update   rebuild and swap the app in place; no sudo, no restart
#                           (the running app uses this to update itself)

REPO="ganya002/clamshell-toggle"
APP_NAME="Clamshell Toggle.app"
APP_PATH="$HOME/Applications/$APP_NAME"
BIN_PATH="$APP_PATH/Contents/MacOS/ClamshellToggle"
PLIST_PATH="$HOME/Library/LaunchAgents/com.user.clamshell-toggle.plist"
SUDOERS_PATH="/etc/sudoers.d/clamshell"
LABEL="com.user.clamshell-toggle"

UPDATE_MODE=false
if [[ "${1:-}" == "--update" ]]; then
  UPDATE_MODE=true
fi

if [[ "$UPDATE_MODE" == true ]]; then
  printf '%s\n' "=> Clamshell Toggle updater"
  if [[ ! -d "$APP_PATH" ]]; then
    printf '%s\n' "Error: $APP_PATH is not installed. Run the full installer." >&2
    exit 1
  fi
else
  printf '%s\n' "=> Clamshell Toggle installer"
fi

if [[ "$(uname)" != "Darwin" ]]; then
  printf '%s\n' "Error: macOS only." >&2
  exit 1
fi

if [[ ! -x /usr/bin/xcrun || ! -x /usr/sbin/visudo ]]; then
  printf '%s\n' "Error: Xcode Command Line Tools are missing. Run: xcode-select --install" >&2
  exit 1
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd || true)"
if [[ -n "$SCRIPT_DIR" && -f "$SCRIPT_DIR/Sources/App.swift" && -f "$SCRIPT_DIR/Resources/Info.plist" ]]; then
  printf '%s\n' "=> Using local sources"
  SRC="$SCRIPT_DIR"
elif [[ "$UPDATE_MODE" == true ]]; then
  printf '%s\n' "Error: update mode needs the sources next to the script." >&2
  exit 1
else
  printf '%s\n' "=> Downloading sources from GitHub"
  curl -fsSL "https://codeload.github.com/$REPO/tar.gz/refs/heads/main" -o "$TMP_DIR/src.tgz"
  tar -xzf "$TMP_DIR/src.tgz" -C "$TMP_DIR"
  SRC="$(find "$TMP_DIR" -type d -name 'clamshell-toggle-*' | head -n 1)"
fi

if [[ -z "${SRC:-}" || ! -f "$SRC/Sources/App.swift" ]]; then
  printf '%s\n' "Error: could not find the app sources." >&2
  exit 1
fi

mkdir -p "$TMP_DIR/src"
cp "$SRC"/Sources/*.swift "$TMP_DIR/src/"
cp "$SRC/Resources/Info.plist" "$TMP_DIR/Info.plist"

CURRENT_DEV_DIR="$(xcode-select -p 2>/dev/null || true)"
TOOLCHAIN_CANDIDATES=()
if [[ -n "$CURRENT_DEV_DIR" && "$CURRENT_DEV_DIR" != "/Library/Developer/CommandLineTools" ]]; then
  TOOLCHAIN_CANDIDATES+=("$CURRENT_DEV_DIR")
fi
[[ -d "/Applications/Xcode-beta.app/Contents/Developer" ]] && TOOLCHAIN_CANDIDATES+=("/Applications/Xcode-beta.app/Contents/Developer")
[[ -d "/Applications/Xcode.app/Contents/Developer" ]] && TOOLCHAIN_CANDIDATES+=("/Applications/Xcode.app/Contents/Developer")
[[ -n "$CURRENT_DEV_DIR" ]] && TOOLCHAIN_CANDIDATES+=("$CURRENT_DEV_DIR")
while IFS= read -r xcode_app; do
  candidate="$xcode_app/Contents/Developer"
  [[ -d "$candidate" ]] && TOOLCHAIN_CANDIDATES+=("$candidate")
done < <(/usr/bin/find /Applications -maxdepth 1 -type d -name 'Xcode*.app' -print 2>/dev/null || true)

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
  printf '%s\n' "Error: no Swift toolchain found. Install Xcode or run: xcode-select --install" >&2
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

  printf '%s\n' "=> Compiling"
  printf '   Toolchain: %s\n' "$developer_dir"

  DEVELOPER_DIR="$developer_dir" /usr/bin/xcrun --sdk macosx swiftc \
    -Onone \
    -framework AppKit \
    -o "$TMP_DIR/ClamshellToggle" \
    "$TMP_DIR"/src/*.swift >"$compile_log" 2>&1 &
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

  (
    sleep 60
    if kill -0 "$compile_pid" 2>/dev/null; then
      : > "$timeout_flag"
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
    printf '%s\n' "   That toolchain stalled. Trying another…" >&2
    return 124
  fi
  if [[ "$compile_status" -ne 0 ]]; then
    printf '   Compile failed with exit %s.\n' "$compile_status" >&2
    [[ -s "$compile_log" ]] && sed 's/^/   /' "$compile_log" >&2
    return "$compile_status"
  fi
  [[ -x "$TMP_DIR/ClamshellToggle" ]]
}

COMPILED=false
USED_DEV_DIR=""
for developer_dir in "${UNIQUE_TOOLCHAINS[@]}"; do
  if compile_with_toolchain "$developer_dir"; then
    COMPILED=true
    USED_DEV_DIR="$developer_dir"
    break
  fi
done

if [[ "$COMPILED" != true ]]; then
  printf '%s\n' "Error: Swift could not build Clamshell Toggle." >&2
  printf '%s\n' "This app needs macOS 26 or later." >&2
  exit 1
fi

if [[ "$UPDATE_MODE" == true ]]; then
  printf '%s\n' "=> Swapping in the new build"
  STAGE_PATH="$(dirname "$APP_PATH")/.Clamshell Toggle.app.updating"
  OLD_PATH="$(dirname "$APP_PATH")/.Clamshell Toggle.app.old"
  rm -rf "$STAGE_PATH" "$OLD_PATH"
  mkdir -p "$STAGE_PATH/Contents/MacOS" "$STAGE_PATH/Contents/Resources"
  cp "$TMP_DIR/ClamshellToggle" "$STAGE_PATH/Contents/MacOS/ClamshellToggle"
  cp "$TMP_DIR/Info.plist" "$STAGE_PATH/Contents/Info.plist"
  chmod +x "$STAGE_PATH/Contents/MacOS/ClamshellToggle"
  codesign --force --sign - "$STAGE_PATH" >/dev/null 2>&1 || true
  mv "$APP_PATH" "$OLD_PATH"
  if ! mv "$STAGE_PATH" "$APP_PATH"; then
    mv "$OLD_PATH" "$APP_PATH"
    printf '%s\n' "Error: could not move the new build into place." >&2
    exit 1
  fi
  rm -rf "$OLD_PATH"
  printf '%s\n' "Updated with $USED_DEV_DIR"
  exit 0
fi

printf '%s\n' "=> Replacing $APP_PATH"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
osascript -e 'quit app "Clamshell Toggle"' >/dev/null 2>&1 || true
killall ClamshellToggle >/dev/null 2>&1 || true
sleep 0.3
rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$TMP_DIR/ClamshellToggle" "$BIN_PATH"
cp "$TMP_DIR/Info.plist" "$APP_PATH/Contents/Info.plist"
chmod +x "$BIN_PATH"
codesign --force --sign - "$APP_PATH" >/dev/null 2>&1 || true

printf '%s\n' "=> Installing LaunchAgent"
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
	<key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
	<key>LimitLoadToSessionType</key><string>Aqua</string>
</dict>
</plist>
EOF
plutil -lint "$PLIST_PATH" >/dev/null

CURRENT_STATE="$(/usr/bin/pmset -g | awk '/SleepDisabled/{print $2; exit}')"
if [[ "$CURRENT_STATE" != "1" ]]; then
  CURRENT_STATE="0"
fi

printf '%s\n' "=> Configuring passwordless pmset (sudo once)"
SUDO_RULE="$(id -un) ALL=(root) NOPASSWD: /usr/bin/pmset disablesleep 0, /usr/bin/pmset disablesleep 1"
printf '%s\n' "$SUDO_RULE" > "$TMP_DIR/clamshell-sudoers"
chmod 0440 "$TMP_DIR/clamshell-sudoers"
if ! /usr/sbin/visudo -cf "$TMP_DIR/clamshell-sudoers" >/dev/null; then
  printf '%s\n' "Error: the sudoers rule did not validate." >&2
  exit 1
fi
sudo install -o root -g wheel -m 0440 "$TMP_DIR/clamshell-sudoers" "$SUDOERS_PATH"
sudo /usr/sbin/visudo -cf "$SUDOERS_PATH" >/dev/null
if ! sudo -n /usr/bin/pmset disablesleep "$CURRENT_STATE"; then
  printf '%s\n' "Error: the passwordless permission test failed." >&2
  exit 1
fi

printf '%s\n' "=> Starting Clamshell Toggle"
launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH" 2>/dev/null || launchctl load "$PLIST_PATH" 2>/dev/null || true

printf '\n%s\n' "Installed with $USED_DEV_DIR"
printf '%s\n' "The menu bar mark is an outline when the Mac can sleep, and filled when the lid is being kept awake."
printf '%s\n' "Everything, including the timer, the schedule, and agents, is in that menu."
printf '%s\n' "The app checks for updates by itself. Turn that off from the same menu."
printf '\n%s\n' "Uninstall: curl -fsSL https://raw.githubusercontent.com/$REPO/main/uninstall.sh | bash"
