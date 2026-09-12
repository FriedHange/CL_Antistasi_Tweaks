/*
    fn_onPlayerRespawn.sqf
    Wrapper for A3A_fnc_onPlayerRespawn.
    Maintainer: CL Antistasi Tweaks Extender

    Enhancements vs vanilla:
      1. Prevents being trapped in a dead corpse: If a player died while controlling
         a remote AI unit, but their original body is dead, clear the 'owner' variable
         so Antistasi core creates a fresh respawn unit at base rather than deleting
         _newUnit and selecting a dead corpse.
      2. Squad Preservation: Re-joins surviving AI squad members owned by _oldUnit
         into group _newUnit so they immediately reappear on the command bar (F2-F10)
         without needing to recruit new soldiers.

    Scope: Client
    Environment: Scheduled
*/

params ["_newUnit", "_oldUnit"];

if (isNull _oldUnit) exitWith {};

// 1. Safety check: prevent permanent corpse lock
private _owner = _oldUnit getVariable ["owner", _oldUnit];
if (_owner != _oldUnit && {!alive _owner}) then {
    diag_log format ["[A3A Tweaks Extender] Remote AI died and owner %1 is dead. Clearing owner to permit clean base respawn.", _owner];
    _oldUnit setVariable ["owner", _oldUnit, true];
};

// 2. Call original Antistasi onPlayerRespawn
_this call A3A_fnc_onPlayerRespawn_original;

// 3. Squad Preservation: Re-join surviving personal AI squad members to the new unit's group
if (alive _newUnit && {side group _newUnit == teamPlayer}) then {
    _newUnit allowDamage true;
    private _ownedAI = allUnits select {
        alive _x && {
            !isPlayer _x && {
                (_x getVariable ["owner", objNull] == _oldUnit) || {
                    (_x getVariable ["owner", objNull] == _newUnit)
                }
            }
        }
    };

    if (_ownedAI isNotEqualTo []) then {
        diag_log format ["[A3A Tweaks Extender] Restoring %1 surviving squad members to group %2.", count _ownedAI, group _newUnit];
        _ownedAI joinSilent (group _newUnit);
        (group _newUnit) selectLeader _newUnit;
        {
            _x allowDamage true;
        } forEach _ownedAI;
    };
};
