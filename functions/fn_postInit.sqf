/*
	    fn_postInit.sqf
	    Initialize the Antistasi Ultimate Tweaks Extender.
	    Overrides core functions with customized versions.
*/
diag_log "[A3A Ultimate Tweaks Extender] Initializing overrides...";

// Override self-revive and marker area functions
A3A_fnc_selfRevive_original = A3A_fnc_selfRevive;
A3A_fnc_selfRevive = compile preprocessFileLineNumbers "\CL_Antistasi_Tweaks\functions\fn_selfRevive.sqf";
A3A_fnc_isWithinMarkerArea = compile preprocessFileLineNumbers "\CL_Antistasi_Tweaks\functions\fn_isWithinMarkerArea.sqf";

// Override unconscious handler and loop for custom keys and dynamic UI prompts
SCRT_fnc_common_unconsciousEventHandler = compile preprocessFileLineNumbers "\CL_Antistasi_Tweaks\functions\fn_common_unconsciousEventHandler.sqf";
A3A_fnc_unconscious = compile preprocessFileLineNumbers "\CL_Antistasi_Tweaks\functions\fn_unconscious.sqf";

// Override AI direct control functions to support configurable time limit and damage threshold
SCRT_fnc_ai_possessFriendlyUnit = compile preprocessFileLineNumbers "\CL_Antistasi_Tweaks\functions\fn_ai_possessFriendlyUnit.sqf";
A3A_fnc_ai_possessFriendlyUnit = SCRT_fnc_ai_possessFriendlyUnit;
A3A_fnc_controlunit = compile preprocessFileLineNumbers "\CL_Antistasi_Tweaks\functions\fn_controlunit.sqf";
A3A_fnc_controlHCsquad = compile preprocessFileLineNumbers "\CL_Antistasi_Tweaks\functions\fn_controlHCsquad.sqf";

// Override onPlayerRespawn with safety wrapper
A3A_fnc_onPlayerRespawn_original = A3A_fnc_onPlayerRespawn;
A3A_fnc_onPlayerRespawn = compile preprocessFileLineNumbers "\CL_Antistasi_Tweaks\functions\fn_onPlayerRespawn.sqf";

// Helper function to stop controlling AI unit and return to player body immediately
A3A_fnc_returnControl = {
	if (!hasInterface) exitWith {};
	player setVariable ["controlReturned", true, true];
	private _owner = player getVariable ["owner", player];
	if (_owner != player) then {
		_owner setVariable ["controlReturned", true, true];
	};
	private _orig = player getVariable ["originalBody", objNull];
	if (!isNull _orig) then {
		_orig setVariable ["controlReturned", true, true];
	};
};
CL_fnc_returnControl = A3A_fnc_returnControl;

// Override builder placing objects function to support auto-building.
// A3A_fnc_placeBuilderObjects is freshly compiled by CfgFunctions at every mission start, 
// so we always capture the real original here at postInit time.
A3A_fnc_placeBuilderObjects_original = A3A_fnc_placeBuilderObjects;
A3A_fnc_placeBuilderObjects = compile preprocessFileLineNumbers "\CL_Antistasi_Tweaks\functions\fn_placeBuilderObjects.sqf";

// compile the helper builder UI resizer globally
A3A_fnc_builderUIResize = compile preprocessFileLineNumbers "\CL_Antistasi_Tweaks\functions\fn_builderUIResize.sqf";

// Override team leader placer dialog to inject expand/collapse button.
A3A_fnc_teamLeaderRTSPlacerDialog_original = A3A_fnc_teamLeaderRTSPlacerDialog;
A3A_fnc_teamLeaderRTSPlacerDialog = compile preprocessFileLineNumbers "\CL_Antistasi_Tweaks\functions\fn_teamLeaderRTSPlacerDialog.sqf";
A3A_fnc_teamLeaderRTSPlacerDialog_toggleHeight = compile preprocessFileLineNumbers "\CL_Antistasi_Tweaks\functions\fn_teamLeaderRTSPlacerDialog_toggleHeight.sqf";

