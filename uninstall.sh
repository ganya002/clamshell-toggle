#!/bin/bash
set -e
APP_PATH="$HOME/Applications/Clamshell Toggle.app"
PLIST_PATH="$HOME/Library/LaunchAgents/com.user.clamshell-toggle.plist"

echo "=> Uninstalling Clamshell Toggle"

echo "-> Stopping LaunchAgent"
launchctl bootout "gui/$(id -u)/com.user.clamshell-toggle" 2>/dev/null || launchctl unload "$PLIST_PATH" 2>/dev/null || true

echo "-> Removing files"
rm -rf "$APP_PATH"
rm -f "$PLIST_PATH"

if [[ -f /etc/sudoers.d/clamshell ]]; then
  echo "-> Removing sudoers rule (requires sudo)"
  sudo rm -f /etc/sudoers.d/clamshell
  # restore normal sleep
  echo "-> Restoring normal sleep"
  sudo pmset disablesleep 0 2>/dev/null || sudo /usr/bin/pmset disablesleep 0 2>/dev/null || true
else
  # still try to re-enable sleep even without sudoers file
  sudo pmset disablesleep 0 2>/dev/null || true
fi

# also try without sudo for current state
pmset -g | grep SleepDisabled || true
echo "✓ Uninstalled."
