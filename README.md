# Clamshell Toggle

A native macOS menu bar app that keeps the lid awake on battery. Close the laptop, leave it running, and turn that back off when you are done.

The menu bar mark is an outline when the machine can sleep, and filled when the lid is being kept awake. The menu also shows whether you are on battery. Settings is a regular glass panel with three tabs:

- **Time.** Spin the dial, or type a duration, to keep the lid awake for 1 hour, 2 hours, 4 hours, or anything from 5 minutes to 8 hours.
- **Schedule.** Pick the days and the hours. An overnight block runs through the next morning.
- **Agents.** While a local agent is actually working, the lid stays awake. When it exits, sleep comes back. Cursor, Claude, Codex, Aider, Gemini, and a few others are recognized. An idle Cursor worker does not count. You can add other program names.

Turning it off from the menu pauses the schedule or the agent watch until that block or that run ends, so it does not immediately switch itself back on.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/ganya002/clamshell-toggle/main/install.sh | bash
```

Or from a checkout:

```bash
git clone https://github.com/ganya002/clamshell-toggle.git
cd clamshell-toggle
./install.sh
```

The installer compiles the app, puts it in `~/Applications`, starts it at login, and adds one sudoers rule so toggling does not ask for a password:

```
$USER ALL=(root) NOPASSWD: /usr/bin/pmset disablesleep *
```

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/ganya002/clamshell-toggle/main/uninstall.sh | bash
```

That removes the app, the login item, and the sudoers rule, and restores normal sleep.

## Requirements

- macOS 26 or later
- Xcode Command Line Tools (`xcode-select --install`)

A closed lid runs warmer. Give the machine some air.

## License

MIT
