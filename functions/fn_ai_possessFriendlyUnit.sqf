/*
    fn_ai_possessFriendlyUnit.sqf
    Override of SCRT_fnc_ai_possessFriendlyUnit.
    Maintainer: CL Antistasi Tweaks Extender (original: Socrates / Antistasi Ultimate)

    Changes vs vanilla:
      1. Time limit reads A3A_tweak_aiControlTimeOverride instead of aiControlTime.
         If the value is -1, the timer is set to 999999 (effectively unlimited).
      2. Damage cancellation uses a configurable threshold (A3A_tweak_aiControlDamageThreshold).
         At threshold == 0 (default) the behaviour is identical to vanilla (any real damage > 0.05).
         At threshold == 99 control is only revoked when the unit becomes incapacitated or dies.

    Return Value:
        <ARRAY> Units

    Scope: Client
    Environment: Any
    Public: Yes
*/

#include "\a3\ui_f\hpp\definedikcodes.inc"

params [["_unit", objNull, [objNull, grpNull, []]]];

if (_unit isEqualType grpNull) then { _unit = leader _unit; };
if (_unit isEqualType [] && { count _unit > 0 }) then {
    private _first = _unit select 0;
    if (_first isEqualType objNull && {_first isKindOf "CAManBase"}) then {
        _unit = _first;
    } else {
        if (_first isEqualType grpNull) then {
            _unit = leader _first;
        };
    };
};

// Helper for safe localization with English fallback
private _fnc_loc = {
    params ["_key", "_default"];
    private _val = localize _key;
    if (_val isEqualTo "" || {_val isEqualTo _key}) then { _default } else { _val }
};

private _hintTitle = ["STR_control_unit_hint_header", "AI Direct Control"] call _fnc_loc;

// 1. Fallback: Check crosshair cursorObject / cursorTarget
if (isNull _unit && {!isNull cursorObject && {cursorObject isKindOf "CAManBase" && {!isPlayer cursorObject}}}) then {
    if (side (group cursorObject) == teamPlayer || side cursorObject == teamPlayer || group cursorObject == group player) then {
        _unit = cursorObject;
    };
};
if (isNull _unit && {!isNull cursorTarget && {cursorTarget isKindOf "CAManBase" && {!isPlayer cursorTarget}}}) then {
    if (side (group cursorTarget) == teamPlayer || side cursorTarget == teamPlayer || group cursorTarget == group player) then {
        _unit = cursorTarget;
    };
};

// 2. Fallback: Check F-key selection
if (isNull _unit) then {
    private _sel = groupSelectedUnits player;
    if (count _sel > 0 && {(_sel select 0) isKindOf "CAManBase"}) then {
        _unit = _sel select 0;
    };
};

// 3. Fallback: Check squad AI
if (isNull _unit) then {
    private _squadAIs = (units group player) select {
        alive _x && {
            !isPlayer _x && {
                _x != player && {
                    _x != Petros && {
                        !(_x getVariable ["incapacitated", false])
                    }
                }
            }
        };
    };
    if (count _squadAIs > 0) then {
        private _sorted = [_squadAIs, [], { _x distance player }, "ASCEND"] call BIS_fnc_sortBy;
        _unit = _sorted select 0;
    };
};

// 4. Fallback: Check nearby friendly AI within 50m
if (isNull _unit) then {
    private _nearAIs = (player nearEntities ["CAManBase", 50]) select {
        alive _x && {
            !isPlayer _x && {
                _x != player && {
                    _x != Petros && {
                        (side (group _x) == teamPlayer || side _x == teamPlayer) && {
                            !(_x getVariable ["incapacitated", false])
                        }
                    }
                }
            }
        };
    };
    if (count _nearAIs > 0) then {
        private _sorted = [_nearAIs, [], { _x distance player }, "ASCEND"] call BIS_fnc_sortBy;
        _unit = _sorted select 0;
    };
};

