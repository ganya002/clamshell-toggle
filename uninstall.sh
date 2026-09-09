#!/bin/bash
set -euo pipefail

APP_PATH="$HOME/Applications/Clamshell Toggle.app"
PLIST_PATH="$HOME/Library/LaunchAgents/com.user.clamshell-toggle.plist"
SUDOERS_PATH="/etc/sudoers.d/clamshell"

printf '%s\n' "=> Uninstalling Clamshell Toggle"

printf '%s\n' "-> Stopping LaunchAgent"
launchctl bootout "gui/$(id -u)/com.user.clamshell-toggle" 2>/dev/null || launchctl unload "$PLIST_PATH" 2>/dev/null || true

printf '%s\n' "-> Restoring normal sleep"
if ! sudo -n /usr/bin/pmset disablesleep 0 2>/dev/null; then
  sudo /usr/bin/pmset disablesleep 0
fi

if [[ -f "$SUDOERS_PATH" ]]; then
  printf '%s\n' "-> Removing sudoers rule"
  sudo rm -f "$SUDOERS_PATH"
fi

printf '%s\n' "-> Removing app and LaunchAgent"
rm -rf "$APP_PATH"
rm -f "$PLIST_PATH"

printf '%s\n' "✓ Uninstalled and restored normal sleep."
