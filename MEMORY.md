# GatherMate2Alert — Development Memory

The single persistent note for this addon. Read it before touching the code instead of re-deriving anything. Created 2026-09-19 from the code, the git history and `README.md` (kept, it is the user-facing doc). **This addon has never been audited for WoW Forever 1.60.x** — like AuctionatorPlus and unlike the other four miyanko-authored addons here, no compatibility pass has been run on it. Section 6 is the work that has not happened.

**Verified against:** `forever` @ `70ef1b2` (1.60.1.69913), 2026-09-21.

**Shared 1.60 client facts are not in this file.** They live in one place: `Cortex/WoW/Forever Client Facts.md` in the Obsidian vault (`~/Library/Mobile Documents/iCloud~md~obsidian/Documents/`). Read that first — this note records only what is specific to this addon, and never restates a fact about the client. Companions there: `Two-Version Addon Architecture.md` (layout), `UI Compatibility Analysis.md` (templates and widgets). Run `../check-client-facts.sh` to see whether any of it has gone stale.

---

## 1. Status on 2026-09-19

| Item | State |
|---|---|
| Version | 1.0.0, **committed and clean**. HEAD `71703d1` "Rename addon to GatherMate2Alert" |
| Repo | `github.com/miyanko-dev/GatherMate2Alert`, branch `main`. No `.pkgmeta`, no CI, no tags |
| Working tree | Only `?? MEMORY.md`. Nothing uncommitted |
| Target | Classic Era 1.15.x only, `## Interface: 11509`. **No 16001**, no 1.60 support |
| Hard dependency | `## RequiredDeps: GatherMate2` — the addon does not load without it, and calls `LibStub("AceAddon-3.0"):GetAddon("GatherMate2")` at file scope, so a missing GatherMate2 is a load-time error, not a soft failure |
| Saved variable | `GatherMate2AlertDB`, account-wide |
| Installed clients | Forever beta only (`_classic_beta_`), never launched. `_classic_era_` is **gone** from this Mac, and GatherMate2 is not installed here either, so the addon cannot run at all today |
| Offline checks | None run. No harness, no test suite, no `luac -p` pass recorded |
| In-game checks | Worked on 1.15.x before `_classic_era_` was removed. Nothing verified since |

**Naming history:** started as `GatherMate2NodeAlert`, renamed to `GatherMate2Alert` in the HEAD commit. Older commit messages and any stale references use the long name.

---

## 2. How to resume

1. `git status` — expect a clean tree plus this file.
2. `luac -p GatherMate2Alert.lua` (never recorded as run).
3. To run it you need `_classic_era_` reinstalled **and** GatherMate2 installed there with node data. Neither exists on this Mac.
4. Before any 1.60 work, read section 6. The blocking question is whether GatherMate2 has a Forever build, not this addon's code.

---

## 3. What it is

Sound and visual alerts when a GatherMate2 node enters minimap tracking range.

- Alert sound when a node's tracking circle appears within GatherMate2's track distance
- Gold pulse ring on the minimap edge, usable as a silent visual-only mode
- Sound picker with preview and a test button
- Cooldown presets so a cluster of nodes triggers a single alert
- Per-node-type toggles pulled live from GatherMate2
- Optional Master-channel playback that comes through while sound effects are muted
- No alerts on flight paths, in combat, while zoning, or for nodes seen in the last three minutes
- Minimap button: left-click opens the settings dialog, right-click toggles the alert
- Settings saved between sessions

**Scope limit worth not re-deriving:** alerts trigger on GatherMate2's own map pins. The native Find Herbs and Find Minerals blips are engine-drawn and invisible to addons, so they cannot be detected. That is why GatherMate2 is a hard dependency rather than a nicety.

---

## 4. Architecture

One flat file, `GatherMate2Alert.lua`, 664 lines, plus `pulse_ring.tga` and four vendored libraries (LibStub, CallbackHandler-1.0, LibDataBroker-1.1, LibDBIcon-1.0) for the minimap launcher. **No `Core/` + `UI/` split and no version seam** — it predates the convention the sibling addons adopted on 2026-09-19.

Toc load order: the four libs, then `GatherMate2Alert.lua`.

### The single integration point

```lua
local GatherMate = LibStub("AceAddon-3.0"):GetAddon("GatherMate2")
local Display = GatherMate:GetModule("Display")

hooksecurefunc(Display, "addMiniPin", function(_, pin) ... end)
```

Everything the addon does hangs off that one post-hook. `Display:addMiniPin` turns a pin into a tracking circle once the node is within GatherMate2's track distance, so **ping on that transition only** — far icon pins at the minimap edge stay silent. The hook runs every frame per pin, so the handler bails out cheaply for anything that is not a circle. It also runs right after `addMiniPin`'s own `Show`, which is why hiding icon pins here wins.

