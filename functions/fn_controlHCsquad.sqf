/*
    fn_controlHCsquad.sqf
    Override of A3A_fnc_controlHCsquad.
    Maintainer: CL Antistasi Tweaks Extender (original: Antistasi Ultimate)

    Changes vs vanilla:
      1. Time limit reads A3A_tweak_aiControlTimeOverride instead of aiControlTime.
         If the value is -1, the timer is set to 999999 (effectively unlimited).
      2. Damage cancellation uses a configurable threshold (A3A_tweak_aiControlDamageThreshold).
         At threshold == 0 (default) the behaviour is identical to vanilla (any real damage > 0.05).
         At threshold == 99 control is only revoked when the unit becomes incapacitated or dies.

    Scope: Client
    Environment: Any
*/

// Helper for safe localization with English fallback
private _fnc_loc = {
    params ["_key", "_default"];
    private _val = localize _key;
    if (_val isEqualTo "" || {_val isEqualTo _key}) then { _default } else { _val }
};

private _hintTitle = ["STR_control_unit_hint_header", "AI Direct Control"] call _fnc_loc;

// Robust parameter parsing: supports nil, [], [group], [unit], grpNull, objNull
private _rawInput = if (isNil "_this" || {_this isEqualTo []}) then { hcSelected player } else { _this };
private _unit = objNull;

if (_rawInput isEqualType []) then {
    if (count _rawInput > 0) then {
        private _first = _rawInput select 0;
        if (_first isEqualType grpNull) then {
            _unit = leader _first;
        } else {
            if (_first isEqualType objNull && {_first isKindOf "CAManBase"}) then {
                _unit = _first;
            };
        };
    };
} else {
    if (_rawInput isEqualType grpNull) then {
        _unit = leader _rawInput;
    } else {
        if (_rawInput isEqualType objNull && {_rawInput isKindOf "CAManBase"}) then {
            _unit = _rawInput;
        };
    };
};

// 1. Fallback: Check High Command selected groups
if (isNull _unit) then {
    private _hcSel = hcSelected player;
    if (count _hcSel > 0) then {
        _unit = leader (_hcSel select 0);
    };
};

// 2. Fallback: Check any HC groups assigned to player
if (isNull _unit) then {
    private _allHC = (hcAllGroups player) select { !isNull _x && { count (units _x select { alive _x }) > 0 } };
    if (count _allHC > 0) then {
        _unit = leader (_allHC select 0);
    };
};

// 3. Fallback: Check F-key selected squad members
if (isNull _unit) then {
    private _sel = groupSelectedUnits player;
    if (count _sel > 0 && {(_sel select 0) isKindOf "CAManBase"}) then {
        _unit = _sel select 0;
    };
};

// 4. Fallback: Check squad AI members
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

if (isNull _unit) exitWith {
    [_hintTitle, ["STR_control_unit_error_no_squad_selected", "No squad or AI unit selected. Select a High Command squad or squad member."] call _fnc_loc] call A3A_fnc_customHint;
};

if (_unit == Petros) exitWith {
    [_hintTitle, ["STR_control_unit_error_petros", "You cannot control Petros."] call _fnc_loc] call A3A_fnc_customHint;
};
if (captive player) exitWith {
    [_hintTitle, ["STR_control_unit_error_undercover", "You cannot control AI while Undercover."] call _fnc_loc] call A3A_fnc_customHint;
};
if (!isNil "theBoss" && {isPlayer theBoss && {player != theBoss && {player != leader group player}}}) exitWith {
    [_hintTitle, ["STR_control_unit_error_no_squad_leader", "Only the Commander or Squad Leader can directly control units."] call _fnc_loc] call A3A_fnc_customHint;
};
if (isPlayer _unit) exitWith {
    [_hintTitle, ["STR_control_unit_error_no_player", "You cannot control other human players."] call _fnc_loc] call A3A_fnc_customHint;
};
if (!(alive _unit) or (_unit getVariable ["incapacitated", false])) exitWith {
    [_hintTitle, ["STR_control_unit_error_alive_only", "You cannot control dead or incapacitated units."] call _fnc_loc] call A3A_fnc_customHint;
};
if (side (group _unit) != teamPlayer && {side _unit != teamPlayer}) exitWith {
    private _rebName = A3A_faction_reb getOrDefault ["name", "Rebel"];
    [_hintTitle, format [["STR_control_unit_error_rebel_only", "You can only control friendly %1 units."] call _fnc_loc, _rebName]] call A3A_fnc_customHint;
};
if (!isNil "A3A_FFPun_Jailed" && {(getPlayerUID player) in A3A_FFPun_Jailed}) exitWith {
    [_hintTitle, ["STR_control_unit_error_punish", "You cannot control AI units while serving punishment."] call _fnc_loc] call A3A_fnc_customHint;
};

