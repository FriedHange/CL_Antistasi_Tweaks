/*
	    fn_planning_execute.sqf
	    Handles the execution phase of the Siege Planning Rework with simulated travel delay.
	    Runs on the server. Validates deployment squads against active mod configs, deducts resource
	    costs for valid squads only, calculates travel times, and triggers spawning/support loops.
*/

disableSerialization;
params [
	["_mode", "", [""]],
	["_params", [], [[]]]
];

if (_mode in ["DEPLOY", "REINFORCE"]) then {
	if (_mode == "DEPLOY" && { call A3A_fnc_planning_isSiegeActive }) exitWith {
		diag_log format ["[A3A Planning Warning] DEPLOY request ignored: siege operation already active for target '%1'.", A3A_planning_objective];
	};

	_params params [
		["_totalMoney", 0, [0]],
		["_totalHR", 0, [0]],
		["_clientOwnerID", 0, [0]],
		["_addHC", true, [true]],
		["_queue", [], [[]]],
		["_autoCapture", true, [true]],
		["_entryPositions", [], [[]]],
		["_objective", "", [""]]
	];

	private _hqPos = getMarkerPos "respawn_west";
	if (_hqPos isEqualTo [0, 0, 0]) then {
		_hqPos = getMarkerPos "respawn_civilian";
	};
	if (_hqPos isEqualTo [0, 0, 0]) then {
		_hqPos = getPos petros;
	};

	A3A_planning_objective = _objective;
	publicVariable "A3A_planning_objective";

	A3A_planning_autoCapture = _autoCapture;
	publicVariable "A3A_planning_autoCapture";

	// Preserve active groups from ongoing sieges while cleaning up dead/null ones
	if (isNil "A3A_planning_activeGroups") then {
		A3A_planning_activeGroups = [];
	} else {
		A3A_planning_activeGroups = A3A_planning_activeGroups select { !isNull _x && { { alive _x } count (units _x) > 0 } };
	};
	publicVariable "A3A_planning_activeGroups";
	A3A_planning_captureTriggered = false;
	publicVariable "A3A_planning_captureTriggered";
	diag_log "[A3A DEBUG] Stage 0: init vars OK";

	    // --- DEFENSIVE VALIDATION & FALLBACK SYSTEM ---
	private _fallbackQueue = [];
	private _failedSquads = [];

	{
		_x params ["_unitTypes", "_idFormat", "_special", "_costMoney", "_costHR", "_vehType", "_displayName", "_entryName"];

		private _squadFailed = false;
		        // Faction-agnostic: don't pre-validate unit identifiers against CfgVehicles here.
		        // Entries may be plain classnames or faction-specific loadout identifiers (e.g. custom
		        // loadout systems used by non-vanilla factions like Syndikat) - A3A_fnc_spawnGroup
		        // already knows how to resolve whatever format the active faction uses, so we trust it
		        // as the primary spawn path. Raw classnames are only strictly required by the manual
		        // createUnit fallback further down, and THAT is where we validate/substitute if needed.
		private _validatedUnits = +_unitTypes;

		        // 2. Validate and replace vehicle type (if specified)
		private _validatedVeh = _vehType;
		if (_vehType != "") then {
			if (!isClass (configFile >> "CfgVehicles" >> _vehType)) then {
				diag_log format ["[A3A Ultimate Tweaks Extender] Spawning vehicle class '%1' is invalid.", _vehType];
				_squadFailed = true;

				if (_special == "VehicleSquad") then {
					_validatedVeh = "I_G_Offroad_01_AT_F"; // Vanilla light AT vehicle
					diag_log "[A3A Ultimate Tweaks Extender] Falling back AT Car vehicle to 'I_G_Offroad_01_AT_F'.";
				} else {
					if (_special == "BuildAA") then {
						_validatedVeh = "I_G_Van_01_transport_F"; // Vanilla Truck
						diag_log "[A3A Ultimate Tweaks Extender] Falling back AA Truck vehicle to 'I_G_Van_01_transport_F'.";
					} else {
						_validatedVeh = "I_G_Offroad_01_armed_F"; // default armed MRAP/car
						diag_log "[A3A Ultimate Tweaks Extender] Falling back custom vehicle to 'I_G_Offroad_01_armed_F'.";
					};
				};
			};
		};

		        // 3. log HMG/Mortar static configuration issues (actual assembly fallbacks are resolved dynamically in supportAI)
		if (_special in ["MG", "MG_FALLBACK"]) then {
			private _staticMG = (A3A_faction_reb getOrDefault ["staticMGs", [""]]) # 0;
			if (isNil "_staticMG" || {
				_staticMG == "" || {
					!isClass (configFile >> "CfgVehicles" >> _staticMG)
				}
			}) then {
				diag_log "[A3A Ultimate Tweaks Extender] faction staticMGs config is invalid;
				fallback HMG will be assembled.";
				_squadFailed = true;
			};
		};
		if (_special in ["Mortar", "Mortar_FALLBACK"]) then {
			private _staticMortar = (A3A_faction_reb getOrDefault ["staticMortars", [""]]) # 0;
			if (isNil "_staticMortar" || {
				_staticMortar == "" || {
					!isClass (configFile >> "CfgVehicles" >> _staticMortar)
				}
			}) then {
				diag_log "[A3A Ultimate Tweaks Extender] faction staticMortars config is invalid;
				fallback Mortar will be assembled.";
				_squadFailed = true;
			};
		};

		if (_squadFailed) then {
			_failedSquads pushBack _displayName;
		};

		_fallbackQueue pushBack [_validatedUnits, _idFormat, _special, _costMoney, _costHR, _validatedVeh, _displayName, _entryName];
	} forEach _queue;
	diag_log format ["[A3A DEBUG] Stage 1: fallback validation OK, fallbackQueue count=%1", count _fallbackQueue];

	    // log fallback conversions to RPT only (no UI warning)
	if (count _failedSquads > 0) then {
		private _failedNames = "";
		{
			if (_forEachIndex > 0) then {
				_failedNames = _failedNames + ", ";
			};
			_failedNames = _failedNames + _x;
		} forEach _failedSquads;
		diag_log format ["[A3A Planning Warning] Custom assets missing/invalid for squads: %1. Spawning vanilla fallbacks.", _failedNames];
	};

	private _allocatedPositions = createHashMap;
	private _idCounters = createHashMap;
	private _validatedQueue = [];

	{
		_x params ["_unitTypes", "_idFormat", "_special", "_costMoney", "_costHR", "_vehType", "_displayName", "_entryName"];

		private _entryPos = [0, 0, 0];
		{
			_x params ["_name", "_pos"];
			if (_name == _entryName) exitWith {
				_entryPos = _pos;
			};
		} forEach _entryPositions;

		if (_entryPos isEqualTo [0, 0, 0]) then {
			private _markerName = "A3A_planning_entry_" + _entryName;
			_entryPos = getMarkerPos _markerName;
		};
		if (_entryPos isEqualTo [0, 0, 0]) then {
			_entryPos = _hqPos;
		};

		        // Retrieve already allocated positions for this entry point
		private _alreadyAllocated = _allocatedPositions getOrDefault [_entryName, []];

		private _spawnPos = [];
		private _minDist = if (_vehType != "") then {
			30
		} else {
			20
		};
		private _searchRadius = 15;
		private _found = false;

		        // Attempt to find a safe position that doesn't overlap
		for "_attempts" from 1 to 10 do {
			private _cand = [_entryPos, 0, _searchRadius, 4, 0, 0.7, 0] call BIS_fnc_findSafePos;
			if (count _cand == 2) then {
				_cand pushBack 0;
			};

			if (count _cand == 3) then {
				// Check distance against all already allocated positions
				private _tooClose = false;
				{
					if (_cand distance2D _x < _minDist) exitWith {
						_tooClose = true;
					};
				} forEach _alreadyAllocated;

				if (!_tooClose) exitWith {
					_spawnPos = _cand;
					_found = true;
				};
			};
			            _searchRadius = _searchRadius + 15; // Expand search area
		};

		        // Fallback if no safe position found
		if (!_found) then {
			_spawnPos = [_entryPos, 5, 60, 2, 0, 0.7, 0] call BIS_fnc_findSafePos;
			if (count _spawnPos == 2) then {
				_spawnPos pushBack 0;
			};
			if (count _spawnPos < 3) then {
				_spawnPos = _entryPos;
			};
		};

		        // Record the allocated position
		_alreadyAllocated pushBack _spawnPos;
		_allocatedPositions set [_entryName, _alreadyAllocated];

		        // Build a unique, complete group name (e.g. "Squd-1", "Mortar-2")
		private _counter = (_idCounters getOrDefault [_idFormat, 0]) + 1;
		_idCounters set [_idFormat, _counter];
		private _groupName = _idFormat + str _counter;

		        // Push squad with its pre-allocated spawn position to the deployment queue
		_validatedQueue pushBack [_unitTypes, _groupName, _special, _costMoney, _costHR, _vehType, _displayName, _entryName, _spawnPos];
	} forEach _fallbackQueue;
	diag_log format ["[A3A DEBUG] Stage 2: position allocation OK, validatedQueue count=%1", count _validatedQueue];

	    // Calculate total cost (using the validated queue)
	private _deductMoney = 0;
	private _deductHR = 0;
	{
		_deductMoney = _deductMoney + (_x select 3);
		_deductHR = _deductHR + (_x select 4);
	} forEach _validatedQueue;

	    // Deduct resources
	[-_deductHR, -_deductMoney] call A3A_fnc_resourcesFIA;
	diag_log "[A3A DEBUG] Stage 3: resource deduction OK";

	    // Deduct selected garage vehicles from the HQ garage
	private _garageVehiclesToDeduct = [];
	{
		_x params ["_type", "_id", "_special", "_costMoney", "_costHR", "_veh", "_name", "_entry"];
		if (_special == "GarageCrew" && {
			_veh != ""
		}) then {
			_garageVehiclesToDeduct pushBack _veh;
		};
	} forEach _validatedQueue;

	if (count _garageVehiclesToDeduct > 0) then {
		[_garageVehiclesToDeduct] call A3A_fnc_planning_serverDeductGarage;
	};
	diag_log "[A3A DEBUG] Stage 4: garage deduction OK";

	private _spawnSquadDirect = {
		params ["_unitTypes", "_idFormat", "_special", "_vehType", "_spawnPos", "_targetPos", "_addHC", "_clientOwnerID"];
		diag_log format ["[A3A DEBUG] spawnSquadDirect invoked for %1", _idFormat];

		        // Declared locally so it's always in scope no matter which call stack
		        // _spawnSquadDirect ends up executing on (spawn does not inherit private
		        // variables from the scope it was written in, only from explicit params).
		private _fnc_ensureThreadStarted = {
			params ["_startCode", "_label"];
			private _attempt = 0;
			private _maxAttempts = 3;
			private _started = false;
			while {
				!_started && {
					_attempt < _maxAttempts
				}
			} do {
				_attempt = _attempt + 1;
				private _handle = call _startCode;
				sleep 0.3;
				if (!isNull _handle && {
					!scriptDone _handle
				}) then {
					_started = true;
				} else {
					diag_log format ["[A3A Planning Warning] Support AI thread '%1' failed to start (attempt %2/%3). Retrying...", _label, _attempt, _maxAttempts];
				};
			};
			if (!_started) then {
				diag_log format ["[A3A Planning Error] Support AI thread '%1' failed to start after %2 attempts. Group left on its HOLD waypoint (will not assault).", _label, _maxAttempts];
			};
			_started
		};

		private _group = grpNull;
		private _vehicle = objNull;

		// --- STAGE 1: Vehicle creation for non-GarageCrew squads.
		// GarageCrew manages its own vehicle lifecycle in the block below.
		if (_special != "GarageCrew" && { _vehType != "" } && {
			isClass (configFile >> "CfgVehicles" >> _vehType)
		}) then {
			diag_log format ["[A3A Planning] Spawning vehicle %1 at %2...", _vehType, _spawnPos];
			_vehicle = createVehicle [_vehType, _spawnPos, [], 10, "NONE"];
			if (!isNull _vehicle) then {
				[_vehicle, teamPlayer] call A3A_fnc_AIVEHinit;
			} else {
				diag_log format ["[A3A Planning Error] Failed to create vehicle %1 at %2.", _vehType, _spawnPos];
			};
		};



		// GarageCrew: crew is generated from the vehicle itself via createVehicleCrew.
		// _unitTypes is [] so spawnGroup would produce an empty group; create one manually.
		if (_special == "GarageCrew") then {
			// Determine whether this is an air asset so Stage 1 can pick the right spawn location.
			private _isHeliCrew = (_vehType != "" && { _vehType isKindOf "Helicopter" });
			private _isPlaneCrew = (_vehType != "" && { _vehType isKindOf "Plane" });
			private _isAirCrew = _isHeliCrew || _isPlaneCrew;

			// --- Pick the vehicle's actual spawn position (separate from the staging-point _spawnPos) ---
			private _vehicleSpawnPos = _spawnPos; // default: staging point (ground vehicles)

			if (_isAirCrew) then {
				private _infra = call A3A_fnc_planning_getFriendlyInfrastructure;
				_infra params ["_hasHelipad", "_hasAirfield", "_friendlyHelipads", "_friendlyAirfields"];

				if (_isHeliCrew) then {
					// Nearest friendly helipad/military base/outpost location, spawned airborne
					private _bestMarker = if (count _friendlyHelipads > 0) then { _friendlyHelipads select 0 } else { "respawn_west" };
					private _bestDist = 1e9;
					{
						private _mPos = getMarkerPos _x;
						if (_mPos isNotEqualTo [0,0,0]) then {
							private _d = _mPos distance2D _targetPos;
							if (_d < _bestDist) then { _bestDist = _d; _bestMarker = _x; };
						};
					} forEach _friendlyHelipads;
					private _basePos = getMarkerPos _bestMarker;
					if (_basePos isEqualTo [0,0,0]) then { _basePos = getMarkerPos "respawn_west"; };
					_vehicleSpawnPos = _basePos vectorAdd [random 30 - 15, random 30 - 15, 200];
				};
				if (_isPlaneCrew) then {
					// Nearest friendly airfield, spawned airborne
					private _bestMarker = if (count _friendlyAirfields > 0) then { _friendlyAirfields select 0 } else { "" };
					private _bestDist = 1e9;
					{
						private _mPos = getMarkerPos _x;
						if (_mPos isNotEqualTo [0,0,0]) then {
							private _d = _mPos distance2D _targetPos;
							if (_d < _bestDist) then { _bestDist = _d; _bestMarker = _x; };
						};
					} forEach _friendlyAirfields;
					private _basePos = if (_bestMarker != "") then { getMarkerPos _bestMarker } else { _spawnPos };
					if (_basePos isEqualTo [0,0,0]) then { _basePos = _spawnPos; };
					_vehicleSpawnPos = _basePos vectorAdd [random 30 - 15, random 30 - 15, 250];
				};
			};

			// --- Spawn the vehicle ---
			try {
				if (_vehType != "" && { isClass (configFile >> "CfgVehicles" >> _vehType) }) then {
					diag_log format ["[A3A Planning] GarageCrew: spawning vehicle %1 at %2...", _vehType, _vehicleSpawnPos];
					if (_isAirCrew) then {
						_vehicle = createVehicle [_vehType, _vehicleSpawnPos, [], 0, "FLY"];
						private _dir = _vehicleSpawnPos getDir _targetPos;
						_vehicle setDir _dir;
						private _speed = if (_isPlaneCrew) then { 120 } else { 45 };
						_vehicle setVelocity [sin(_dir) * _speed, cos(_dir) * _speed, 0];
						private _flyHeight = if (_isPlaneCrew) then { 250 } else { 200 };
						_vehicle flyInHeight _flyHeight;
					} else {
						_vehicle = createVehicle [_vehType, _vehicleSpawnPos, [], 10, "NONE"];
					};
					if (!isNull _vehicle) then {
						[_vehicle, teamPlayer] call A3A_fnc_AIVEHinit;
					} else {
						diag_log format ["[A3A Planning Error] GarageCrew: failed to create vehicle %1.", _vehType];
					};
				};
			} catch {
				diag_log format ["[A3A Planning Exception] GarageCrew vehicle creation failed: %1", _exception];
			};

			// --- Create friendly rebel crew for vehicle (filling all combat seats) ---
			try {
				if (!isNull _vehicle) then {
					_group = createGroup teamPlayer;

					// Resolve friendly rebel crew class
					private _crewUnitType = missionNamespace getVariable ["staticCrewReb", ""];
					if (_crewUnitType == "" || { !isClass (configFile >> "CfgVehicles" >> _crewUnitType) }) then {
						if (!isNil "A3A_faction_reb" && { A3A_faction_reb isEqualType createHashMap }) then {
							_crewUnitType = if (_isAirCrew) then {
								A3A_faction_reb getOrDefault ["unitPilot", A3A_faction_reb getOrDefault ["unitCrew", ""]]
							} else {
								A3A_faction_reb getOrDefault ["unitCrew", ""]
							};
						};
					};
					if (_crewUnitType == "" || { !isClass (configFile >> "CfgVehicles" >> _crewUnitType) }) then {
						_crewUnitType = missionNamespace getVariable ["SDKMil", "I_G_Soldier_F"];
					};
					if (_crewUnitType == "" || { !isClass (configFile >> "CfgVehicles" >> _crewUnitType) }) then {
						_crewUnitType = "I_G_Soldier_F";
					};

					// Identify all empty non-cargo combat seats (driver, gunner, commander, turret)
					private _allSeats = fullCrew [_vehicle, "", true];
					private _crewSeats = _allSeats select {
						(_x select 0 isEqualTo objNull) && {
							(_x select 1) in ["driver", "gunner", "commander", "turret"]
						} && {
							!(_x select 4) // ignore personTurret (cargo FFV seats)
						}
					};

					// Fallback if fullCrew finds no empty combat seats but vehicle is uncrewed
					if (count _crewSeats == 0 && { count (crew _vehicle) == 0 }) then {
						_crewSeats = [[objNull, "driver", -1, [], false]];
					};

					{
						_x params ["_seatUnit", "_role", "_cargoIndex", "_turretPath", "_personTurret"];
						private _unit = objNull;
						if (!isNil "A3A_fnc_createUnit") then {
							_unit = [_group, _crewUnitType, _vehicleSpawnPos, [], 5] call A3A_fnc_createUnit;
						} else {
							_unit = _group createUnit [_crewUnitType, _vehicleSpawnPos, [], 5, "NONE"];
						};
						if (!isNull _unit) then {
							_unit setVariable ["unitType", _crewUnitType, true];
							// Assign seat IMMEDIATELY so unit is in vehicle before any init script runs
							switch (_role) do {
								case "driver": { _unit moveInDriver _vehicle; };
								case "gunner": { _unit moveInGunner _vehicle; };
								case "commander": { _unit moveInCommander _vehicle; };
								case "turret": { _unit moveInTurret [_vehicle, _turretPath]; };
								default { _unit moveInAny _vehicle; };
							};
							try {
								if (!isNil "A3A_fnc_FIAinit") then {
									[_unit, false, _crewUnitType] call A3A_fnc_FIAinit;
								};
							} catch {
								diag_log format ["[A3A Planning Exception] FIAinit failed for crew unit %1: %2", _unit, _exception];
							};
						};
					} forEach _crewSeats;

					private _crewMembers = crew _vehicle;
					_group setGroupIdGlobal [_idFormat + "1"];
					diag_log format ["[A3A Planning] GarageCrew %1: vehicle %2 crewed by %3 friendly units (%4).", _idFormat, typeOf _vehicle, count _crewMembers, _crewUnitType];
				} else {
					_group = createGroup teamPlayer; // Empty group as placeholder so Stage 2 can proceed
					diag_log format ["[A3A Planning Error] GarageCrew %1: no vehicle — creating empty group as placeholder.", _idFormat];
				};
			} catch {
				diag_log format ["[A3A Planning Exception] GarageCrew crew creation failed: %1", _exception];
				if (isNull _group) then { _group = createGroup teamPlayer; };
			};

			// Store air-asset flags on the group for Stage 2/4 access
			_group setVariable ["siege_isAirCrew", _isAirCrew, true];
			_group setVariable ["siege_isHeli", _isHeliCrew, true];
			_group setVariable ["siege_isPlane", _isPlaneCrew, true];
		} else {
			// --- All non-GarageCrew squad types: normal infantry spawn ---
			diag_log format ["[A3A Planning] Spawning squad group %1 units: %2...", _idFormat, _unitTypes];
			_group = [_spawnPos, teamPlayer, _unitTypes, true] call A3A_fnc_spawnGroup;
			if (isNull _group) then {
				diag_log "[A3A Planning Warning] A3A_fnc_spawnGroup returned groupNull. Attempting manual group creation...";
				_group = createGroup teamPlayer;
				if (!isNull _group) then {
					{
						private _spawnUnitType = _x;
						if (isNil "_spawnUnitType" || {
							_spawnUnitType == "" || {
								!isClass (configFile >> "CfgVehicles" >> _spawnUnitType)
							}
						}) then {
							diag_log format ["[A3A Planning Warning] Manual fallback: unit identifier '%1' isn't a raw createUnit-compatible classname. Falling back to 'I_G_Soldier_F'.", _spawnUnitType];
							_spawnUnitType = "I_G_Soldier_F";
						};
						private _unit = objNull;
						if (!isNil "A3A_fnc_createUnit") then {
							_unit = [_group, _spawnUnitType, _spawnPos, [], 10] call A3A_fnc_createUnit;
						} else {
							_unit = _group createUnit [_spawnUnitType, _spawnPos, [], 10, "NONE"];
						};
						if (!isNull _unit) then {
							_unit setVariable ["unitType", _spawnUnitType, true];
							try {
								if (!isNil "A3A_fnc_FIAinit") then {
									[_unit, false, _spawnUnitType] call A3A_fnc_FIAinit;
								};
							} catch {
								diag_log format ["[A3A Planning Exception] FIAinit failed for unit %1: %2", _unit, _exception];
							};
						} else {
							diag_log format ["[A3A Planning Error] Manual createUnit failed for unit class %1.", _spawnUnitType];
						};
					} forEach _unitTypes;
				};
			};

			if (!isNull _group) then {
				private _timeout = time + 10;
				while { ({ alive _x } count (units _group) < count _unitTypes) && { time < _timeout } } do {
					sleep 0.2;
				};
				_group setGroupIdGlobal [_idFormat];
				{
					try {
						if (!isNil "A3A_fnc_FIAinit") then {
							[_x, false, typeOf _x] call A3A_fnc_FIAinit;
						};
					} catch {};
				} forEach (units _group);
			};
		};

		if (isNull _group) exitWith {
			diag_log "[A3A Planning Error] Group creation failed entirely.";
			grpNull
		};


		        // --- STAGE 2: Classify and lock in waypoint/behavior FIRST, before any risky
		        // crew-assignment code runs. This is the only place a support role is decided,
		        // and it happens unconditionally as soon as the group exists.
		private _isAirCrewGroup = (_special == "GarageCrew") && { _group getVariable ["siege_isAirCrew", false] };
		private _roleTag = switch (true) do {
			case (_isAirCrewGroup): { "AIR_CREW" };
			case (_special in ["MG", "MG_FALLBACK"]): { "MG" };
			case (_special in ["Mortar", "Mortar_FALLBACK"]): { "MORTAR" };
			case (_special in ["VehicleSquad", "BuildAA"] || { _special == "GarageCrew" && !_isAirCrewGroup }): { "VEHICLE" };
			default { "ASSAULT" };
		};
		_group setVariable ["siege_role", _roleTag, true];
		_group setVariable ["siege_spawnPos", _spawnPos, true];

		// Only static MG/Mortar teams hold at spawn; ground vehicles and assault infantry advance towards target
		private _isStaticSupport = _special in ["MG", "Mortar", "MG_FALLBACK", "Mortar_FALLBACK"];

		if (_roleTag == "AIR_CREW") then {
			// Air assets go to combat immediately — airOverwatch will manage orbit/recovery
			private _wp = _group addWaypoint [_targetPos, 0];
			_wp setWaypointType "SAD";
			_wp setWaypointBehaviour "COMBAT";
			_wp setWaypointCombatMode "RED";
			_wp setWaypointSpeed "FULL";
			_group setBehaviour "COMBAT";
			_group setCombatMode "RED";
			_group setSpeedMode "FULL";
			if (!isNull _vehicle) then {
				private _flyHeight = if (_group getVariable ["siege_isPlane", false]) then { 200 } else { 80 };
				_vehicle flyInHeight _flyHeight;
			};
		} else {
			if (_isStaticSupport) then {
				private _wp = _group addWaypoint [_spawnPos, 0];
				_wp setWaypointType "HOLD";
				_group setBehaviour "AWARE";
				_group setCombatMode "YELLOW";
				_group setSpeedMode "NORMAL";
			} else {
				// All combat ground vehicles (GarageCrew, VehicleSquad, BuildAA) & infantry advance with SAD waypoints
				private _wp = _group addWaypoint [_targetPos, 0];
				_wp setWaypointType "SAD";
				_wp setWaypointBehaviour "COMBAT";
				_wp setWaypointCombatMode "RED";
				_wp setWaypointSpeed "FULL";
				_group setBehaviour "COMBAT";
				_group setCombatMode "RED";
				_group setSpeedMode "FULL";
			};
		};

		        // --- STAGE 3: crew assignment / vehicle mounting. Isolated in its own
		        // try/catch so a failure here (moveInDriver/moveInGunner/fullCrew races, 
		        // bad indexing, etc.) can NEVER roll back or skip the waypoint/behavior
		        // already committed in Stage 2 above. ---
		try {
			// MG and Mortar weapon bag override system (only for fallback squads)
			if (_special in ["MG_FALLBACK", "Mortar_FALLBACK"]) then {
				[_group, _special] spawn {
					params ["_group", "_special"];
					private _units = [];
					private _tries = 0;
					while { _tries < 10 } do {
						if (isNull _group) exitWith {};
						_units = (units _group) select {
							alive _x
						};
						if (count _units >= 2) exitWith {};
						sleep 0.5;
						_tries = _tries + 1;
					};
					if (isNull _group) exitWith {};
					if (count _units < 2) exitWith {
						diag_log format ["[A3A Planning Error] %1 squad %2 never reached 2 alive units for weapon-bag assignment (found %3 after retries). Squad failed to spawn correctly.", _special, groupId _group, count _units];
					};

					private _sidePrefix = if (teamPlayer == west) then {
						"B"
					} else {
						if (teamPlayer == east) then {
							"O"
						} else {
							"I"
						}
					};

					private _mgWeaponBag = _sidePrefix + "_HMG_01_weapon_F";
					private _mgSupportBag = _sidePrefix + "_HMG_01_support_F";
					if (!isClass (configFile >> "CfgVehicles" >> _mgWeaponBag)) then {
						_mgWeaponBag = "I_HMG_01_weapon_F";
						_mgSupportBag = "I_HMG_01_support_F";
					};

					private _mortarWeaponBag = _sidePrefix + "_Mortar_01_weapon_F";
					private _mortarSupportBag = _sidePrefix + "_Mortar_01_support_F";
					if (!isClass (configFile >> "CfgVehicles" >> _mortarWeaponBag)) then {
						_mortarWeaponBag = "I_Mortar_01_weapon_F";
						_mortarSupportBag = "I_Mortar_01_support_F";
					};

					private _unit1 = _units # 0;
					private _unit2 = _units # 1;

					removeBackpackGlobal _unit1;
					removeBackpackGlobal _unit2;

					if (_special == "MG_FALLBACK") then {
						_unit1 addBackpackGlobal _mgWeaponBag;
						_unit2 addBackpackGlobal _mgSupportBag;
					};
					if (_special == "Mortar_FALLBACK") then {
						_unit1 addBackpackGlobal _mortarWeaponBag;
						_unit2 addBackpackGlobal _mortarSupportBag;
					};
					diag_log format ["[A3A Ultimate Tweaks Extender] Equipped group %1 with %2 deployment bags.", groupId _group, _special];
				};
			};

			            // Spread out the units immediately if they are on foot to prevent drone wipes
			if (isNull _vehicle) then {
				{
					if (_forEachIndex > 0) then {
						private _offsetPos = [_spawnPos, 4, 25, 2, 0, 0.7, 0] call BIS_fnc_findSafePos;
						if (count _offsetPos == 2) then {
							_x setPos _offsetPos;
						};
					};
				} forEach (units _group);
				_group setFormation "LINE";
			};

			            // Assign group to player's High Command if requested
			if (_addHC && {
				_clientOwnerID > 0
			} && {
				_roleTag in ["ASSAULT", "CREW"]
			}) then {
				[_group] remoteExec ["A3A_fnc_planning_localAddHC", _clientOwnerID];
			};

			private _countUnits = count (units _group) - 1;

			private _initVeh = {
				if (isNull _vehicle) exitWith {};
				_group addVehicle _vehicle;
				_vehicle setVariable ["owner", _group, true];
				driver _vehicle action ["engineOn", _vehicle];
				{
					if (vehicle _x == _x) then {
						_x moveInAny _vehicle
					}
				} forEach units _group;
			};

			private _initInfVeh = {
				if (isNull _vehicle) exitWith {};
				leader _group moveInDriver _vehicle;
				if (count (units _group) > 1 && {
					fullCrew [_vehicle, "gunner", true] isNotEqualTo []
				}) then {
					(units _group # 1) moveInGunner _vehicle;
				};
				call _initVeh;
			};

			switch _special do {
				case "GarageCrew": {
					// Vehicle was spawned and crewed via createVehicleCrew before Stage 2.
					// Stage 3 just finalises ownership and starts the engine.
					if (!isNull _vehicle) then {
						_vehicle setVariable ["owner", _group, true];
						_vehicle allowCrewInImmobile true;
						private _d = driver _vehicle;
						if (!isNull _d) then { _d action ["engineOn", _vehicle]; };
						_vehicle engineOn true;
						diag_log format ["[A3A Planning] GarageCrew %1: vehicle %2 ready (%3 crew in vehicle).", _idFormat, typeOf _vehicle, count (crew _vehicle)];
					} else {
						diag_log format ["[A3A Planning Error] GarageCrew %1: vehicle is null at Stage 3.", _idFormat];
					};
				};

				case "BuildAA": {
					private _staticList = (attachedObjects _vehicle) select {
						typeOf _x in (A3A_faction_reb get "staticAA")
					};
					if (count _staticList > 0) then {
						private _static = _staticList # 0;
						if (_countUnits >= 1) then {
							(units _group # (_countUnits - 1)) moveInDriver _vehicle;
							(units _group # _countUnits) moveInGunner _static;
						};
					};
					call _initVeh;
					_vehicle allowCrewInImmobile true;
				};
				case "VehicleSquad": {
					if (_countUnits >= 1) then {
						(units _group # (_countUnits - 1)) moveInDriver _vehicle;
						(units _group # _countUnits) moveInGunner _vehicle;
					};
					call _initVeh;
					_vehicle allowCrewInImmobile true;
				};
				default {
					call _initInfVeh;
				};
			};
		} catch {
			diag_log format ["[A3A Planning Exception] Crew assignment failed for squad: %1 (role: %2). Error: %3. Waypoint/behavior already committed in Stage 2, so this squad will still hold/support correctly - it may just be missing its vehicle seat.", _idFormat, _roleTag, _exception];
		};

		// --- STAGE 4: Dispatch the appropriate support-AI thread for this squad. ---
		// MG/Mortar: supportAI thread.
		// Air assets (AIR_CREW): airOverwatch thread (CAS attack runs, orbit, recovery).
		// ALL ground combat vehicles (VehicleSquad, GarageCrew, BuildAA): vehicleOverwatch thread.
		if (_special in ["MG", "Mortar", "MG_FALLBACK", "Mortar_FALLBACK"]) then {
			[
				{ [_group, _special, A3A_planning_objective, _targetPos] spawn A3A_fnc_planning_supportAI },
				_idFormat
			] call _fnc_ensureThreadStarted;
		} else {
			if (_roleTag == "AIR_CREW") then {
				if (!isNull _vehicle) then {
					[
						{ [_group, _vehicle, A3A_planning_objective, _targetPos] spawn A3A_fnc_planning_airOverwatch },
						_idFormat
					] call _fnc_ensureThreadStarted;
				} else {
					diag_log format ["[A3A Planning Error] Air asset %1 has no valid vehicle object.", _idFormat];
				};
			} else {
				if (!isNull _vehicle) then {
					[
						{ [_group, _vehicle, A3A_planning_objective, _targetPos] spawn A3A_fnc_planning_vehicleOverwatch },
						_idFormat
					] call _fnc_ensureThreadStarted;
				};
			};
		};

		_group
	};
	diag_log "[A3A DEBUG] Stage 5: spawnSquadDirect compiled OK";

	private _targetPos = getMarkerPos A3A_planning_objective;
	diag_log format ["[A3A DEBUG] Stage 6: entering dispatch loop, targetPos=%1", _targetPos];

	    // Hardcoded (no longer lobby-tweakable): 8s delay before dispatching the assault.
	private _initDelay = 8;

	[_validatedQueue, _entryPositions, _hqPos, _targetPos, _spawnSquadDirect, _addHC, _clientOwnerID, _initDelay] spawn {
		params ["_validatedQueue", "_entryPositions", "_hqPos", "_targetPos", "_spawnSquadDirect", "_addHC", "_clientOwnerID", "_initDelay"];

		if (_initDelay > 0) then {
			diag_log format ["[A3A Planning] Waiting %1s for the objective's defenses to finish initializing before dispatching the assault...", _initDelay];
			sleep _initDelay;
		};

		        // 2. spawn travel watches for each queued squad (valid squads only)
		{
			_x params ["_unitTypes", "_idFormat", "_special", "_costMoney", "_costHR", "_vehType", "_displayName", "_entryName", "_spawnPos"];

			private _entryPos = [0, 0, 0];
			{
				_x params ["_name", "_pos"];
				if (_name == _entryName) exitWith {
					_entryPos = _pos;
				};
			} forEach _entryPositions;

			if (_entryPos isEqualTo [0, 0, 0]) then {
				private _markerName = "A3A_planning_entry_" + _entryName;
				_entryPos = getMarkerPos _markerName;
			};
			if (_entryPos isEqualTo [0, 0, 0]) then {
				_entryPos = _hqPos;
			};

			            // Calculate travel delay based on road speed ~14 m/s (50 km/h)
			private _distance = round (_hqPos distance2D _entryPos);
			private _travelTime = round (_distance / 14);

			            // apply configurable travel time multiplier
			private _rawTravelMult = missionNamespace getVariable ["A3A_tweak_siegeTravelTimeMultiplier", 100];
			private _travelMult = if (_rawTravelMult > 2) then { _rawTravelMult / 100 } else { _rawTravelMult };
			_travelTime = round (_travelTime * _travelMult);

			if (_travelMult == 0) then {
				_travelTime = 0; // Instant
			} else {
				_travelTime = (_travelTime max 5) min 300; // Bound between 5s and 5 minutes
			};

			            // spawn a thread to track travel simulation
			[_unitTypes, _idFormat, _special, _vehType, _entryPos, _targetPos, _travelTime, _displayName, _entryName, _spawnSquadDirect, _distance, _costMoney, _costHR, _spawnPos, _addHC, _clientOwnerID] spawn {
				params ["_unitTypes", "_idFormat", "_special", "_vehType", "_entryPos", "_targetPos", "_travelTime", "_displayName", "_entryName", "_spawnSquadDirect", "_distance", "_costMoney", "_costHR", "_spawnPos", "_addHC", "_clientOwnerID"];

				private _travelMarker = "";
				if (_travelTime > 0) then {
					private _tMarkerName = format ["A3A_planning_travel_%1_%2", _idFormat, round (random 99999)];
					if (getMarkerPos _tMarkerName isNotEqualTo [0,0,0]) then { deleteMarker _tMarkerName; };
					_travelMarker = createMarker [_tMarkerName, _hqPos];
					_travelMarker setMarkerType "mil_arrow";
					_travelMarker setMarkerColor "ColorGUER";
					_travelMarker setMarkerText format ["%1 (En Route)", _displayName];

					// Radio departure report
					[format ["%1 attack group departing HQ for Staging Area %2. Distance: %3m | ETA: %4 seconds.", _displayName, _entryName, _distance, _travelTime]] remoteExec ["A3A_fnc_planning_localSideChat", 0];

					private _startTime = time;
					private _endTime = time + _travelTime;
					private _halfTimeLogged = false;

					while { time < _endTime } do {
						private _progress = ((time - _startTime) / _travelTime) min 1;
						private _currentPos = [
							(_hqPos select 0) + ((_entryPos select 0) - (_hqPos select 0)) * _progress,
							(_hqPos select 1) + ((_entryPos select 1) - (_hqPos select 1)) * _progress,
							0
						];
						_travelMarker setMarkerPos _currentPos;

						if (!_halfTimeLogged && { _progress >= 0.5 }) then {
							_halfTimeLogged = true;
							[format ["%1 attack group is halfway to Staging Area %2.", _displayName, _entryName]] remoteExec ["A3A_fnc_planning_localSideChat", 0];
						};

						sleep 1;
					};

					deleteMarker _travelMarker;
				};

				                // spawn the group safely at pre-allocated position
				private _group = [_unitTypes, _idFormat, _special, _vehType, _spawnPos, _targetPos, _addHC, _clientOwnerID] call _spawnSquadDirect;

				if (!isNull _group) then {
					// set tracking variables on group
					_group setVariable ["siege_costMoney", _costMoney, true];
					_group setVariable ["siege_costHR", _costHR, true];
					_group setVariable ["siege_originalCount", count (units _group), true];

					                    // Track active group for garrison/refund
					A3A_planning_activeGroups pushBack _group;
					publicVariable "A3A_planning_activeGroups";

					                    // Radio arrival report
					[format ["%1 reports arrival at Staging Area %2! Dismounting and commencing assault.", groupID _group, _entryName]] remoteExec ["A3A_fnc_planning_localSideChat", 0];

					// Track the active group on the map in real-time
					[_group, _idFormat] spawn {
						params ["_group", "_idFormat"];
						private _trkMarkerName = format ["A3A_planning_track_%1_%2", _idFormat, round (random 99999)];
						if (getMarkerPos _trkMarkerName isNotEqualTo [0,0,0]) then { deleteMarker _trkMarkerName; };
						private _trackMarker = createMarker [_trkMarkerName, getPosATL (leader _group)];
						_trackMarker setMarkerType "mil_dot";
						_trackMarker setMarkerColor "ColorGUER";
						_trackMarker setMarkerText _idFormat;

						while { !isNull _group && { { alive _x } count (units _group) > 0 } && { call A3A_fnc_planning_isSiegeActive } } do {
							private _ldr = leader _group;
							if (alive _ldr) then {
								_trackMarker setMarkerPos (getPosATL _ldr);
							};
							sleep 4;
						};

						deleteMarker _trackMarker;
					};
				};
			};
		} forEach _validatedQueue;
		diag_log "[A3A DEBUG] Stage 7: dispatch loop completed";
	};

	A3A_planning_assaultStarted = true;
	publicVariable "A3A_planning_objective";
	publicVariable "A3A_planning_assaultStarted";
};