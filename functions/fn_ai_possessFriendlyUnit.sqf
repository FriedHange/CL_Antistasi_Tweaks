/*
    fn_ai_possessFriendlyUnit.sqf
    Override of SCRT_fnc_ai_possessFriendlyUnit.
    Maintainer: CL Antistasi Tweaks Extender (original: Socrates / Antistasi Ultimate)

    Changes vs vanilla:
      1. Time limit reads A3A_tweak_aiControlTimeOverride instead of aiControlTime.
         If the value is -1, the timer is set to 999999 (effectively unlimited).
      2. Damage cancellation uses a configurable threshold (A3A_tweak_aiControlDamageThreshold).
         At threshold == 0 (default) the behaviour is identical to vanilla (any damage).
         At threshold == 1.01 control is only revoked when the unit becomes incapacitated or dies.

    Return Value:
        <ARRAY> Units

    Scope: Client
    Environment: Any
    Public: Yes
*/

#include "\a3\ui_f\hpp\definedikcodes.inc"

params ["_unit"];

if (_unit == Petros) exitWith {
    [localize "STR_control_unit_hint_header", localize "STR_control_unit_error_petros"] call A3A_fnc_customHint;
};
if (isPlayer _unit) exitWith {
    [localize "STR_control_unit_hint_header", localize "STR_control_unit_error_no_player"] call A3A_fnc_customHint;
};
if (!(alive _unit) or (_unit getVariable ["incapacitated",false]))  exitWith {
    [localize "STR_control_unit_hint_header", localize "STR_control_unit_error_alive_only"] call A3A_fnc_customHint;
};
if (side _unit != teamPlayer) exitWith {
    [localize "STR_control_unit_hint_header", format [localize "STR_control_unit_error_rebel_only", A3A_faction_reb get "name"]] call A3A_fnc_customHint;
};

private _owner = player getVariable ["owner", player];
if (_owner != player) exitWith {
    [localize "STR_control_unit_hint_header", localize "STR_control_unit_error_ai_recursion"] call A3A_fnc_customHint;
};

private _face    = face _unit;
private _speaker = speaker _unit;

player setVariable ["originalBody", player];
player setVariable ["A3A_blockRevive", true, true];

_unit setVariable ["owner", player, true];
_unit setVariable ["A3A_player", player];
private _originalBody = player;

// --- Configurable damage threshold ---
// 0   = any damage returns control (vanilla)
// 0.3 = light wound
// 0.6 = heavy wound
// 1.01 = only incapacitation/death returns control (effectively ignores damage)
private _damageThreshold = missionNamespace getVariable ["A3A_tweak_aiControlDamageThreshold", 0];

// HandleDamage EH on the original player body
private _playerEh = player addEventHandler ["HandleDamage", {
    params ["_unit", "_selection", "_damage"];
    private _threshold = missionNamespace getVariable ["A3A_tweak_aiControlDamageThreshold", 0];
    private _player = _unit;

    if (_threshold <= 0) then {
        // Vanilla: any hit returns control immediately
        _player removeEventHandler ["HandleDamage", _thisEventHandler];
        selectPlayer _player;
        (units group player) joinsilent group player;
        group player selectLeader player;
        _player setVariable ["controlReturned", true];
        [localize "STR_control_unit_hint_header", localize "STR_control_unit_damage_control_return_player"] call A3A_fnc_customHint;
    } else {
        if (_selection == "" && { _damage >= _threshold }) then {
            _player removeEventHandler ["HandleDamage", _thisEventHandler];
            selectPlayer _player;
            (units group player) joinsilent group player;
            group player selectLeader player;
            _player setVariable ["controlReturned", true];
            [localize "STR_control_unit_hint_header", localize "STR_control_unit_damage_control_return_player"] call A3A_fnc_customHint;
        };
    };
    nil
}];

// HandleDamage EH on the possessed AI unit
private _unitEh = _unit addEventHandler ["HandleDamage", {
    params ["_unit", "_selection", "_damage"];
    private _threshold = missionNamespace getVariable ["A3A_tweak_aiControlDamageThreshold", 0];

    if (_threshold <= 0) then {
        // Vanilla: any hit returns control immediately
        _unit removeEventHandler ["HandleDamage", _thisEventHandler];
        selectPlayer (_unit getVariable "A3A_player");
        (units group player) joinsilent group player;
        group player selectLeader player;
        _unit setVariable ["controlReturned", true];
        [localize "STR_control_unit_hint_header", localize "STR_control_unit_damage_control_return_ai"] call A3A_fnc_customHint;
    } else {
        if (_selection == "" && { _damage >= _threshold }) then {
            _unit removeEventHandler ["HandleDamage", _thisEventHandler];
            selectPlayer (_unit getVariable "A3A_player");
            (units group player) joinsilent group player;
            group player selectLeader player;
            _unit setVariable ["controlReturned", true];
            [localize "STR_control_unit_hint_header", localize "STR_control_unit_damage_control_return_ai"] call A3A_fnc_customHint;
        };
    };
    nil
}];

selectPlayer _unit;
[_unit, createHashMapFromArray [["face", _face], ["speaker", _speaker]]] call A3A_fnc_setIdentity;

// --- Configurable time limit ---
// -1 in the param means Unlimited → set to a very large number so the countdown
// still ticks (giving the player a visible "time remaining" HUD) but never expires.
private _configTime = missionNamespace getVariable ["A3A_tweak_aiControlTimeOverride", aiControlTime];
private _timeX = if (_configTime == -1) then { 999999 } else { _configTime };

private _returnActionId = _unit addAction [(localize "STR_antistasi_actions_return_control_to_ai"), {
    params ["_unit"];
    private _player = _unit getVariable "A3A_player";
    _unit setVariable ["controlReturned", true];
    selectPlayer _player;
}];
private _healActionId = [_originalBody, "heal2"] call A3A_fnc_flagaction;

private _layer = ["A3A_infoCenter"] call BIS_fnc_rscLayer;
[localize "STR_antistasi_actions_unconscious_action_possessed", 0, 0, 3, 0, 0, _layer] spawn bis_fnc_dynamicText;

waitUntil {
    sleep 1;
    // Show a capped timer (cap display at 9999 for Unlimited so it doesn't look odd)
    private _displayTime = if (_timeX > 9999) then { "∞" } else { str _timeX };
    [localize "STR_control_unit_hint_header", format [localize "STR_control_unit_time_to_return_to_original_body", _displayTime]] call A3A_fnc_customHint;
    _timeX = _timeX - 1;

    _timeX == -1 ||
    {!alive _unit ||
    {_unit getVariable ["incapacitated", false] ||
    {!([_unit] call A3A_fnc_canFight) ||
    {!(_originalBody getVariable ["incapacitated", false]) ||
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
_unit setVariable ["A3A_player", nil];
_unit setVariable ["CL_aiControl_accumDmg", nil];
_unit removeEventHandler ["HandleDamage", _unitEh];

[localize "STR_control_unit_hint_header", localize "STR_control_unit_return_to_original_body"] call A3A_fnc_customHint;

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