private _owner = player getVariable ["owner", player];
if (_owner != player) exitWith {
    [_hintTitle, ["STR_control_unit_error_ai_recursion", "You are already directly controlling an AI unit."] call _fnc_loc] call A3A_fnc_customHint;
};

{
    if (_x != vehicle _x) then {
        [_x] orderGetIn true;
    };
} forEach units group player;

private _face    = face _unit;
private _speaker = speaker _unit;

_unit setVariable ["owner", player, true];
_unit setVariable ["A3A_player", player];
player setVariable ["originalBody", player];

// HandleDamage EH on the original player body
private _eh1 = player addEventHandler ["HandleDamage", {
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
private _eh2 = _unit addEventHandler ["HandleDamage", {
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

if (fatigueEnabled isEqualTo false) then {
    _unit enableFatigue false;
};
if (staminaEnabled isEqualTo false) then {
    _unit enableStamina false;
};

private _newWeaponSway = swayEnabled / 100;
_unit setCustomAimCoef _newWeaponSway;

// --- Configurable time limit ---
private _configTime = missionNamespace getVariable ["A3A_tweak_aiControlTimeOverride", aiControlTime];
private _timeX = if (_configTime == -1) then { 999999 } else { _configTime };

_unit setVariable ["controlReturned", false];
_owner setVariable ["controlReturned", false];

private _releaseText = ["STR_antistasi_actions_return_control_to_ai", "Release Control"] call _fnc_loc;
private _returnActionId = _unit addAction [
    format ["<t color='#FFD700'>%1</t>", _releaseText],
    {
        params ["_target"];
        _target setVariable ["controlReturned", true, true];
        private _origOwner = _target getVariable ["owner", _target];
        _origOwner setVariable ["controlReturned", true, true];
    },
    nil, 10, true, true, "", "true"
];

private _timerFmt = ["STR_control_unit_time_to_return_to_original_body", "Time remaining in AI body: %1"] call _fnc_loc;

waitUntil {
    sleep 1;
    private _displayTime = if (_timeX > 9999) then { "∞" } else { str _timeX };
    [_hintTitle, format [_timerFmt, _displayTime]] call A3A_fnc_customHint;
    _timeX = _timeX - 1;

    (_timeX <= 0) or {
        !alive _unit or {
            !alive _owner or {
                (_unit getVariable ["incapacitated", false]) or {
                    (!([_unit] call A3A_fnc_canFight)) or {
                        (_unit getVariable ["controlReturned", false]) or {
                            (_owner getVariable ["controlReturned", false])
                        }
                    }
                }
            }
        }
    }
};

_unit removeAction _returnActionId;

selectPlayer _owner;
(units group player) joinsilent group player;
group player selectLeader player;

if (!isNil "respawnMenu") then {
    (findDisplay 46) displayRemoveEventHandler ["KeyDown", respawnMenu];
    respawnMenu = nil;
};

_unit setVariable ["controlReturned", nil];
_unit setVariable ["owner", nil];
_unit setVariable ["A3A_player", nil];
_unit setVariable ["CL_aiControl_accumDmg", nil];
_unit removeEventHandler ["HandleDamage", _eh2];

player setVariable ["controlReturned", nil];
player setVariable ["originalBody", nil];
player setVariable ["CL_aiControl_accumDmg", nil];
player removeEventHandler ["HandleDamage", _eh1];

[_hintTitle, ["STR_control_unit_return_to_original_body", "Control returned to original body."] call _fnc_loc] call A3A_fnc_customHint;
playSound "A3AP_UiSuccess";

