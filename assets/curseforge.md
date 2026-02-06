# LastMount

Automatically remembers your last used mount and resummons it with a single macro. No more random mount roulette — always get back on the mount you were just riding.

## Setup

Create a macro with this single line:

```
/click LastMountButton
```

Drag it to your action bar. That's it — clicking it summons your last used mount, or dismounts if already mounted.

## Features

- **Auto-tracking** — detects your mount the moment you use it, no configuration needed
- **Fallback mount** — set a default mount for when no last mount is recorded (e.g. after a fresh install)
- **Blacklist** — prevent specific mounts from being tracked as your "last mount"
- **Options panel** — configure everything from ESC > Options > AddOns > LastMount
- **Spell ID support** — set fallback or blacklist entries by mount name or Wowhead spell ID

## Slash Commands

| Command | Description |
|---|---|
| `/lastmount` | Open options panel |
| `/lastmount help` | Show status and all commands |
| `/lastmount fallback <name or id>` | Set fallback mount |
| `/lastmount fallback reset` | Clear fallback mount |
| `/lastmount blacklist add <name or id>` | Blacklist a mount |
| `/lastmount blacklist remove <name or id>` | Remove from blacklist |
| `/lastmount blacklist list` | Show blacklisted mounts |

## How It Works

When you mount up, LastMount saves that mount's ID. Next time you use the macro, it summons that exact mount. If the mount is no longer collected, it falls back to your configured fallback mount, or random mount (ID 0) if no fallback is set.

Blacklisted mounts are ignored by the tracker — useful if you occasionally use a mount you don't want as your default (e.g. a slow or situational mount).

## Lightweight

Single Lua file, no libraries, no dependencies. Uses only `LastMountDB` saved variable.
