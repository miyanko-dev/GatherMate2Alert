# GatherMate2Alert

## Target

- WoW Classic Era 1.15.x only, `## Interface: 11509`.
- `main` holds the Classic Era version. `1.15.x-backup` keeps a copy and stays untouched.
- Verify every API against Gethe `wow-ui-source` and Ketho `BlizzardInterfaceResources`, branch `classic_era`.

## Rules

- GatherMate2 is a hard dependency on purpose. The file calls `LibStub("AceAddon-3.0"):GetAddon("GatherMate2")` at load, so a missing GatherMate2 is a load error, not a soft failure.
- Everything hangs off one `hooksecurefunc` post-hook on `Display:addMiniPin`, a GatherMate2 internal, not an API. It runs every frame for every pin, so return early for anything that is not a circle.
- Inside the hook: size the circle, merge, run the alert gates, then write `seen`. Merging before the gates lets a hidden duplicate still alert for its own node type. Gating before `seen` keeps the first alert after a flight, a fight or an unmute.
- `seen` is keyed by node type, then `pin.coords`, never by pin frame. GatherMate2 recycles pin frames.
- Circles merge by on-screen pin distance, not by coordinate, within the batch of pins positioned in one frame. Only the cluster leader stays visible.
- The leader is the lowest node coordinate, never the first pin to arrive. GatherMate2 iterates pins in different orders, and first-come leadership made the circle hop between nodes.
- Merge reach stays at GatherMate2's native 10 px circle, whatever the size slider says. A scaled reach moved the circle off its node.
- A hidden pin keeps a stale position, so it never leads or merges.
- A single-type cluster keeps its colour from `GatherMate.db.profile.trackColors`. Gold marks a mixed cluster. The pulse uses the same colours.
- No cleanup pass. GatherMate2's full sweeps re-show every pin at least every two seconds and heal stale merge state.
- `DEFAULT_SOUND_ID` stays the literal `3175`, so a saved id survives a `SOUNDKIT` rename.

## Libraries

- `Libs/` holds tracked, unedited upstream copies for the minimap button.
- AceAddon-3.0 is not embedded. It comes with GatherMate2.

## Checks

- Run `luac -p` on every Lua file after a change. The repo has no test harness.
- Turn on `/console scriptErrors 1` before testing in game.
