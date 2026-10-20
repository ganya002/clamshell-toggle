# Clamshell Toggle

A native macOS menu bar app that keeps the lid awake on battery. Close the laptop, leave it running, and turn that back off when you are done.

The menu bar mark is an outline when the machine can sleep, and filled when the lid is being kept awake. Everything lives in that one menu, with no separate window:

- **Turn On / Turn Off.** Keep the lid awake until you turn it off.
- **Keep Awake For.** Pick 15 minutes up to 8 hours, or choose Custom… and type a duration such as `45m` or `1h 30m`. While a timer runs, the menu shows the time left and a Stop Timer item.
- **Schedule.** Pick the days, then Set Hours…. An overnight block runs through the next morning.
- **Agents.** While a local agent is actually running, the lid stays awake. When it exits, sleep comes back. Cursor, Claude, Codex, Aider, Gemini, Copilot, OpenCode, Cline, Kiro, Qwen, Kimi, and many others are recognized, including when they start through node, bun, python, or npx. Desktop apps, MCP servers, and app servers do not count. An idle Cursor worker does not count. Add Other Programs… lets you name more.
- **Power.** The menu also shows whether you are on battery, and warns that a closed lid on battery drains faster.

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
$USER ALL=(root) NOPASSWD: /usr/bin/pmset disablesleep 0, /usr/bin/pmset disablesleep 1
```

## Updates

The app checks GitHub for a newer version a minute after it starts, then every 6 hours. When it finds one, it downloads the source, builds it with the same toolchain as the installer, swaps it into `~/Applications`, and restarts. No password is needed.

A new version is any commit on `main` that raises `CFBundleVersion` in `Resources/Info.plist`.

The menu has two items for this. **Check for Updates…** runs a check now and asks before it updates. **Update Automatically** turns the background checks off. If a build fails, the app does not retry that version for 24 hours.

Versions before 2.2.0 cannot update themselves. Run the installer once to get 2.2.0.

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