Handler order inside the hook, and why:

1. `pin.isCircle` false → optionally `pin:Hide()` when `db.hideIcons`, then return.
2. `applyCircleSize(pin)` — GatherMate2 sizes tracking circles once, at `10 / Minimap:GetScale()`, when a pin turns into a circle (its `Display.lua`). Resize right after so the slider choice sticks. Slider step 1 keeps the native 10px, each step adds 2px: `(8 + 2 * circleSize) / Minimap:GetScale()`. Skips when already sized.
3. `mergeCircle(pin)` when `db.mergeCircles` — **after sizing but before the alert checks**, so a hidden duplicate still alerts for its own node type.
4. Alert gates, in order: `db.enabled or db.pulse`, `db.mutedTypes[pin.nodeType]`, `UnitOnTaxi("player")`, `InCombatLockdown()`. **Skip before touching `seen`**, so nodes circled while muted, mid-flight or mid-fight still alert once pings are possible again.
5. `seen[nodeType][pin.coords]` with `REAPPEAR_AFTER = 180`, then the global `db.cooldown` throttle and the `quietUntil` zoning window.

### Circle merging — the subtle part

Nearby nodes are separate spawns with distinct coordinates, so circles that overlap on screen must merge **by pin distance, not by coordinate**. GatherMate2 positions every pin through `addMiniPin` within a single frame, so frame time works as the batch marker: circles whose centers fall within one default circle-width of each other form a cluster and only its leader stays visible.

Two decisions that were arrived at the hard way and should not be reverted:

- **Leadership goes to the lowest node coordinate, never to whichever pin arrived first.** GatherMate2's full sweeps and its per-move updates iterate pins in different orders, and first-come leadership made the visible circle hop between cluster members instead of staying concentric with one real node. Full sweeps re-show all pins at least every two seconds, which heals any stale state after pins leave range or get recycled.
- **Merge reach stays at GatherMate2's native 10px circle footprint no matter the size slider.** A scaled-up reach merged nodes that never merged at default size, moving the visible circle off the node it encircles.

Also: GatherMate2 skips positioning when it hides an edge-faded pin, so a hidden pin has a stale point and must not lead or merge.

Colour rule: a single-type cluster keeps that type's own circle colour and only grows; gold marks a cluster that mixes node types. Repainting the type colour also heals a leader that was gold a frame earlier. Colours come from `GatherMate.db.profile.trackColors[nodeType]` — the same table GatherMate2 tints its own circles from — and the pulse flash is tinted the same way, so the colour alone tells the node type.

Node types come from `GatherMate.db_types`, read live, so the per-type toggle list matches whatever GatherMate2 knows about.

### Constants

| Name | Value | Meaning |
|---|---|---|
| `REAPPEAR_AFTER` | 180 | Seconds before the same coordinate of the same type alerts again |
| `ZONING_QUIET_TIME` | 5 | Seconds of silence after a zone change |
| `DEFAULT_SOUND_ID` | 3175 | `SOUNDKIT.MAP_PING`, kept as a literal so a saved id survives a constant rename |
| `BUTTON_ICON` | `Interface\Icons\INV_Misc_Bell_01` | Minimap button icon |
| `PULSE_TEXTURE` | `Interface\AddOns\GatherMate2Alert\pulse_ring` | **Ships with the addon** as `pulse_ring.tga`, so it is not a client-data dependency |
| `PULSE_COLOR` | `{ 1, 0.82, 0 }` | Gold, used for mixed-type clusters |
| `COOLDOWNS` | `{ 1, 3, 5, 10, 20, 30 }` | The cooldown presets offered in the panel |

Panel layout constants, all on the same grid the sibling addons use: `PAD 16`, `PAD_TOP 48` (clears the dialog-box-header banner), `SECTION_GAP 24` (clears the floating label), `SECTION_INNER_PAD 12` (clears the border art), `SECTION_LABEL_LIFT 8`, `HELPER_GAP 8`, `BTN_GAP 8`, `ROW_H 24`, `ROW_GAP 4`, `CB_H 20` (native `UICheckButton` size), `SLIDER_H 40` and `SLIDER_W 160` (`MinimalSliderWithSteppersTemplate`, matching the dropdown column). These are the knobs for any "panel looks wrong" report.

### Saved variables — `GatherMate2AlertDB`

Account-wide, created on `ADDON_LOADED`. Keys: `enabled`, `pulse`, `pulseThickness`, `channel` (`"Master"` or `"SFX"`), `soundId`, `cooldown`, `hideIcons`, `mergeCircles`, `circleSize`, `mutedTypes` (keyed by node type, `true` = muted, cleared to nil when unmuted), plus LibDBIcon's own minimap position.

