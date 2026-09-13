# LootDetect - README

## What this is

A single, self-contained Windower 4 addon that watches chat for item
drops and shows a small fading toast (icon + item name, on a styled
background panel) on screen when you get one. Multiple drops at once
stack vertically.

This is the merged/standalone version of what started as two addons
(a MogWatch-integrated detector + a separate LootPopup display addon).
Everything now lives in one file with no dependency on MogWatch or
anything else - just this one addon.

## Install

1. Copy this whole `lootdetect` folder into:
   ```
   Windower4/addons/
   ```

   **The folder name must exactly match the file name** (`lootdetect`,
   all lowercase) and sit directly inside `addons/` - Windower won't
   load it otherwise.

   Final layout:
   ```
   addons/lootdetect/lootdetect.lua
   addons/lootdetect/assets/white_pixel.png
   addons/lootdetect/icons/<item_id>.png   (optional, see below)
   ```

2. In game:
   ```
   //lua load lootdetect
   ```

3. Whenever you replace `lootdetect.lua` with an updated version:
   ```
   //lua reload lootdetect
   ```
   (Windower doesn't pick up file changes on its own.)

## Item icons (optional)

Icons are just PNG files named by item ID (e.g. `4102.png`) sitting in
the `icons` folder. If a file isn't there for a given item, the popup
just shows text with no icon - it won't error.

To populate this folder, the item's icon needs to be sourced from
somewhere like a wiki (fan-wiki icons are fine for personal use like
this, not for redistribution). Coverage will never be 100% - some
items just don't have a findable icon - and that's fine.

## Commands

| Command | Description |
|---|---|
| `//lootdetect test [count]` | Shows fake test popup(s) - e.g. `//lootdetect test 4` shows four stacked popups, without needing a real drop. |
| `//lootdetect show <item_id> <item name...>` | Manually trigger a popup with a specific id/name. |
| `//lootdetect move` | Shows a draggable yellow handle. Left-click and drag it wherever you want the popup list to appear, then run `//lootdetect move` again to lock it in. Saved automatically, persists across restarts. |
| `//lootdetect mousedebug` | Toggles a diagnostic print of raw mouse-event data - only needed if dragging ever stops responding correctly. |
| `//lootdetect style [name]` | With no name: lists the current style and all options. With a name: switches style (saved). Options: `steel` (default), `gold`, `shadow`, `royal`, `emerald`. |
| `//lootdetect duration [seconds]` | With no number: shows the current display duration. With a number: sets how long a popup stays fully visible before fading out (e.g. `//lootdetect duration 5`). Saved per character - each character on your account remembers its own value. |
| `//lootdetect debugall` | Prints the chat "mode" number and raw text of **every** chat line - very spammy, but the fastest way to find a drop message format that isn't triggering a popup. Turn it back off when done. |

## Appearance settings

A few things aren't exposed as commands, to keep things simple, but
can be hand-edited in the `CONFIG` block near the top of
`lootdetect.lua`:

| Setting | Description |
|---|---|
| `ROW_HEIGHT` | vertical spacing between stacked popups |
| `ICON_SIZE` | displayed icon size in pixels |
| `FADE_IN` | fade-in duration (seconds) |
| `FADE_OUT` | fade-out duration (seconds) |
| `FONT_SIZE` | text size |
| `PADDING` | space between the panel edge and its contents |

(How long a popup stays fully visible is controlled by `//lootdetect
duration` instead - see Commands above - since that's saved per
character rather than being a fixed setting.)

Remember to `//lua reload lootdetect` after editing.

## What triggers a popup

The addon listens for several different in-game message shapes and
treats all of them as a drop:

- Enemy loot: `"<Player> obtains <item>."` (chat mode 127)
- A second personal-drop message channel using the same phrasing
  (chat mode 121 - e.g. some monster mechanics route drops this way
  instead of mode 127)
- Personal drops: `"You obtain (x) <item>."`
- Chest/NPC drops: `"Obtained: <item>"`
- Temporary-item personal drops: `"<Player> obtains the temporary
  item: <item>"` (the descriptive "the temporary item:" phrase is
  stripped so the real item name is used)

Item names are matched against Windower's own resource library to
resolve the correct item ID and the correctly-capitalized display name
(so things like roman numerals - "Moglophone II" - display correctly
instead of getting mangled by simple text capitalization).

If you ever hit a drop that doesn't trigger a popup, `//lootdetect
debugall` on that exact drop will show the chat mode number and raw
text needed to add a new pattern for it.

## Known limitations

- Item icon coverage depends entirely on what's in the `icons` folder
  - there's no built-in way to fetch these automatically from within
    the addon itself.
- Drop detection is chat-text based, so any FFXI message format not
  already covered above (see "What triggers a popup") needs a new
  pattern added to work.