if (isNull _unit) exitWith {
    [_hintTitle, ["STR_control_unit_error_no_unit", "No AI unit found. Look at an AI, select with F-keys, or recruit a squad member."] call _fnc_loc] call A3A_fnc_customHint;
};
if (_unit == Petros) exitWith {
    [_hintTitle, ["STR_control_unit_error_petros", "You cannot control Petros."] call _fnc_loc] call A3A_fnc_customHint;
};
if (isPlayer _unit) exitWith {
    [_hintTitle, ["STR_control_unit_error_no_player", "You cannot control other human players."] call _fnc_loc] call A3A_fnc_customHint;
};
if (!(alive _unit) or (_unit getVariable ["incapacitated",false])) exitWith {
    [_hintTitle, ["STR_control_unit_error_alive_only", "You cannot control dead or incapacitated units."] call _fnc_loc] call A3A_fnc_customHint;
};
if (side (group _unit) != teamPlayer && {side _unit != teamPlayer}) exitWith {
    private _rebName = A3A_faction_reb getOrDefault ["name", "Rebel"];
    [_hintTitle, format [["STR_control_unit_error_rebel_only", "You can only control friendly %1 units."] call _fnc_loc, _rebName]] call A3A_fnc_customHint;
};

private _owner = player getVariable ["owner", player];
if (_owner != player) exitWith {
    [_hintTitle, ["STR_control_unit_error_ai_recursion", "You are already directly controlling an AI unit."] call _fnc_loc] call A3A_fnc_customHint;
};

private _face    = face _unit;
private _speaker = speaker _unit;

player setVariable ["originalBody", player];
player setVariable ["A3A_blockRevive", true, true];

_unit setVariable ["owner", player, true];
_unit setVariable ["A3A_player", player];
private _originalBody = player;
private _wasIncap = _originalBody getVariable ["incapacitated", false];

// HandleDamage EH on the original player body
private _playerEh = player addEventHandler ["HandleDamage", {
    params ["_unit", "_selection", "_damage"];
    private _threshold = missionNamespace getVariable ["A3A_tweak_aiControlDamageThreshold", 0];

    // Vanilla mode (_threshold == 0): real damage returns control
    if (_threshold == 0 && {_damage > 0.05}) then {
        _unit removeEventHandler ["HandleDamage", _thisEventHandler];
        _unit setVariable ["controlReturned", true, true];
        private _hintHeader = if (localize "STR_control_unit_hint_header" != "") then { localize "STR_control_unit_hint_header" } else { "AI Direct Control" };
        private _hintMsg = if (localize "STR_control_unit_damage_control_return_player" != "") then { localize "STR_control_unit_damage_control_return_player" } else { "Your original body took damage! Control returned." };
        [_hintHeader, _hintMsg] call A3A_fnc_customHint;
    };
    // Custom threshold mode (e.g. 0 < _threshold < 90)
    if (_threshold > 0 && {_threshold < 90} && {_selection == "" && {_damage >= _threshold}}) then {
        _unit removeEventHandler ["HandleDamage", _thisEventHandler];
        _unit setVariable ["controlReturned", true, true];
        private _hintHeader = if (localize "STR_control_unit_hint_header" != "") then { localize "STR_control_unit_hint_header" } else { "AI Direct Control" };
        private _hintMsg = if (localize "STR_control_unit_damage_control_return_player" != "") then { localize "STR_control_unit_damage_control_return_player" } else { "Your original body took damage! Control returned." };
        [_hintHeader, _hintMsg] call A3A_fnc_customHint;
    };
    _damage
}];

// HandleDamage EH on the possessed AI unit
private _unitEh = _unit addEventHandler ["HandleDamage", {
    params ["_unit", "_selection", "_damage"];
    private _threshold = missionNamespace getVariable ["A3A_tweak_aiControlDamageThreshold", 0];

    // Vanilla mode (_threshold == 0): real damage returns control
    if (_threshold == 0 && {_damage > 0.05}) then {
        _unit removeEventHandler ["HandleDamage", _thisEventHandler];
        _unit setVariable ["controlReturned", true, true];
        private _hintHeader = if (localize "STR_control_unit_hint_header" != "") then { localize "STR_control_unit_hint_header" } else { "AI Direct Control" };
        private _hintMsg = if (localize "STR_control_unit_damage_control_return_ai" != "") then { localize "STR_control_unit_damage_control_return_ai" } else { "Controlled unit took damage! Control returned." };
        [_hintHeader, _hintMsg] call A3A_fnc_customHint;
    };
    // Custom threshold mode (e.g. 0 < _threshold < 90)
    if (_threshold > 0 && {_threshold < 90} && {_selection == "" && {_damage >= _threshold}}) then {
        _unit removeEventHandler ["HandleDamage", _thisEventHandler];
        _unit setVariable ["controlReturned", true, true];
        private _hintHeader = if (localize "STR_control_unit_hint_header" != "") then { localize "STR_control_unit_hint_header" } else { "AI Direct Control" };
        private _hintMsg = if (localize "STR_control_unit_damage_control_return_ai" != "") then { localize "STR_control_unit_damage_control_return_ai" } else { "Controlled unit took damage! Control returned." };
        [_hintHeader, _hintMsg] call A3A_fnc_customHint;
    };
    _damage
}];

