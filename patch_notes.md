# Patch notes

## 2026-10-13 — HQ Garage vehicle crews at every war level

### Fixed

- Vehicle Crew (HQ Garage) now stays at the top of the Siege Planning squad list at every war level, including when garage vehicles are empty or fully reserved. Newly unlocked faction squads no longer push garage access below the initial list viewport.
- Squad list refreshes preserve the selected squad ID without selection callbacks changing it during repopulation. Rapid interactions retain a delayed refresh so the Select Vehicle controls catch up to the current selection.
- The garage browser opens with an empty inventory and explains when no unqueued combat vehicles are available. Empty searches clear vehicle details and disable confirmation; unavailable saved selections are cleared before queuing.
- Existing faction unlock levels, combat vehicle filters, infrastructure requirements, reservations, and recruitment costs remain in effect. No campaign reset is needed.

### Verification

- Dedicated-server validation passed 224 assertions with no SQF errors: production menu generation at War Levels 1–10, selection restoration and event guards through UI command adapters, empty-detail confirmation controls, and actual CBA deferred-refresh scheduling. The production UI compiled in the engine.
- SQF/config delimiter checks and `git diff --check` passed. The addon was built, signed, and signature-verified; all 31 packaged runtime functions matched the source and validation fixtures were excluded.
- Graphical-client verification with CBA, Antistasi Ultimate, and this addon is still required for list scrolling, vehicle selection, and deployment at later war levels.

## 2026-10-10 — Antistasi Ultimate persistent save and JSON import/export compatibility

### Added

- Added native support for Antistasi Ultimate's `CBA_EVENT_SERVER_GAME_SAVE` (`"A3A_event_serverGameSave"`) and `CBA_EVENT_SERVER_GAME_LOAD` (`"A3A_event_serverGameLoad"`) persistence events via modular handlers `CL_fnc_saveState` and `CL_fnc_loadState`.
- Persistent Fog of War: Discovered non-zone map targets (radio towers, gas stations, outposts) are now saved into the AU plugin save map (`"CL_Antistasi_Tweaks" -> "discoveredMarkers"`) and restored on campaign load. Loaded discoveries are synchronized with `revealedZones` and broadcast to all connecting players.

### Architecture & JSON Compatibility

- Architected all custom persistent data structures to be strictly JSON-serializable for seamless compatibility with Antistasi Ultimate's upcoming import/export functionality:
  - No `SIDE` data types stored (all data is string or scalar).
  - No `OBJECT` references stored (pure marker strings).
  - All HashMap keys are strictly `STRING`s.
  - Mod data is isolated inside its own tagged dictionary (`"CL_Antistasi_Tweaks"`).

### Verification

- Validated SQF syntax, parameters, and variable sanitation against Antistasi Ultimate's `cba_events.hpp` and `fn_saveLoop` / `fn_loadServer` specifications.

## 2026-10-03 — Point Campfire Extender and TEH fork compatibility

### Fixed

- Point Campfire Extender's upgraded rebel factories and resource sites now contribute to the ten minute faction income payout. The upgrade bonus follows Point Campfire's income formula when its resource upgrade option is enabled.
- TEH Antistasi Ultimate now applies its HR reserve salary deduction and displays it in the income message.
- TEH's configurable arms dealer war tier requirement and war tier zero restriction on random Petros missions are retained alongside this mod's mission chance multiplier.

### Verification

- Compared income and mission logic with Point Campfire Extender's installed core PBO and TEH Antistasi Ultimate's upstream resource loop.
- In-game verification with both optional mods is still needed.

## 2026-10-03 — Antistasi Ultimate V12 compatibility fixes

### Fixed

- Siege planner infantry now receives its faction role before rebel equipment initialization. Armed roles are checked after spawning; squads that cannot equip their full roster are cancelled and refunded instead of deploying unarmed AI.
- The town economy loop now reads V12 town data and uses V12 support thresholds, town battle triggers, and side change functions. This restores the existing town skirmish events and avoids the older override's direct ownership changes.
- The AI spawn distance override now applies the saved campaign setting after Antistasi finishes loading. Its related spawn distances update together. **Off** keeps Antistasi's default distances.
- Boolean siege limit settings are converted to numeric values safely when read from mission parameters.

### Native behavior preserved

- Invaders do not capture towns through ordinary attacks in V12. Their attacks on rebel towns use the native punishment event; faction attacks can still capture eligible non-town objectives. This patch does not add new town conquest rules.

### Verification

- Static SQF delimiter checks and `git diff --check` passed.
- In-game verification with an Antistasi Ultimate V12 campaign is still needed for siege equipment, town battles, and save/load behavior.
