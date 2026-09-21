# GatherMate2Alert

Sound and visual alerts when a GatherMate2 node enters minimap tracking range.

## Features

- Alert sound when a node's tracking circle appears within GatherMate2's track distance
- Gold pulse ring on the minimap edge, usable as a silent visual-only mode
- Sound picker with preview and a test button
- Cooldown presets, so a cluster of nodes triggers a single alert
- Per-node-type toggles, pulled live from GatherMate2
- Optional Master-channel playback that comes through while sound effects are muted
- Silent on flight paths, in combat, while zoning, and for nodes seen in the last three minutes
- Minimap button: left-click opens the settings, right-click toggles the alert

## Installation

1. Copy the `GatherMate2Alert/` folder into `World of Warcraft/_classic_era_/Interface/AddOns/`.
2. Restart the game or `/reload`.
3. Enable **GatherMate2Alert** in the AddOns list.

## Requirements

WoW Classic Era 1.15.x, and GatherMate2 with node data.

## Restrictions

Alerts fire on GatherMate2's own map pins. The native Find Herbs and Find Minerals blips are drawn by the game engine and invisible to addons, so they cannot be detected.
