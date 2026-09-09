# Clamshell Toggle

A tiny native macOS menu bar utility that lets your Mac stay awake with the lid closed — including while running on battery.

Clamshell Toggle uses macOS `pmset disablesleep` and lives entirely in the menu bar. Version 2 replaces the old `Clamshell ON/OFF` text with a compact icon so it barely takes any space.

## What the menu bar icon means

- **Laptop icon** — Clamshell Mode is ON; system sleep is disabled.
- **Moon icon** — Clamshell Mode is OFF; normal sleep behavior is restored.
- **Question mark** — the current `pmset` state could not be read.

Click the icon to see the current state, power source, battery percentage, and toggle control.

## Features

- Tiny icon-only native menu bar UI
- One-click Clamshell Mode ON/OFF
- Battery percentage + Battery/Power Adapter status
- Warning when Clamshell Mode is active while running on battery
- Automatic status refresh every 60 seconds and whenever the menu opens
- Starts automatically when you log in
- No Dock icon
- Native AppKit app with no external runtime or dependencies
- Narrow sudo permission limited to exactly:
  - `/usr/bin/pmset disablesleep 0`
  - `/usr/bin/pmset disablesleep 1`
- Installer preserves your current sleep state instead of enabling Clamshell Mode during setup

## Install / update

```bash
curl -fsSL https://raw.githubusercontent.com/ganya002/clamshell-toggle/main/install.sh | bash
```

Or clone it:

```bash
git clone https://github.com/ganya002/clamshell-toggle.git
cd clamshell-toggle
./install.sh
```

The installer:

1. Compiles `Sources/main.swift` with Apple's Swift compiler.
2. Creates `~/Applications/Clamshell Toggle.app`.
3. Installs a LaunchAgent so the app starts at login.
4. Creates a narrowly scoped sudoers rule after validating it with `visudo`.
5. Verifies the permission while preserving your current `SleepDisabled` state.
6. Starts the menu bar app.

Installing over an older version upgrades it in place.

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/ganya002/clamshell-toggle/main/uninstall.sh | bash
```

Or, from a clone:

```bash
./uninstall.sh
```

Uninstalling restores normal sleep first, then removes the app, LaunchAgent, and sudoers rule.

## Manual commands

```bash
sudo pmset disablesleep 1  # Clamshell Mode ON
sudo pmset disablesleep 0  # restore normal sleep
pmset -g | grep SleepDisabled
pmset -g batt              # power source + battery state
```

## Requirements

- macOS 13 or newer
- Xcode Command Line Tools (`xcode-select --install`)

## How it works

The app is a small AppKit `NSStatusItem` application with `LSUIElement=true`, so there is no Dock icon. It reads `pmset -g` to determine whether sleep is disabled and runs only one of two passwordless commands when you toggle the setting.

The sudoers entry is:

```text
$USER ALL=(root) NOPASSWD: /usr/bin/pmset disablesleep 0, /usr/bin/pmset disablesleep 1
```

No general passwordless `sudo` access is granted.

## Important

Keeping a Mac awake with the lid closed while on battery can drain the battery quickly and may increase heat. Make sure the Mac has reasonable ventilation.

`pmset disablesleep` is system-wide. Quitting Clamshell Toggle does **not** change the current state; the menu explicitly says this so the setting is not changed unexpectedly.

## License

MIT
