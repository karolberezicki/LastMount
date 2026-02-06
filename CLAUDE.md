# LastMount - WoW Addon

## Overview
Tracks the player's last used mount and resummons it via `/click LastMountButton` macro. Supports a fallback mount and a mount blacklist.

## Architecture
Single-file Lua addon (`LastMount.lua`) with no external dependencies.

### Key components
- **Mount Detection**: `UNIT_SPELLCAST_SUCCEEDED` (spell-to-mount lookup) + `COMPANION_UPDATE` (active mount scan)
- **Mount Button**: Plain `CreateFrame("Button")` — NOT SecureActionButtonTemplate. The hardware event from `/click` macro propagates to OnClick, allowing `C_MountJournal.SummonByID()` calls.
- **Options Panel**: Custom canvas frame registered via `Settings.RegisterCanvasLayoutCategory`
- **SavedVariables**: `LastMountDB` table with `lastMountID`, `fallbackMountID`, `blacklist`

### Event flow
1. `ADDON_LOADED` → `InitDB()`, `CreateMountButton()`, `CreateOptionsPanel()`
2. `PLAYER_LOGIN` → `ValidateStoredMounts()`, `RegisterSlashCommands()`
3. `UNIT_SPELLCAST_SUCCEEDED` / `COMPANION_UPDATE` → detect and save current mount

## WoW API notes

### Mount IDs vs Spell IDs
- Internal logic uses **mount journal IDs** (for `SummonByID`, `GetMountInfoByID`)
- User-facing displays show **spell IDs** (matches Wowhead URLs)
- `C_MountJournal.GetMountInfoByID` returns: name(1), spellID(2), icon(3), isActive(4), isUsable(5), sourceType(6), isFavorite(7), ..., isCollected(11)

### Settings API
- `Settings.RegisterCanvasLayoutCategory(frame, name)` → category object
- `Settings.RegisterAddOnCategory(category)` → places in AddOns tab
- `Settings.OpenToCategory(category:GetID())` → opens directly (single call, no workarounds needed)

## Critical Lua pattern
**Declare all shared `local` variables at the top of the file.** Lua closures capture locals in scope at function definition time. A function defined on line 100 cannot see a `local` declared on line 200 — it silently reads a global (nil) instead. This has caused real bugs in this addon.

## Slash commands
- `/lastmount` — open options panel
- `/lastmount help` — show status + usage
- `/lastmount fallback <name|spellID>` / `reset`
- `/lastmount blacklist add|remove|list <name|spellID>`

## Files
- `LastMount.toc` — addon metadata, Interface: 120000
- `LastMount.lua` — all logic in one file