The panel is a named frame `GatherMate2AlertPanel` on `BackdropTemplate`, registered in `UISpecialFrames` so Escape closes it. Sliders are named `GatherMate2AlertSlider<N>` via a counter.

Events registered: `ADDON_LOADED`, `PLAYER_LOGIN`, `PLAYER_ENTERING_WORLD`, `ZONE_CHANGED_NEW_AREA`.

Minimap button: left-click opens the panel, right-click toggles the alert (setting both `enabled` and `pulse` together), and the icon desaturates while the alert is off. The tooltip reports the current state, the sound name and the cooldown.

---

## 5. Known behaviour worth not re-deriving

- **Master-channel playback is deliberate.** `PlaySound(id, db.channel, true)` with `channel = "Master"` comes through while sound effects are muted, which is the point for a gathering alert.
- **The pulse texture ships with the addon**, so unlike the sibling addons' `UI-DialogBox-*` usage it carries no client-art risk.
- **`seen` is keyed by node type then by `pin.coords`**, not by pin identity, because GatherMate2 recycles pin frames.
- **The alert gates run before `seen` is written.** Reverting that order would silently swallow the first alert after a flight, a fight or an unmute.
- **Full sweeps every two seconds are what heals stale merge state.** There is no explicit cleanup pass and none is needed.

---

## 6. Open: nothing about 1.60 has been checked

Ordered by what blocks what.

1. **Does GatherMate2 have a WoW Forever build?** `## RequiredDeps: GatherMate2`, and the addon calls `LibStub("AceAddon-3.0"):GetAddon("GatherMate2")` at file scope, so without it the addon errors at load rather than degrading. **Settle this first.** GatherMate2 is an Ace3 addon; whether Ace3 itself works unmodified on camelot is a second, separate question.
2. **Does `Display:addMiniPin` still exist with that signature in a Forever build of GatherMate2?** The entire addon is one post-hook on it. This is an internal of a third-party addon, not an API, and the Forever port (if any) is the most likely place for it to move.
3. **Camelot's minimap is re-skinned.** `Blizzard_Minimap/Camelot/Skin.lua` resizes `MinimapCluster.MinimapContainer` and sets a custom mask (confirmed in `../TargetFinder/MEMORY.md` Stage 0.5 and `../ChatScan/MEMORY.md` open question 8). That affects three things here: `Minimap:GetScale()` in `applyCircleSize`, the pulse ring's placement on the minimap edge, and LibDBIcon r56's button placement. All three are geometry, not crashes.
4. **`## Interface: 11509` only.** No 16001. One line, pointless before 1 and 2.
5. **`SOUNDKIT.MAP_PING` = 3175** is confirmed present on both clients (`../ChatScan/MEMORY.md` section 8 verified all six of its sound presets); this one id is shared with ChatScan's default, so it is the safest part of the addon.
6. **`MinimalSliderWithSteppersTemplate`, `UICheckButtonTemplate`, `BackdropTemplate`, `UISpecialFrames`.** All confirmed present on both clients by the sibling audits. `UICheckButtonTemplate` with its `.Text` region is byte-identical on both.
7. **No structural audit has been done.** No `luac -p`, no toc-resolution check, no globals extraction.

---

## 7. Next development steps

Nothing needs beta access except step 4.

1. **Run the basic offline checks every sibling addon has had and this one has not:** `luac -p` on the addon file and the four libs, confirm all five toc entries resolve, confirm nothing on disk is unlisted, extract global writes and check they are `GatherMate2AlertDB` plus the named frames only.
2. **Decide whether 1.60 is a goal.** Answer open questions 1 and 2. If GatherMate2 has no Forever build, write that down here and stop; this stays a 1.15.x tool.
3. **If 1.60 is a goal**, audit against `Gethe/wow-ui-source@forever` the way the siblings were audited, and treat the Camelot minimap skin (open question 3) as the main piece of real work.
4. **Reinstall `_classic_era_` plus GatherMate2** if the addon is to be exercised at all. It currently cannot run on this machine.
5. **Optional, independent of the above:** split the 664-line file into the `Core/` + `UI/` shape the siblings use. The natural seam already exists — the `addMiniPin` hook plus merging and alerting is `Core/`, the panel and minimap button are `UI/`. Only worth doing if step 2 says 1.60 is a goal.
6. **Check for stale `GatherMate2NodeAlert` references** if anything ever looks mis-wired; the rename landed in HEAD and older commits use the long name.

---

## 8. Test results

Empty. The addon worked on 1.15.x before `_classic_era_` was removed from this Mac; nothing is recorded per-feature.