selectPlayer _unit;
[_unit, createHashMapFromArray [["face", _face], ["speaker", _speaker]]] call A3A_fnc_setIdentity;

// --- Configurable time limit ---
private _configTime = missionNamespace getVariable ["A3A_tweak_aiControlTimeOverride", aiControlTime];
private _timeX = if (_configTime == -1) then { 999999 } else { _configTime };

_unit setVariable ["controlReturned", false];
_originalBody setVariable ["controlReturned", false];

private _releaseText = ["STR_antistasi_actions_return_control_to_ai", "Release Control"] call _fnc_loc;
private _returnActionId = _unit addAction [
    format ["<t color='#FFD700'>%1</t>", _releaseText],
    {
        params ["_target"];
        _target setVariable ["controlReturned", true, true];
        player setVariable ["controlReturned", true, true];
        private _originalBody = _target getVariable ["A3A_player", objNull];
        if (!isNull _originalBody) then {
            _originalBody setVariable ["controlReturned", true, true];
        };
    },
    nil, 10, true, true, "", "true"
];
private _healActionId = [_originalBody, "heal2"] call A3A_fnc_flagaction;

private _layer = ["A3A_infoCenter"] call BIS_fnc_rscLayer;
private _possessMsg = ["STR_antistasi_actions_unconscious_action_possessed", "Direct Control Active"] call _fnc_loc;
[_possessMsg, 0, 0, 3, 0, 0, _layer] spawn bis_fnc_dynamicText;

private _timerFmt = ["STR_control_unit_time_to_return_to_original_body", "Time remaining in AI body: %1"] call _fnc_loc;

waitUntil {
    sleep 1;
    private _displayTime = if (_timeX > 9999) then { "∞" } else { str _timeX };
    [_hintTitle, format [_timerFmt, _displayTime]] call A3A_fnc_customHint;
    _timeX = _timeX - 1;

    (_timeX <= 0) ||
    {!alive _unit ||
    {_unit getVariable ["incapacitated", false] ||
    {!([_unit] call A3A_fnc_canFight) ||
    {(_wasIncap && {!(_originalBody getVariable ["incapacitated", false])}) ||
    {_unit getVariable ["controlReturned", false] ||
    {_originalBody getVariable ["controlReturned", false]
    }}}}}}
};

_unit removeAction _returnActionId;
if (_healActionId != -1) then {
    _originalBody removeAction _healActionId;
};

selectPlayer _originalBody;
(units group player) joinsilent group player;
group player selectLeader player;
player setVariable ["A3A_blockRevive", nil, true];
player setVariable ["originalBody", nil];
player removeEventHandler ["HandleDamage", _playerEh];
player setVariable ["controlReturned", nil];
player setVariable ["CL_aiControl_accumDmg", nil];

_unit setVariable ["controlReturned", nil];
_unit setVariable ["owner", nil];
_unit setVariable ["A3A_player", nil];
_unit setVariable ["CL_aiControl_accumDmg", nil];
_unit removeEventHandler ["HandleDamage", _unitEh];

[_hintTitle, ["STR_control_unit_return_to_original_body", "Control returned to original body."] call _fnc_loc] call A3A_fnc_customHint;
playSound "A3AP_UiSuccess";

sleep 1;

if (player getVariable ["incapacitated", false]) then {
    player setVariable ["A3A_possessTime", time + 10];
    if (!isNil "respawnMenu") then {
        (findDisplay 46) displayRemoveEventHandler ["KeyDown", respawnMenu];
    };
    respawnMenu = (findDisplay 46) displayAddEventHandler ["KeyDown", SCRT_fnc_common_unconsciousEventHandler];
} else {
    if (!isNil "respawnMenu") then {
        (findDisplay 46) displayRemoveEventHandler ["KeyDown", respawnMenu];
        respawnMenu = nil;
    };
};

