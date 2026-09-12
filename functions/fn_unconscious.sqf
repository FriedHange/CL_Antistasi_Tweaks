/*
    fn_unconscious.sqf
    Override of A3A_fnc_unconscious.
    Maintainer: CL Antistasi Tweaks Extender

    Supports configurable unconscious keys via Arma 3 Custom Controls (User Action 1 - 20)
    and dynamically displays active key bindings in the on-screen UI prompts.

    Scope: Any
    Environment: Scheduled
*/

params ["_unit", "_injurer"];

private _bleedOut = time + 450;
private _isPlayer = false;
private _playersX = false;
private _inPlayerGroup = false;
private _handlerCountdown = 0;
_unit setBleedingremaining 300;

private _fnc_applyPostEffect = {
	"colorCorrections" ppEffectAdjust [1,1,0, [0.1,0.2,0.3,-0.5], [1,1,1,0.4], [0.5,0.2,0,1]]; 
	"colorCorrections" ppEffectCommit 0; 
	"colorCorrections" ppEffectEnable true;
	
	"filmGrain" ppEffectAdjust [0.05, 1, 1, 0, 1]; 
	"filmGrain" ppEffectCommit 0; 
	"filmGrain" ppEffectEnable true;
};

private _fnc_selfReviveCountdownStart = {
	private _diff = (_unit getVariable ["A3A_selfReviveTimeout", -1]) - time;
	private _initialCountDown = [_diff] call BIS_fnc_countDown;

	if (_diff > 0) then {
		_handlerCountdown = addMissionEventHandler [
			"EachFrame", 
			{ 
				[
					localize "STR_antistasi_actions_unconscious_self_withstand_countdown",
					format[
						[(([0] call BIS_fnc_countdown) / 60) + .01, "HH:MM"] call BIS_fnc_timetostring
					],
					true
				] call A3A_fnc_customHint
			}
		];
	}
	else {
		_handlerCountdown = addMissionEventHandler [
			"EachFrame", 
			{ 
				[
					localize "STR_antistasi_actions_unconscious_self_withstand_countdown",
					format[
						"<t color='#008000'>%1</t>", 
						localize "STR_antistasi_actions_unconscious_self_withstand_ready"
					],
					true
				] call A3A_fnc_customHint
			}
		];
	};
};

private _fnc_selfReviveCountdownStop = {
	removeMissionEventHandler ["EachFrame", _handlerCountdown];
};

// Helper function to resolve key name from action number or return fallback
private _fnc_getKeyName = {
	params ["_actionNum", "_defaultName"];
	if (_actionNum <= 0) exitWith { _defaultName };
	private _actionName = format ["User%1", _actionNum];
	if (actionKeys _actionName isEqualTo []) exitWith { _defaultName };
	private _raw = actionKeysNames _actionName;
	if (_raw isEqualTo "") exitWith { _defaultName };
	
	// Remove all quotes so e.g. '"Space"' -> 'Space' and '"User 1"' -> 'User 1'
	private _clean = "";
	private _quoteChars = [toString [34], toString [39]];
	for "_i" from 0 to ((count _raw) - 1) do {
		private _char = _raw select [_i, 1];
		if !(_char in _quoteChars) then {
			_clean = _clean + _char;
		};
	};
	if (_clean isEqualTo "") then { _defaultName } else { _clean };
};

// Helper function to replace key in localized prompt
private _fnc_replacePromptKey = {
	params ["_text", "_keyType", "_newKey"];
	if (_newKey isEqualTo _keyType) exitWith { _text };
	
	private _replacements = [];
	switch (_keyType) do {
		case "R": {
			_replacements = [
				[" R ", " " + _newKey + " "],
				[" R,", " " + _newKey + ","],
				["按R键", "按" + _newKey + "键"],
				["按 R 键", "按 " + _newKey + " 键"],
				[">R ", ">" + _newKey + " "]
			];
		};
		case "T": {
			_replacements = [
				[" T ", " " + _newKey + " "],
				[" T,", " " + _newKey + ","],
				["按 T 键", "按 " + _newKey + " 键"],
				["按T键", "按" + _newKey + "键"],
				[">T ", ">" + _newKey + " "]
			];
		};
		case "H": {
			_replacements = [
				[" H ", " " + _newKey + " "],
				[" H,", " " + _newKey + ","],
				["按 H 键", "按 " + _newKey + " 键"],
				["按H键", "按" + _newKey + "键"],
				[">H키", ">" + _newKey + "키"],
				[">H ", ">" + _newKey + " "]
			];
		};
	};

	{
		_x params ["_needle", "_replace"];
		private _res = "";
		private _needleLen = count _needle;
		private _idx = _text find _needle;
		while {_idx != -1} do {
			_res = _res + (_text select [0, _idx]) + _replace;
			_text = _text select [_idx + _needleLen, count _text];
			_idx = _text find _needle;
		};
		_text = _res + _text;
	} forEach _replacements;

	_text
};