// Override Petros mission requests, resourcecheck, and fast travel
A3A_fnc_missionRequest_original = A3A_fnc_missionRequest;
A3A_fnc_missionRequest = compile preprocessFileLineNumbers "\CL_Antistasi_Tweaks\functions\fn_missionRequest.sqf";
A3A_fnc_resourcecheck = compile preprocessFileLineNumbers "\CL_Antistasi_Tweaks\functions\fn_resourcecheck.sqf";
A3A_fnc_fastTravelRadio = compile preprocessFileLineNumbers "\CL_Antistasi_Tweaks\functions\fn_fastTravelRadio.sqf";

// Override builder actions and builder complete handlers
A3A_fnc_addBuildingActions = compile preprocessFileLineNumbers "\CL_Antistasi_Tweaks\functions\fn_addBuildingActions.sqf";
A3A_fnc_buildingComplete = compile preprocessFileLineNumbers "\CL_Antistasi_Tweaks\functions\fn_buildingComplete.sqf";

// Override commander menu populator and tab change functions
SCRT_fnc_ui_populateCommanderMenu_original = SCRT_fnc_ui_populateCommanderMenu;
SCRT_fnc_ui_populateCommanderMenu = compile preprocessFileLineNumbers "\CL_Antistasi_Tweaks\functions\fn_ui_populateCommanderMenu.sqf";
SCRT_fnc_ui_changeTab_original = SCRT_fnc_ui_changeTab;
SCRT_fnc_ui_changeTab = compile preprocessFileLineNumbers "\CL_Antistasi_Tweaks\functions\fn_ui_changeTab.sqf";

// compile planning functions
A3A_fnc_planning_init = compile preprocessFileLineNumbers "\CL_Antistasi_Tweaks\functions\fn_planning_init.sqf";
A3A_fnc_planning_cacheVehicles = compile preprocessFileLineNumbers "\CL_Antistasi_Tweaks\functions\fn_planning_cacheVehicles.sqf";
A3A_fnc_planning_ui = compile preprocessFileLineNumbers "\CL_Antistasi_Tweaks\functions\fn_planning_ui.sqf";
A3A_fnc_planning_execute = compile preprocessFileLineNumbers "\CL_Antistasi_Tweaks\functions\fn_planning_execute.sqf";
A3A_fnc_planning_sectorControl = compile preprocessFileLineNumbers "\CL_Antistasi_Tweaks\functions\fn_planning_sectorControl.sqf";
A3A_fnc_planning_supportAI = compile preprocessFileLineNumbers "\CL_Antistasi_Tweaks\functions\fn_planning_supportAI.sqf";
A3A_fnc_planning_vehicleOverwatch = compile preprocessFileLineNumbers "\CL_Antistasi_Tweaks\functions\fn_planning_vehicleOverwatch.sqf";
A3A_fnc_planning_airOverwatch = compile preprocessFileLineNumbers "\CL_Antistasi_Tweaks\functions\fn_planning_airOverwatch.sqf";
A3A_fnc_planning_showNotification = compile preprocessFileLineNumbers "\CL_Antistasi_Tweaks\functions\fn_planning_showNotification.sqf";

// Global locality wrappers for planning system
A3A_fnc_planning_localCleanupMarkers = {
	params [["_deleteAll", false, [false]]];
	if (hasInterface) then {
		if (_deleteAll) then {
			if ("A3A_planning_AO" in allMapMarkers) then {
				deleteMarkerLocal "A3A_planning_AO";
			};
		};
		{
			deleteMarkerLocal ("A3A_planning_entry_" + _x);
		} forEach ["Alpha", "Beta", "Gamma", "Delta"];
		A3A_planning_entryPoints = [];
		A3A_planning_objective = "";
		A3A_planning_queue = [];
	};
	// Clean up travel and tracking markers globally
	{
		if ((_x find "A3A_planning_travel_") == 0 || { (_x find "A3A_planning_track_") == 0 }) then {
			deleteMarker _x;
		};
	} forEach allMapMarkers;
};

