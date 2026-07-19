# GatherMate2NodeAlert

Sound and visual alerts when a GatherMate2 node enters minimap tracking range, for World of Warcraft Classic Era (1.15.x).

## Features

- Alert sound when a node's tracking circle appears within GatherMate2's track distance
- Gold pulse ring on the minimap edge, works as a silent visual-only mode
- Sound picker with preview and test button
- Cooldown presets so a cluster of nodes triggers a single alert
- Per-node-type toggles pulled live from GatherMate2
- Optional Master-channel playback that comes through while sound effects are muted
- No alerts on flight paths, in combat, while zoning, or for nodes seen in the last three minutes
- Minimap button: left-click opens the settings dialog, right-click toggles the alert
- Settings saved between sessions

## Notes

Requires GatherMate2 with node data. Alerts trigger on GatherMate2's own map pins;
the native Find Herbs and Find Minerals blips are engine-drawn and invisible to addons,
so they cannot be detected.
