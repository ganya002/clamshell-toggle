# Clamshell Toggle

A tiny native macOS menu bar app to enable **lid-closed (clamshell) mode on battery**.

Normally macOS sleeps when you close the lid unless you're on AC power + external display. This app flips `pmset disablesleep` with one click and keeps it toggleable from the menu bar.

<img width="400" alt="menu bar showing Clamshell ON" src="https://via.placeholder.com/600x120?text=Clamshell+ON+%2F+OFF+in+menu+bar">

## One-click install

```bash
curl -fsSL https://raw.githubusercontent.com/ganya002/clamshell-toggle/main/install.sh | bash
```

Or clone and run locally:

```bash
git clone https://github.com/ganya002/clamshell-toggle.git
cd clamshell-toggle
./install.sh
```

What the installer does:
1. Compiles `Sources/main.swift` with `swiftc` (requires Xcode Command Line Tools: `xcode-select --install`)
2. Creates `~/Applications/Clamshell Toggle.app` (no Dock icon, menu bar only)
3. Installs a LaunchAgent (`~/Library/LaunchAgents/com.user.clamshell-toggle.plist`) so it auto-starts at login
4. Adds a narrow sudoers rule so toggling doesn't prompt for a password:
   ```
   $USER ALL=(root) NOPASSWD: /usr/bin/pmset disablesleep *
   ```

Look for **Clamshell ON / OFF** in the menu bar. Click to toggle.

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/ganya002/clamshell-toggle/main/uninstall.sh | bash
# or if you cloned:
./uninstall.sh
```

This removes the app, the LaunchAgent, the sudoers rule, and restores `sudo pmset disablesleep 0`.

## Manual toggle

```bash
sudo pmset disablesleep 1  # enable clamshell on battery
sudo pmset disablesleep 0  # restore normal sleep
pmset -g | grep SleepDisabled
```

## How it works

- `pmset -g` → checks for `SleepDisabled 1`
- `sudo -n pmset disablesleep 1|0` → toggles (passwordless via `/etc/sudoers.d/clamshell`)
- `NSStatusItem` (AppKit) with `LSUIElement=true` (menu bar only)

## Requirements

- macOS 13+
- Xcode Command Line Tools (`xcode-select --install`)

## Notes

- Clamshell on battery runs hotter with the lid closed — ensure ventilation.
- The sudoers rule is scoped to `pmset disablesleep` only.
- `pmset disablesleep` is system-wide; there is no per-power-source variant on current macOS.

## License

MIT