A3A_fnc_planning_localAddHC = {
	params [["_group", grpNull, [grpNull]]];
	if (isNull _group) exitWith {};
	if (hasInterface) then {
		player hcSetGroup [_group];
		diag_log format ["[A3A Planning] Added group %1 to player's High Command.", groupId _group];
	};
};

A3A_fnc_planning_localSideChat = {
	params [["_message", "", [""]]];
	if (_message == "") exitWith {};
	diag_log format ["[A3A Planning Radio] %1", _message];
	if (hasInterface) then {
		[teamPlayer, "HQ"] sideChat _message;
		systemChat format ["[HQ]: %1", _message];
	};
};

A3A_fnc_planning_localSetCurrentWaypoint = {
	params [["_group", grpNull, [grpNull]], ["_wpIndex", 0, [0]]];
	if (isNull _group) exitWith {};
	_group setCurrentWaypoint [_group, _wpIndex];
};

A3A_fnc_planning_localMoveInGunner = {
	params [["_unit", objNull, [objNull]], ["_vehicle", objNull, [objNull]]];
	if (isNull _unit || { isNull _vehicle }) exitWith {};
	_unit assignAsGunner _vehicle;
	_unit moveInGunner _vehicle;
};

A3A_fnc_planning_localDoWatch = {
	params [["_unit", objNull, [objNull]], ["_pos", [0, 0, 0], [[]]]];
	if (isNull _unit) exitWith {};
	_unit doWatch _pos;
};

A3A_fnc_planning_localArtilleryFire = {
	params [["_vehicle", objNull, [objNull]], ["_pos", [0, 0, 0], [[]]], ["_mag", "", [""]], ["_count", 1, [0]]];
	if (isNull _vehicle || { _mag == "" }) exitWith {};
	_vehicle commandArtilleryFire [_pos, _mag, _count];
};

A3A_fnc_planning_localGetOut = {
	params [["_unit", objNull, [objNull]], ["_vehicle", objNull, [objNull]]];
	if (isNull _unit) exitWith {};
	unassignVehicle _unit;
	[_unit] orderGetIn false;
	if (!isNull _vehicle) then {
		_unit action ["GetOut", _vehicle];
	};
};

A3A_fnc_planning_localDoMove = {
	params [["_unit", objNull, [objNull]], ["_pos", [0, 0, 0], [[]]]];
	if (isNull _unit) exitWith {};
	_unit doMove _pos;
};
// Initialize planning variables and loops
[] call A3A_fnc_planning_init;

