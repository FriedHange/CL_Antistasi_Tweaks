/*
    fn_controlHCsquad.sqf
    Override of A3A_fnc_controlHCsquad.
    Maintainer: CL Antistasi Tweaks Extender (original: Antistasi Ultimate)

    Changes vs vanilla:
      1. Time limit reads A3A_tweak_aiControlTimeOverride instead of aiControlTime.
         If the value is -1, the timer is set to 999999 (effectively unlimited).
      2. Damage cancellation uses a configurable threshold (A3A_tweak_aiControlDamageThreshold).
         At threshold == 0 (default) the behaviour is identical to vanilla (any damage).
         At threshold == 1.01 control is only revoked when the unit becomes incapacitated or dies.

    Scope: Client
    Environment: Any
*/

private _rawInput = if (_this isEqualTo [] || isNil "_this") then { hcSelected player } else { _this };
private _groups = if (_rawInput isEqualType []) then { _rawInput } else { [_rawInput] };

if (_groups isEqualTo []) exitWith {
    [localize "STR_control_unit_hint_header", localize "STR_control_unit_error_no_squad_selected"] call A3A_fnc_customHint;
};

private _first = _groups select 0;
private _unit = objNull;

if (_first isEqualType objNull) then {
    if (_first isKindOf "CAManBase") then {
        _unit = _first;
    };
} else {
    if (_first isEqualType grpNull) then {
        _unit = leader _first;
    };
};

if (isNull _unit) exitWith {
    [localize "STR_control_unit_hint_header", localize "STR_control_unit_error_no_squad_selected"] call A3A_fnc_customHint;
};

if (_unit == Petros) exitWith {
    [localize "STR_control_unit_hint_header", localize "STR_control_unit_error_petros"] call A3A_fnc_customHint;
};
if (captive player) exitWith {
    [localize "STR_control_unit_hint_header", localize "STR_control_unit_error_undercover"] call A3A_fnc_customHint;
};
if (player != leader group player) exitWith {
    [localize "STR_control_unit_hint_header", localize "STR_control_unit_error_no_squad_leader"] call A3A_fnc_customHint;
};
if (isPlayer _unit) exitWith {
    [localize "STR_control_unit_hint_header", localize "STR_control_unit_error_no_player"] call A3A_fnc_customHint;
};
if (!(alive _unit) or (_unit getVariable ["incapacitated", false])) exitWith {
    [localize "STR_control_unit_hint_header", localize "STR_control_unit_error_alive_only"] call A3A_fnc_customHint;
};
if (side _unit != teamPlayer) exitWith {
    [localize "STR_control_unit_hint_header", format [localize "STR_control_unit_error_rebel_only", A3A_faction_reb get "name"]] call A3A_fnc_customHint;
};
if (!isNil "A3A_FFPun_Jailed" && {(getPlayerUID player) in A3A_FFPun_Jailed}) exitWith {
    [localize "STR_control_unit_hint_header", localize "STR_control_unit_error_punish"] call A3A_fnc_customHint;
};

private _owner = player getVariable ["owner", player];
if (_owner != player) exitWith {
    [localize "STR_control_unit_hint_header", localize "STR_control_unit_error_ai_recursion"] call A3A_fnc_customHint;
};

{
    if (_x != vehicle _x) then {
        [_x] orderGetIn true;
    };
} forEach units group player;

private _face    = face _unit;
private _speaker = speaker _unit;

_unit setVariable ["owner", player, true];

// --- Configurable damage threshold ---
private _damageThreshold = missionNamespace getVariable ["A3A_tweak_aiControlDamageThreshold", 0];

// HandleDamage EH on the original player body
private _eh1 = player addEventHandler ["HandleDamage", {
    params ["_unit", "_selection", "_damage"];
    private _threshold = missionNamespace getVariable ["A3A_tweak_aiControlDamageThreshold", 0];

    if (_threshold <= 0 || { _selection == "" && { _damage >= _threshold } }) then {
        _unit removeEventHandler ["HandleDamage", _thisEventHandler];
        _unit setVariable ["controlReturned", true, true];
        private _possessed = player;
        if (!isNull _possessed) then { _possessed setVariable ["controlReturned", true, true]; };
        [localize "STR_control_unit_hint_header", localize "STR_control_unit_damage_control_return_player"] call A3A_fnc_customHint;
    };
    nil
}];

// HandleDamage EH on the possessed AI unit
private _eh2 = _unit addEventHandler ["HandleDamage", {
    params ["_unit", "_selection", "_damage"];
    private _threshold = missionNamespace getVariable ["A3A_tweak_aiControlDamageThreshold", 0];

    if (_threshold <= 0 || { _selection == "" && { _damage >= _threshold } }) then {
        _unit removeEventHandler ["HandleDamage", _thisEventHandler];
        _unit setVariable ["controlReturned", true, true];
        private _origOwner = _unit getVariable ["owner", objNull];
        if (!isNull _origOwner) then { _origOwner setVariable ["controlReturned", true, true]; };
        [localize "STR_control_unit_hint_header", localize "STR_control_unit_damage_control_return_ai"] call A3A_fnc_customHint;
    };
    nil
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

private _returnActionId = _unit addAction [
    format ["<t color='#FFD700'>%1</t>", localize "STR_antistasi_actions_return_control_to_ai"],
    {
        params ["_target"];
        _target setVariable ["controlReturned", true, true];
        private _origOwner = _target getVariable ["owner", _target];
        _origOwner setVariable ["controlReturned", true, true];
    },
    nil, 10, true, true, "", "true"
];

waitUntil {
    sleep 1;
    private _displayTime = if (_timeX > 9999) then { "∞" } else { str _timeX };
    [localize "STR_control_unit_hint_header", format [localize "STR_control_unit_time_to_return_to_original_body", _displayTime]] call A3A_fnc_customHint;
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

removeAllActions _unit;
selectPlayer (_unit getVariable ["owner", _unit]);
(units group player) joinsilent group player;
group player selectLeader player;

if (!isNil "respawnMenu") then {
    (findDisplay 46) displayRemoveEventHandler ["KeyDown", respawnMenu];
    respawnMenu = nil;
};

_unit setVariable ["CL_aiControl_accumDmg", nil];
player setVariable ["CL_aiControl_accumDmg", nil];
_unit removeEventHandler ["HandleDamage", _eh2];
player removeEventHandler ["HandleDamage", _eh1];
[localize "STR_control_unit_hint_header", localize "STR_control_unit_return_to_original_body"] call A3A_fnc_customHint;
playSound "A3AP_UiSuccess";