// Unconditionally restore allowDamage true after the 5s transition delay
_unit spawn {
	sleep 5;
	_this allowDamage true;
};

if (isPlayer _unit) then {
	_isPlayer = true;
	closeDialog 0;
	if (!isNil "respawnMenu") then {(findDisplay 46) displayRemoveEventHandler ["KeyDown", respawnMenu]};
	respawnMenu = (findDisplay 46) displayAddEventHandler ["KeyDown", SCRT_fnc_common_unconsciousEventHandler];
	if (_injurer != Invaders) then {
		_unit setCaptive true
	};

	if (useDownedNotification) then {
		[_unit, localize "STR_A3AU_downed_help"] remoteExec ["globalChat", 0];
	};

	openMap false;

	{
		unassignVehicle _x;  // Ensure AI aren't assigned to a vehicle
		if ((!isPlayer _x) and (vehicle _x != _x) and (_x distance _unit < 50)) then {
			_x action ["getOut", vehicle _x];  // Added to force AI to get out of the vehicle
			[_x] orderGetIn false;
		};
	} forEach units group _unit;
}
else {
	if ({isPlayer _x} count units  group _unit > 0) then {_inPlayerGroup = true};
	_unit stop true;
	if (_inPlayerGroup) then {
		[_unit,"heal1"] remoteExec ["A3A_fnc_flagaction",0,_unit];

		if (_injurer != Invaders) then {
			_unit setCaptive true
		};
	}
	else {
		if ({if ((isPlayer _x) and (_x distance _unit < distanceSPWN2)) exitWith {1}} count allUnits != 0) then {
				_playersX = true;
				[_unit,"heal"] remoteExec ["A3A_fnc_flagaction",0,_unit];
			if (_unit != petros && {_injurer != Invaders}) then {
			    _unit setCaptive true
			};
		};
	};
};

if (_isPlayer) then {
	[] call _fnc_applyPostEffect;
	[] call _fnc_selfReviveCountdownStart;
};

_unit setFatigue 1;
sleep 2;
if (_isPlayer) then {
	group _unit setCombatMode "YELLOW";
	[_unit,"heal1"] remoteExec ["A3A_fnc_flagaction",0,_unit];

	if (isDiscordRichPresenceActive) then {
		private _possibleMarkers = outposts + airportsX + resourcesX + factories + seaports + milbases + ["NATO_carrier", "CSAT_carrier"];
		private _nearestMarker = [_possibleMarkers, player] call BIS_fnc_nearestPosition;
		private _locationName = [_nearestMarker] call A3A_fnc_localizar;

		if(player distance2D (getMarkerPos _nearestMarker) < 300) then {
			[["UpdateState", format ["Lying incapacitated at the %1", _locationName]]] call SCRT_fnc_misc_updateRichPresence;
		} else {
			[["UpdateState", "Lying incapacitated in the middle of nowhere"]] call SCRT_fnc_misc_updateRichPresence;
		};
	};
};

//declaring out of scope helps with perf
private _textX = "";
private _consciousUnits = [];
private _helper = objNull;
private _originalBody = objNull;

private _nextRequest = 0;