// Sync lobby parameters from server to all clients
if (isServer) then {
	diag_log "[A3A Ultimate Tweaks Extender] Loading and broadcasting lobby parameters...";
	{
		_x params ["_paramName", "_defaultValue"];
		private _val = missionNamespace getVariable [_paramName, [_paramName, _defaultValue] call BIS_fnc_getParamValue];
		missionNamespace setVariable [_paramName, _val, true];
		diag_log format ["[A3A Ultimate Tweaks Extender] Synced parameter: %1 = %2", _paramName, _val];
	} forEach [
		["A3A_tweak_autoBuild", 1],
		["A3A_selfReviveTweak_NoKit", -1],
		["A3A_selfReviveTweak_Cooldown", 300],
		["A3A_selfReviveTweak_Damage", 50],
		["A3A_tweak_saveRadiusHQ", 50],
		["A3A_tweak_saveRadiusBuffer", 0],
		["A3A_tweak_missionCooldown", 0],
		["A3A_tweak_randomMissionChanceMultiplier", 100],
		["A3A_tweak_fastTravelSpeedMultiplier", 1],
		["A3A_tweak_builderChainRadius", 0],
		["A3A_tweak_discoveryReveal", 1],
		["A3A_tweak_discoveryDistance", 200],
		["A3A_tweak_maxSiegeSquads", 10],
		["A3A_tweak_siegeRefundOrGarrison", 1],
		["A3A_tweak_siegeTravelTimeMultiplier", 100],
		["A3A_tweak_siegeDeploymentMultiplier", 125],
		["A3A_tweak_aiControlTimeOverride", 120],
		["A3A_tweak_aiControlDamageThreshold", 0],
		["A3A_tweak_remoteHQMenu", 2],
		["A3A_tweak_minSpawnDistance", 0],
		["A3A_tweak_unconsciousRespawnAction", 0],
		["A3A_tweak_unconsciousPossessAction", 0],
		["A3A_tweak_unconsciousWithstandAction", 0]
	];
	private _overrideTime = missionNamespace getVariable ["A3A_tweak_aiControlTimeOverride", 120];
	private _globalTime = if (_overrideTime == -1) then { 999999 } else { _overrideTime };
	missionNamespace setVariable ["aiControlTime", _globalTime, true];

		// AI Spawn Distance Override
		private _minSpawnDist = missionNamespace getVariable ["A3A_tweak_minSpawnDistance", 0];
		if (_minSpawnDist > 0) then {
			distanceSPWN = _minSpawnDist;
			publicVariable "distanceSPWN";
			diag_log format ["[A3A Ultimate Tweaks Extender] Override AI Spawn Distance (distanceSPWN) set to %1m", _minSpawnDist];

			// Delayed re-enforcement after Antistasi core finishes mission init
			[] spawn {
				sleep 5;
				private _dist = missionNamespace getVariable ["A3A_tweak_minSpawnDistance", 0];
				if (_dist > 0) then {
					distanceSPWN = _dist;
					publicVariable "distanceSPWN";
					diag_log format ["[A3A Ultimate Tweaks Extender] Delayed enforcement: AI Spawn Distance (distanceSPWN) locked to %1m", _dist];
				};
			};
		};
	};

	A3A_tweak_fnc_revealMarker = {
		params ["_marker", ["_zone", ""]];
		if (!isServer || { _marker == "" }) exitWith {};

		if (isNil "A3A_tweak_discoveredMarkers") then {
			A3A_tweak_discoveredMarkers = [];
		};
		A3A_tweak_discoveredMarkers pushBackUnique _marker;
		if (_zone != "") then {
			A3A_tweak_discoveredMarkers pushBackUnique ("Dum" + _zone);
		};
		publicVariable "A3A_tweak_discoveredMarkers";

		if (_zone != "") then {
			if (isNil "revealedZones") then { revealedZones = [] };
			revealedZones pushBackUnique _zone;
			publicVariable "revealedZones";
			("Dum" + _zone) setMarkerAlpha 1;
		};
		_marker setMarkerAlpha 1;
	};

	// Client-side loop to enforce fog of war and reveal enemy zones when approached.
	if (hasInterface) then {
		[] spawn {
			scriptName "A3A_Ultimate_Tweaks_MarkerRevealLoop";
			waitUntil {
				sleep 0.5;
				!isNil "A3A_startupState" && {
					A3A_startupState == "completed"
				} && {
					!isNil "markersX"
				} && {
					!isNil "hideEnemyMarkers"
				} && {
					!isNil "sidesX"
				}
			};
			if !(hideEnemyMarkers isEqualTo 1 || { hideEnemyMarkers isEqualTo true }) exitWith {};
			// A3A_startupState is published before Ultimate's final marker pass completes.
			sleep 1;

			// Queue system variables
			A3A_tweak_discoveryQueue = [];
			A3A_tweak_discoveryRunning = false;
			private _revealedMarkers = (missionNamespace getVariable ["revealedZones", []]) apply { "Dum" + _x };
			_revealedMarkers append (missionNamespace getVariable ["revealedZones", []]);
			_revealedMarkers append (missionNamespace getVariable ["A3A_tweak_discoveredMarkers", []]);

			private _fnc_getLocationDisplayName = {
				params ["_visualMarker", "_zone", "_markerPos"];
				private _cities = missionNamespace getVariable ["citiesX", []];
				private _nearCity = if (_cities isNotEqualTo []) then {
					[_cities, _markerPos] call BIS_fnc_nearestPosition
				} else { "" };

				private _name = "";

				if (_zone != "") then {
					_name = [_zone] call A3A_fnc_localizar;
					if (_name isEqualTo "") then {
						private _type = call {
							if (_zone in (missionNamespace getVariable ["airportsX", []])) exitWith { "AIRBASE" };
							if (_zone in (missionNamespace getVariable ["milbases", []])) exitWith { "MILITARY BASE" };
							if (_zone in (missionNamespace getVariable ["outposts", []])) exitWith { "OUTPOST" };
							if (_zone in (missionNamespace getVariable ["resourcesX", []])) exitWith { "RESOURCE" };
							if (_zone in (missionNamespace getVariable ["factories", []])) exitWith { "FACTORY" };
							if (_zone in (missionNamespace getVariable ["seaports", []])) exitWith { "SEAPORT" };
							if (_zone in (missionNamespace getVariable ["controlsX", []])) exitWith { "ROADBLOCK" };
							if (_zone in (missionNamespace getVariable ["milAdministrationsX", []])) exitWith { "MILITARY ADMINISTRATION" };
							"BASE"
						};
						_name = if (_nearCity != "") then { format ["%1: %2", _type, _nearCity] } else { _type };
					};
				} else {
					if ((_visualMarker find "Ant") == 0 && {_visualMarker in allMapMarkers && {markerType _visualMarker == "loc_Fuelstation"}}) then {
						_name = if (_nearCity != "") then { format ["GAS STATION: %1", _nearCity] } else { "GAS STATION" };
					} else {
						if ((_visualMarker find "antenna") != -1 || {markerType _visualMarker == "loc_Transmitter"}) then {
							_name = if (_nearCity != "") then { format ["RADIO TOWER: %1", _nearCity] } else { "RADIO TOWER" };
						} else {
							private _mText = markerText _visualMarker;
							if (_mText != "") then {
								_name = if (_nearCity != "") then { format ["%1: %2", _mText, _nearCity] } else { _mText };
							} else {
								_name = if (_nearCity != "") then { format ["LOCATION: %1", _nearCity] } else { "UNKNOWN LOCATION" };
							};
						};
					};
				};

				toUpper _name
			};

			private _fnc_getDiscoveryTargets = {
				private _targets = [];
				private _cities = missionNamespace getVariable ["citiesX", []];

				{
					private _zone = _x;
					private _visualMarker = if (("Dum" + _zone) in allMapMarkers) then { "Dum" + _zone } else { _zone };
					if !(_visualMarker in allMapMarkers) then { continue };

					private _markerSide = sidesX getVariable [_zone, sideUnknown];
					if (_markerSide isEqualTo teamPlayer || { _zone in _cities }) then {
						_visualMarker setMarkerAlphaLocal 1;
					} else {
						private _size = markerSize _zone;
						private _radius = (_size select 0) max (_size select 1);
						private _pos = getMarkerPos _zone;
						if (_pos isEqualTo [0, 0, 0]) then { _pos = getMarkerPos _visualMarker; };
						_targets pushBack [_visualMarker, _zone, _pos, _radius];
					};
				} forEach (missionNamespace getVariable ["markersX", []]);

				{
					if (_x in allMapMarkers) then {
						_targets pushBack [_x, "", getMarkerPos _x, 0];
					};
				} forEach (missionNamespace getVariable ["mrkAntennas", []]);

				{
					private _fuelMarker = format ["Ant%1", mapGridPosition _x];
					if (_fuelMarker in allMapMarkers) then {
						_targets pushBackUnique [_fuelMarker, "", getMarkerPos _fuelMarker, 0];
					};
				} forEach (missionNamespace getVariable ["A3A_fuelStations", []]);

				{
					private _markerSide = sidesX getVariable [_x, sideUnknown];
					if (_markerSide isEqualTo teamPlayer) then {
						_x setMarkerAlphaLocal 1;
					} else {
						_targets pushBack [_x, "", getMarkerPos _x, 0];
					};
				} forEach (missionNamespace getVariable ["milAdministrationsX", []]);

				_targets
			};

			private _hiddenCount = 0;

			{
				_x params ["_visualMarker"];
				if !(_visualMarker in _revealedMarkers) then {
					_visualMarker setMarkerAlphaLocal 0;
					_hiddenCount = _hiddenCount + 1;
				};
			} forEach (call _fnc_getDiscoveryTargets);
			diag_log format ["[A3A Ultimate Tweaks Extender] Fog of War initialized after campaign load. Hidden %1 map markers; retained %2 discoveries.", _hiddenCount, count _revealedMarkers];

			private _fnc_processQueue = {
				if (A3A_tweak_discoveryRunning) exitWith {};
				A3A_tweak_discoveryRunning = true;
				[] spawn {
					while { count A3A_tweak_discoveryQueue > 0 } do {
						private _placeName = A3A_tweak_discoveryQueue deleteAt 0;
						if (_placeName != "") then {
							private _msg = format [
								"<t size='1.3' color='#84B062' font='PuristaBold' align='center'>LOCATION DISCOVERED</t><br/><t size='1.7' color='#E3DCBE' font='PuristaMedium' align='center'>%1</t>",
								_placeName
							];
							// Display text at center-top of screen (y = -0.30), duration 4s, fade-in/out 0.2s
							[_msg, -1, -0.30, 4, 0.2, 0, 9700] spawn BIS_fnc_dynamicText;
							sleep 4.45; // 0.2s fade-in + 4s duration + 0.2s fade-out + 0.05s buffer
						};
					};
					A3A_tweak_discoveryRunning = false;
				};
			};

			while { true } do {
				sleep 3;
				// Marker hiding remains active even when automatic proximity reveals are disabled.
				private _enabled = missionNamespace getVariable ["A3A_tweak_discoveryReveal", 1];

				if (!alive player) then {
					continue
				};
				private _playerPos = getPos player;
				private _revealDist = missionNamespace getVariable ["A3A_tweak_discoveryDistance", 200];

				_revealedMarkers append ((missionNamespace getVariable ["revealedZones", []]) apply { "Dum" + _x });
				_revealedMarkers append (missionNamespace getVariable ["revealedZones", []]);
				_revealedMarkers append (missionNamespace getVariable ["A3A_tweak_discoveredMarkers", []]);

				{
					_x params ["_visualMarker", "_zone", "_markerPos", ["_radius", 0]];
					if (_visualMarker in _revealedMarkers || { _zone != "" && { _zone in (missionNamespace getVariable ["revealedZones", []]) } }) then {
						_visualMarker setMarkerAlphaLocal 1;
						continue
					};

					_visualMarker setMarkerAlphaLocal 0;

					private _inZone = if (_zone != "" && {_zone in allMapMarkers}) then { _playerPos inArea _zone } else { false };
					private _nearZone = (_playerPos distance2D _markerPos) < (_revealDist + _radius);

					if (_enabled isNotEqualTo 0 && { _inZone || _nearZone }) then {
						_visualMarker setMarkerAlphaLocal 1;
						_revealedMarkers pushBackUnique _visualMarker;
						if (_zone != "") then {
							_revealedMarkers pushBackUnique _zone;
							_revealedMarkers pushBackUnique ("Dum" + _zone);
						};
						[_visualMarker, _zone] remoteExecCall ["A3A_tweak_fnc_revealMarker", 2];

						// Update map marker text on gas stations with nearest town name for quick map reference
						if ((_visualMarker find "Ant") == 0 && {_visualMarker in allMapMarkers && {markerType _visualMarker == "loc_Fuelstation"}}) then {
							private _cities = missionNamespace getVariable ["citiesX", []];
							private _nearCity = if (_cities isNotEqualTo []) then { [_cities, _markerPos] call BIS_fnc_nearestPosition } else { "" };
							if (_nearCity != "") then {
								_visualMarker setMarkerTextLocal (format ["%1 (%2)", localize "STR_fuelstation", _nearCity]);
							};
						};

						private _locName = [_visualMarker, _zone, _markerPos] call _fnc_getLocationDisplayName;
						if (_locName != "") then {
							A3A_tweak_discoveryQueue pushBack _locName;
							[] call _fnc_processQueue;
						};
					};
				} forEach (call _fnc_getDiscoveryTargets);
			};
		};
	};

	// Overrides applied
	diag_log "[A3A Ultimate Tweaks Extender] Overrides applied.";

