# Patch notes

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