while {time < _bleedOut && _unit getVariable ["incapacitated",false] && alive _unit} do {
	// Space out help requests increasingly with failures
	_helper = _unit getVariable ["helped", objNull];

	if (isNull _helper and _nextRequest < time) then {
		_helper = [_unit] call A3A_fnc_askHelp;
		if (AIrevivesOutsideSquad isNotEqualTo -1 && {isNull _helper}) then {
			_helper = [_unit] call A3A_fnc_askAnyoneHelp; //in case there is no helper found in _units group
		};
		private _requestGap = (2 + (_unit getVariable ["helpFailed", 0]))^2;
		_nextRequest = if (isPlayer _unit) then { time + _requestGap/2 } else { time + _requestGap };
	};

	if (_isPlayer) then	{
		//selectPlayer from possession feature switches unit
		_originalBody = _unit getVariable ["originalBody", objNull];
		if (_originalBody isNotEqualTo objNull) then {
			_helper = _originalBody;
		};

		_consciousUnits = [] call SCRT_fnc_ai_getNearFriendlyUnits;

		private _respawnAction = missionNamespace getVariable ["A3A_tweak_unconsciousRespawnAction", 0];
		private _possessAction = missionNamespace getVariable ["A3A_tweak_unconsciousPossessAction", 0];
		private _withstandAction = missionNamespace getVariable ["A3A_tweak_unconsciousWithstandAction", 0];

		private _rKey = [_respawnAction, "R"] call _fnc_getKeyName;
		private _tKey = [_possessAction, "T"] call _fnc_getKeyName;
		private _hKey = [_withstandAction, "H"] call _fnc_getKeyName;

		private _possessPrompt = "";
		if (count _consciousUnits > 0) then {
			_possessPrompt = [localize "STR_antistasi_actions_unconscious_action_prompt_possess", "T", _tKey] call _fnc_replacePromptKey;
		};

		private _selfRevive = ["", localize "STR_antistasi_actions_unconscious_action_prompt_selfrevive"] select ("A3AP_SelfReviveKit" in (backpackItems player));

		if (A3A_selfReviveMethods) then {
			_selfRevive = [localize "STR_antistasi_actions_unconscious_action_prompt_withstand", "H", _hKey] call _fnc_replacePromptKey;
		};

		_textX = format [
			localize "STR_antistasi_actions_unconscious_action_prompt0_base", 
			_possessPrompt,
			_selfRevive
		];
	
		if !(isNull _helper) then {
			if (_helper distance _unit < 3) then {
				_textX = format [ localize "STR_antistasi_actions_unconscious_action_prompt1_base", 
					name _helper, 
					_possessPrompt,
					_selfRevive
				];
			} else {
				_textX = format [localize "STR_antistasi_actions_unconscious_action_prompt2_base", 
					name _helper, 
					_possessPrompt,
					_selfRevive
				];
			};
		};

		_textX = [_textX, "R", _rKey] call _fnc_replacePromptKey;

		if !(isNull _originalBody) then {
			_textX = localize "STR_antistasi_actions_unconscious_action_possessed";
		};

		private _layer = ["A3A_infoCenter"] call BIS_fnc_rscLayer;
		[_textX,0,0,3,0,0,_layer] spawn bis_fnc_dynamicText;
	};

	sleep 3;
	if !(isNull attachedTo _unit) then {_bleedOut = _bleedOut + 3};			// delay bleedout if dragged or loaded into vehicle
	if (random 20 < 1) then {playSound3D [(selectRandom injuredSounds),_unit,false, getPosASL _unit, 1, 1, 50]};
};
if (_isPlayer) then {
	"colorCorrections" ppEffectCommit 0; 
	"colorCorrections" ppEffectEnable false;

	"filmGrain" ppEffectCommit 0; 
	"filmGrain" ppEffectEnable false;
};

if (_isPlayer) then {
	(findDisplay 46) displayRemoveEventHandler ["KeyDown", respawnMenu];
	[_unit,"remove"] remoteExec ["A3A_fnc_flagaction",0,_unit];
	[] call _fnc_selfReviveCountdownStop;
}
else {
	_unit stop false;
	if (_inPlayerGroup or _playersX) then {
		[_unit,"remove"] remoteExec ["A3A_fnc_flagaction",0,_unit];
	};
};

if (captive _unit) then {_unit setCaptive false};
_unit setVariable ["overallDamage",damage _unit];
if (_isPlayer and (_unit getVariable ["respawn",false])) exitWith {};

if (time > _bleedOut) exitWith {
	if (_isPlayer) then {
		_unit call A3A_fnc_respawn;
		[] call _fnc_selfReviveCountdownStop;
	}
	else {
		_unit allowDamage true;
		_unit setDamage 1;
	};
};

if (alive _unit) then {
	_unit setUnconscious false;
	_unit switchMove "unconsciousoutprone";
	_unit setBleedingRemaining 0;
	_unit allowDamage true;
	[] call _fnc_selfReviveCountdownStop;

	if (isPlayer _unit) then {
		[] call SCRT_fnc_misc_updateRichPresence;
	};
};
