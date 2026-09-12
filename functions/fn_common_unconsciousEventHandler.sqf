/*
    fn_common_unconsciousEventHandler.sqf
    Override of SCRT_fnc_common_unconsciousEventHandler.
    Maintainer: CL Antistasi Tweaks Extender

    Supports configurable unconscious keys via Arma 3 Custom Controls (User Action 1 - 20):
      - Respawn: A3A_tweak_unconsciousRespawnAction (0 = default DIK_R / 19)
      - Possess AI: A3A_tweak_unconsciousPossessAction (0 = default DIK_T / 20)
      - Withstand: A3A_tweak_unconsciousWithstandAction (0 = default DIK_H / 35)
      - Combat Readiness Kit: default DIK_Q / 16

    Scope: Client
    Environment: Any
*/

#include "\a3\ui_f\hpp\definedikcodes.inc"

params ["_displayOrControl", "_key", "_shift", "_ctrl", "_alt"];

private _handled = false;

// 1. Withstand / Self-Revive
private _withstandAction = missionNamespace getVariable ["A3A_tweak_unconsciousWithstandAction", 0];
private _withstandKeys = if (_withstandAction > 0) then {
    actionKeys (format ["User%1", _withstandAction])
} else {
    [35] // DIK_H
};
if (_withstandKeys isEqualTo []) then { _withstandKeys = [35]; };

if (_key in _withstandKeys) then {
    if (A3A_selfReviveMethods isEqualTo true) then {
        [] spawn A3A_fnc_selfRevive;
    };
    _handled = true;
};

// 2. Respawn
private _respawnAction = missionNamespace getVariable ["A3A_tweak_unconsciousRespawnAction", 0];
private _respawnKeys = if (_respawnAction > 0) then {
    actionKeys (format ["User%1", _respawnAction])
} else {
    [19] // DIK_R
};
if (_respawnKeys isEqualTo []) then { _respawnKeys = [19]; };

if (_key in _respawnKeys) then {
    if (!isNil "respawnMenu") then {
        (findDisplay 46) displayRemoveEventHandler ["KeyDown", respawnMenu];
        respawnMenu = nil;
    };
    player spawn A3A_fnc_respawn;
    _handled = true;
};

// 3. Possess AI
private _possessAction = missionNamespace getVariable ["A3A_tweak_unconsciousPossessAction", 0];
private _possessKeys = if (_possessAction > 0) then {
    actionKeys (format ["User%1", _possessAction])
} else {
    [20] // DIK_T
};
if (_possessKeys isEqualTo []) then { _possessKeys = [20]; };

if (_key in _possessKeys) then {
    private _nearFriendlyUnits = [] call SCRT_fnc_ai_getNearFriendlyUnits;
    private _possessTimeout = player getVariable ["A3A_possessTime", time - 1];
    if (time < _possessTimeout) exitWith {
        [localize "STR_antistasi_dialogs_ai_control_title", format [localize "STR_A3AP_notifications_possess_cooldown", round (_possessTimeout - time)]] call SCRT_fnc_misc_deniedHint;
    };
    if (_nearFriendlyUnits isNotEqualTo []) then {
        if (!isNil "respawnMenu") then {
            (findDisplay 46) displayRemoveEventHandler ["KeyDown", respawnMenu];
            respawnMenu = nil;
        };
        [_nearFriendlyUnits select 0] spawn SCRT_fnc_ai_possessFriendlyUnit;
    };
    _handled = true;
};

// 4. Combat Readiness Kit (Q)
if ((missionNamespace getVariable ["reviveKitsEnabled", false]) && {_key == 16}) then {
    if ("A3AP_SelfReviveKit" in (backpackItems player)) then {
        if (!isNil "respawnMenu") then {
            (findDisplay 46) displayRemoveEventHandler ["KeyDown", respawnMenu];
            respawnMenu = nil;
        };
        [player, player] call SCRT_fnc_common_revive;
        _handled = true;
    };
};

_handled;
