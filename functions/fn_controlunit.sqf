/*
    fn_controlunit.sqf
    Override of A3A_fnc_controlunit.
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

params ["_units"];

private _unit = _units select 0;

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

    if (_threshold <= 0) then {
        // Vanilla: any hit returns control immediately
        _unit removeEventHandler ["HandleDamage", _thisEventHandler];
        selectPlayer _unit;
        (units group player) joinsilent group player;
        group player selectLeader player;
        [localize "STR_control_unit_hint_header", localize "STR_control_unit_damage_control_return_player"] call A3A_fnc_customHint;
    } else {
        if (_selection == "" && { _damage >= _threshold }) then {
            _unit removeEventHandler ["HandleDamage", _thisEventHandler];
            selectPlayer _unit;
            (units group player) joinsilent group player;
            group player selectLeader player;
            [localize "STR_control_unit_hint_header", localize "STR_control_unit_damage_control_return_player"] call A3A_fnc_customHint;
        };
    };
    nil
}];

// HandleDamage EH on the possessed AI unit
private _eh2 = _unit addEventHandler ["HandleDamage", {
    params ["_unit", "_selection", "_damage"];
    private _threshold = missionNamespace getVariable ["A3A_tweak_aiControlDamageThreshold", 0];

    if (_threshold <= 0) then {
        // Vanilla: any hit returns control immediately
        _unit removeEventHandler ["HandleDamage", _thisEventHandler];
        removeAllActions _unit;
        selectPlayer (_unit getVariable ["owner", _unit]);
        (units group player) joinsilent group player;
        group player selectLeader player;
        [localize "STR_control_unit_hint_header", localize "STR_control_unit_damage_control_return_ai"] call A3A_fnc_customHint;
    } else {
        if (_selection == "" && { _damage >= _threshold }) then {
            _unit removeEventHandler ["HandleDamage", _thisEventHandler];
            removeAllActions _unit;
            selectPlayer (_unit getVariable ["owner", _unit]);
            (units group player) joinsilent group player;
            group player selectLeader player;
            [localize "STR_control_unit_hint_header", localize "STR_control_unit_damage_control_return_ai"] call A3A_fnc_customHint;
        };
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

_unit addAction [(localize "STR_antistasi_actions_return_control_to_ai"), {
    selectPlayer leader (group (_this select 0));
}];

waitUntil {
    sleep 1;
    private _displayTime = if (_timeX > 9999) then { "∞" } else { str _timeX };
    [localize "STR_control_unit_hint_header", format [localize "STR_control_unit_time_to_return_to_original_body", _displayTime]] call A3A_fnc_customHint;
    _timeX = _timeX - 1;

    (_timeX == -1) or {
        !alive _unit or {
            (_unit getVariable ["incapacitated", false]) or {
                (!([_unit] call A3A_fnc_canFight)) or {
                    (isPlayer (leader group player))
                }
            }
        }
    }
};

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
