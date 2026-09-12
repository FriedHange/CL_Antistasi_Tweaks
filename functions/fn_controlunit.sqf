/*
    fn_controlunit.sqf
    Override of A3A_fnc_controlunit.
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

// Robust parameter parsing: supports nil, [], [unit], [group], objNull, grpNull
private _rawInput = if (isNil "_this" || {_this isEqualTo []}) then { groupSelectedUnits player } else { _this };
private _unit = objNull;

if (_rawInput isEqualType []) then {
    if (count _rawInput > 0) then {
        private _first = _rawInput select 0;
        if (_first isEqualType objNull && {_first isKindOf "CAManBase"}) then {
            _unit = _first;
        } else {
            if (_first isEqualType grpNull) then {
                _unit = leader _first;
            };
        };
    };
} else {
    if (_rawInput isEqualType objNull && {_rawInput isKindOf "CAManBase"}) then {
        _unit = _rawInput;
    } else {
        if (_rawInput isEqualType grpNull) then {
            _unit = leader _rawInput;
        };
    };
};

// 1. Fallback: Check F-key selected squad members
if (isNull _unit) then {
    private _sel = groupSelectedUnits player;
    if (count _sel > 0 && {(_sel select 0) isKindOf "CAManBase"}) then {
        _unit = _sel select 0;
    };
};

// 2. Fallback: Check High Command selected groups
if (isNull _unit) then {
    private _hcSel = hcSelected player;
    if (count _hcSel > 0) then {
        _unit = leader (_hcSel select 0);
    };
};

// 3. Fallback: Check crosshair cursorObject / cursorTarget
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

// 4. Fallback: If player has AI squad members in group player, auto-select the closest valid squad member!
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

// 5. Fallback: If still no squad AI, check any nearby friendly AI within 35m of player
if (isNull _unit) then {
    private _nearAIs = (player nearEntities ["CAManBase", 35]) select {
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
    [_hintTitle, ["STR_control_unit_error_no_unit", "No AI unit found. Select a squad member with F2-F10, look at an AI, or recruit a squad member."] call _fnc_loc] call A3A_fnc_customHint;
};

if (_unit == Petros) exitWith {
    [_hintTitle, ["STR_control_unit_error_petros", "You cannot control Petros."] call _fnc_loc] call A3A_fnc_customHint;
};
if (captive player) exitWith {
    [_hintTitle, ["STR_control_unit_error_undercover", "You cannot control AI while Undercover."] call _fnc_loc] call A3A_fnc_customHint;
};
if (player != leader group player && {!(_unit in units group player)}) exitWith {
    [_hintTitle, ["STR_control_unit_error_no_squad_leader", "Only the Squad Leader can directly control squad members."] call _fnc_loc] call A3A_fnc_customHint;
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

private _origGroup = group player;
private _unitOrigGroup = group _unit;

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
player setVariable ["CL_controlledAI", _unit];

// HandleDamage EH on the original player body
private _eh1 = player addEventHandler ["HandleDamage", {
    params ["_body", "_selection", "_damage"];

    // Any real damage to the player's main body must IMMEDIATELY return control to the main body,
    // so the player can react and so that if the damage is fatal, the player dies as 'player'
    // and enters the normal respawn sequence instead of becoming stuck in an inert corpse!
    if (_damage > 0.05) then {
        _body removeEventHandler ["HandleDamage", _thisEventHandler];
        private _controlled = _body getVariable ["CL_controlledAI", objNull];
        if (!isNull _controlled) then {
            _controlled setVariable ["controlReturned", true, true];
            _controlled removeEventHandler ["HandleDamage", _controlled getVariable ["CL_aiControl_eh2", -1]];
            _controlled setVariable ["owner", nil, true];
            _controlled setVariable ["A3A_player", nil, true];
        };
        _body setVariable ["controlReturned", true, true];

        _body allowDamage true;
        if (!isNull _controlled) then {
            _controlled allowDamage true;
        };

        // Synchronously return player to main body before damage is applied
        if (alive _body && {player != _body}) then {
            selectPlayer _body;
        };

        private _hintHeader = if (localize "STR_control_unit_hint_header" != "") then { localize "STR_control_unit_hint_header" } else { "AI Direct Control" };
        private _hintMsg = if (localize "STR_control_unit_damage_control_return_player" != "") then { localize "STR_control_unit_damage_control_return_player" } else { "Your original body took damage! Control returned." };
        [_hintHeader, _hintMsg] call A3A_fnc_customHint;
    };
    _damage
}];
player setVariable ["CL_aiControl_eh1", _eh1];

// HandleDamage EH on the possessed AI unit
private _eh2 = _unit addEventHandler ["HandleDamage", {
    params ["_aiUnit", "_selection", "_damage"];
    private _threshold = missionNamespace getVariable ["A3A_tweak_aiControlDamageThreshold", 0];
    private _origOwner = _aiUnit getVariable ["owner", objNull];

    private _shouldReturn = false;
    if (_threshold == 0) then {
        // Vanilla mode: any real hit returns control immediately
        if (_damage > 0.05) then { _shouldReturn = true; };
    } else {
        // Incapacitated / Dead only mode (threshold == 99):
        // Allow combat damage without revoking control, BUT if the hit would be lethal or incapacitating,
        // synchronously return control to _origOwner before _aiUnit dies, so the player is never trapped in a corpse!
        if (_damage >= 0.85 || { (damage _aiUnit + _damage) >= 0.9 || { _aiUnit getVariable ["incapacitated", false] } }) then {
            _shouldReturn = true;
        };
    };

    if (_shouldReturn) then {
        _aiUnit removeEventHandler ["HandleDamage", _thisEventHandler];
        _aiUnit setVariable ["controlReturned", true, true];
        _aiUnit setVariable ["owner", nil, true];
        _aiUnit setVariable ["A3A_player", nil, true];

        if (!isNull _origOwner) then {
            _origOwner removeEventHandler ["HandleDamage", _origOwner getVariable ["CL_aiControl_eh1", -1]];
            _origOwner setVariable ["controlReturned", true, true];
        };

        _aiUnit allowDamage true;
        if (!isNull _origOwner) then {
            _origOwner allowDamage true;
        };

        // Synchronously return player to main body before fatal damage is applied to the AI
        if (!isNull _origOwner && {alive _origOwner && {player != _origOwner}}) then {
            selectPlayer _origOwner;
        };

        private _hintHeader = if (localize "STR_control_unit_hint_header" != "") then { localize "STR_control_unit_hint_header" } else { "AI Direct Control" };
        private _hintMsg = if (_threshold == 0) then {
            if (localize "STR_control_unit_damage_control_return_ai" != "") then { localize "STR_control_unit_damage_control_return_ai" } else { "Controlled unit took damage! Control returned." };
        } else {
            "Controlled unit was incapacitated/killed! Control returned to your body."
        };
        [_hintHeader, _hintMsg] call A3A_fnc_customHint;
    };
    _damage
}];
_unit setVariable ["CL_aiControl_eh2", _eh2];

_unit allowDamage true;
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
    if (!isDamageAllowed _unit) then { _unit allowDamage true; };
    if (!isDamageAllowed _owner) then { _owner allowDamage true; };
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

if (alive _owner && {player != _owner}) then {
    selectPlayer _owner;
};

// Safely preserve squad hierarchy without breaking groups if incapacitated
if (alive _owner) then {
    if (group _owner != _origGroup) then {
        [_owner] joinSilent _origGroup;
    };
    if !(_owner getVariable ["incapacitated", false]) then {
        _origGroup selectLeader _owner;
    };
};

if (!isNull _unit && {alive _unit}) then {
    _unit allowDamage true;
    if (group _unit != _unitOrigGroup) then {
        [_unit] joinSilent _unitOrigGroup;
    };
};

if (alive _owner) then {
    _owner allowDamage true;
};

// Preserve unconscious menu if the player is currently incapacitated
if (alive player && {player getVariable ["incapacitated", false]}) then {
    if (isNil "respawnMenu") then {
        respawnMenu = (findDisplay 46) displayAddEventHandler ["KeyDown", SCRT_fnc_common_unconsciousEventHandler];
    };
} else {
    if (!isNil "respawnMenu") then {
        (findDisplay 46) displayRemoveEventHandler ["KeyDown", respawnMenu];
        respawnMenu = nil;
    };
};

_unit setVariable ["controlReturned", nil, true];
_unit setVariable ["owner", nil, true];
_unit setVariable ["A3A_player", nil, true];
_unit setVariable ["CL_aiControl_accumDmg", nil];
_unit setVariable ["CL_aiControl_eh2", nil];
_unit removeEventHandler ["HandleDamage", _eh2];

_owner setVariable ["controlReturned", nil, true];
_owner setVariable ["originalBody", nil, true];
_owner setVariable ["CL_controlledAI", nil, true];
_owner setVariable ["CL_aiControl_accumDmg", nil];
_owner setVariable ["CL_aiControl_eh1", nil];
_owner setVariable ["A3A_blockRevive", nil, true];
_owner removeEventHandler ["HandleDamage", _eh1];

if (alive _owner && {!(_owner getVariable ["incapacitated", false])}) then {
    [_hintTitle, ["STR_control_unit_return_to_original_body", "Control returned to original body."] call _fnc_loc] call A3A_fnc_customHint;
    playSound "A3AP_UiSuccess";
};

