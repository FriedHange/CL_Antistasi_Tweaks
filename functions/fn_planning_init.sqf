/*
	    fn_planning_init.sqf
	    Initializes global variables, states, and background execution loops for the Siege & Attack Planning system.
	    Supports target selection, multiple deployment entry points, and recruitment queues.
*/

if (isNil "A3A_planning_initDone") then {
	A3A_planning_initDone = true;

	    // Reworked State Variables
	    A3A_planning_objective = "";                 // Selected target zone marker
	    A3A_planning_entryPoints = [];               // List of active entry point names (e.g. ["Alpha", "Beta"])
	    A3A_planning_sharedEntry = true;             // Whether all squads share a single entry point
	    A3A_planning_selectedSharedEntry = "Alpha";  // Selected shared entry point name
	    A3A_planning_queue = [];                     // Recruitment queue of squads: [_squadType, _idFormat, _special, _money, _hr, _vehType, _displayName, _assignedEntryName]
	    A3A_planning_assaultStarted = false;         // Assault state for progressive capture loop compatibility
	    A3A_planning_activeGroups = [];              // Track deployed groups for refund/garrison
	    A3A_planning_captureTriggered = false;       // Sector capture trigger state
	    A3A_planning_reservedGarageVehicles = [];    // Classnames of garage vehicles currently queued for siege (prevents double-queuing)

	    // Global function: Robust check if a siege operation is currently active
	    A3A_fnc_planning_isSiegeActive = {
		    if (isNil "A3A_planning_assaultStarted" || { !A3A_planning_assaultStarted }) exitWith { false };
		    if (isNil "A3A_planning_objective" || { A3A_planning_objective == "" }) exitWith {
			    A3A_planning_assaultStarted = false;
			    false
		    };
		    if !(A3A_planning_objective in allMapMarkers) exitWith {
			    A3A_planning_assaultStarted = false;
			    A3A_planning_objective = "";
			    false
		    };
		    private _side = sidesX getVariable [A3A_planning_objective, sideUnknown];
		    if (_side == teamPlayer) exitWith {
			    A3A_planning_assaultStarted = false;
			    false
		    };
		    true
	    };

	    // Global function: Calculate the active Area of Operations (AO) radius for an objective
	    A3A_fnc_planning_getAORadius = {
		    params [["_marker", "", [""]]];
		    if (_marker == "") exitWith { 300 };
		    private _markerSize = markerSize _marker;
		    private _maxMarkerDim = selectMax _markerSize;
		    private _airports = missionNamespace getVariable ["airportsX", []];
		    private _milbases = missionNamespace getVariable ["milbases", []];
		    private _outposts = missionNamespace getVariable ["outposts", []];
		    private _cities = missionNamespace getVariable ["citiesX", []];
		    switch (true) do {
			    case (_marker in _airports): { _maxMarkerDim max 750 };
			    case (_marker in _milbases): { _maxMarkerDim max 450 };
			    case (_marker in _outposts): { _maxMarkerDim max 350 };
			    case (_marker in _cities): { _maxMarkerDim max 400 };
			    default { _maxMarkerDim max 300 };
		    }
	    };

	    // Global function: Check whether a position or unit is within the target objective's AO
	    A3A_fnc_planning_isInsideAO = {
		    params [["_posOrUnit", [0, 0, 0], [[], objNull]], ["_marker", "", [""]]];
		    if (_marker == "") exitWith { false };
		    private _pos = if (_posOrUnit isEqualType objNull) then { getPosATL _posOrUnit } else { _posOrUnit };
		    if (count _pos < 2) exitWith { false };
		    private _targetPos = getMarkerPos _marker;
		    private _aoRadius = [_marker] call A3A_fnc_planning_getAORadius;
		    if ((_pos distance2D _targetPos) <= _aoRadius) exitWith { true };
		    if (!isNil "A3A_fnc_isWithinMarkerArea" && { [_pos, _marker] call A3A_fnc_isWithinMarkerArea }) exitWith { true };
		    false
	    };

	    // UI Helpers
	    A3A_planning_includeVehicle = true;          // Checkbox state for including vehicles
	    A3A_planning_selectedSquadIndex = 0;         // Selected squad type index (0-10)
	    A3A_planning_selectedSquadEntry = "Alpha";   // Target entry point for the currently selected squad when not shared
	    A3A_planning_selectedStagingToMove = "";     // Currently selected staging point name for movement
	    A3A_planning_selectedGarageVehicleIdx = -1;  // Selected index in the garage vehicle dropdown (IDC 8030)

	// Client-side helper: returns [_hasHelipad, _hasAirfield, _friendlyHelipads, _friendlyAirfields]
	A3A_fnc_planning_getFriendlyInfrastructure = {
		private _friendlyAirports = [];
		private _friendlyHelipads = [];

		if (!isNil "sidesX") then {
			private _airports = missionNamespace getVariable ["airportsX", []];
			{
				if ((sidesX getVariable [_x, sideUnknown]) == teamPlayer) then {
					_friendlyAirports pushBack _x;
					_friendlyHelipads pushBack _x;
				};
			} forEach _airports;

			private _outposts = missionNamespace getVariable ["outposts", []];
			{
				if ((sidesX getVariable [_x, sideUnknown]) == teamPlayer) then {
					_friendlyHelipads pushBack _x;
				};
			} forEach _outposts;

			private _seaports = missionNamespace getVariable ["seaports", []];
			{
				if ((sidesX getVariable [_x, sideUnknown]) == teamPlayer) then {
					_friendlyHelipads pushBack _x;
				};
			} forEach _seaports;
		};

		// HQ is always a valid fallback helipad location
		if (count _friendlyHelipads == 0) then {
			_friendlyHelipads pushBack "respawn_west";
		};

		private _hasAirfield = (count _friendlyAirports > 0);
		private _hasHelipad = (count _friendlyHelipads > 0);

		[_hasHelipad, _hasAirfield, _friendlyHelipads, _friendlyAirports]
	};

	// Calculates combat/crew seats (driver, pilot, commander, gunner, weapon turrets) dynamically for any vehicle class
	A3A_fnc_planning_getVehicleCombatSeatCount = {
		params ["_class"];
		if (isNil "_class" || { _class == "" } || { !isClass (configFile >> "CfgVehicles" >> _class) }) exitWith { 2 };
		private _cfg = configFile >> "CfgVehicles" >> _class;

		private _fnc_countTurrets = {
			params ["_turretsCfg"];
			private _subCount = 0;
			if (isClass _turretsCfg) then {
				{
					if (isClass _x) then {
						private _isPerson = getNumber (_x >> "isPersonTurret");
						private _weapons = getArray (_x >> "weapons");
						if (_isPerson == 0 || { count _weapons > 0 }) then {
							_subCount = _subCount + 1;
						};
						if (isClass (_x >> "Turrets")) then {
							_subCount = _subCount + ([_x >> "Turrets"] call _fnc_countTurrets);
						};
					};
				} forEach ("true" configClasses _turretsCfg);
			};
			_subCount
		};

		private _turretSeats = [_cfg >> "Turrets"] call _fnc_countTurrets;
		private _totalCrew = (1 + _turretSeats) max 2;
		_totalCrew
	};

	// Client-side helper: builds the categorized, detailed list of combat-ready garage vehicles.
	// Returns array of [_dispName, _class, _crewCount, _vehUID, _category, _subcat, _isAvailable, _reason, _healthPct, _fuelPct, _ammoPct, _condition, _weaponsList, _picture, _availableCount] tuples.
	A3A_fnc_planning_getAvailableGarageVehicles = {
		private _reserved = missionNamespace getVariable ["A3A_planning_reservedGarageVehicles", []];
		private _infra = call A3A_fnc_planning_getFriendlyInfrastructure;
		_infra params ["_hasHelipad", "_hasAirfield", "_friendlyHelipads", "_friendlyAirfields"];

		private _rawVehicles = [];
		private _cfgVeh = configFile >> "CfgVehicles";

		// Helper: dynamic configuration-based check to filter out non-combat / logistics vehicles
		private _fnc_isCombatVehicle = {
			params ["_class"];
			if (isNil "_class" || { _class == "" } || { !isClass (_cfgVeh >> _class) }) exitWith { false };
			private _cfg = _cfgVeh >> _class;

			// Exclude non-combat categories & support roles by config properties
			private _vClass = getText (_cfg >> "vehicleClass");
			if (_vClass in ["Support", "Submarine", "Autonomous"]) exitWith { false };
			if (getNumber (_cfg >> "attendant") == 1) exitWith { false };       // Medical / Ambulance
			if (getNumber (_cfg >> "transportAmmo") > 0) exitWith { false };  // Ammo truck
			if (getNumber (_cfg >> "transportFuel") > 0) exitWith { false };  // Fuel truck
			if (getNumber (_cfg >> "transportRepair") > 0) exitWith { false };// Repair truck

			// Tanks, APCs, IFVs, Armed Helis, Planes are combat vehicles
			if (_class isKindOf "Tank" || _class isKindOf "Wheeled_APC_F" || _class isKindOf "APC_Tracked_F" || _class isKindOf "StaticWeapon") exitWith { true };

			// Inspect weapons array & turrets for mounted offensive weapons
			private _hasOffensiveWeapon = false;
			private _ignoredWeapons = ["Horn", "BikeHorn", "TruckHorn", "CarHorn", "SmokeLauncher", "FlareLauncher", "Laserdesignator"];

			private _weapons = getArray (_cfg >> "weapons");
			{
				private _w = _x;
				private _isIgnored = false;
				{ if ((_w find _x) != -1) exitWith { _isIgnored = true; }; } forEach _ignoredWeapons;
				if (!_isIgnored) exitWith { _hasOffensiveWeapon = true; };
			} forEach _weapons;

			if (_hasOffensiveWeapon) exitWith { true };

			private _turretsCfg = _cfg >> "Turrets";
			if (isClass _turretsCfg) then {
				{
					if (isClass _x) then {
						private _tWeapons = getArray (_x >> "weapons");
						{
							private _w = _x;
							private _isIgnored = false;
							{ if ((_w find _x) != -1) exitWith { _isIgnored = true; }; } forEach _ignoredWeapons;
							if (!_isIgnored) exitWith { _hasOffensiveWeapon = true; };
						} forEach _tWeapons;
					};
					if (_hasOffensiveWeapon) exitWith {};
				} forEach ("true" configClasses _turretsCfg);
			};

			_hasOffensiveWeapon
		};

		// Helper: dynamic category assignment
		private _fnc_getCategory = {
			params ["_class"];
			private _cfg = _cfgVeh >> _class;
			switch (true) do {
				case (_class isKindOf "Ship"): { "NAVAL" };
				case (_class isKindOf "Helicopter"): { "HELICOPTERS" };
				case (_class isKindOf "Plane"): { "AIRCRAFT" };
				case (getNumber (_cfg >> "artilleryScanner") == 1 || _class isKindOf "StaticMortar"): { "ARTILLERY" };
				case (_class isKindOf "Tank" || _class isKindOf "Wheeled_APC_F" || _class isKindOf "APC_Tracked_F"): { "ARMOR" };
				default { "CARS" };
			}
		};

		// Helper: dynamic subcategory role
		private _fnc_getSubcategory = {
			params ["_class", "_cat"];
			private _cfg = _cfgVeh >> _class;
			switch (_cat) do {
				case "CARS": {
					if (_class isKindOf "Car" && { count (getArray (_cfg >> "weapons")) > 0 || isClass (_cfg >> "Turrets" >> "MainTurret") }) then {
						"Armed Technical"
					} else { "MRAP / Armed Car" };
				};
				case "ARMOR": {
					if (_class isKindOf "Tank" && !(_class isKindOf "Wheeled_APC_F" || _class isKindOf "APC_Tracked_F")) then {
						"Combat Tank"
					} else { "APC / IFV" };
				};
				case "HELICOPTERS": {
					if (count (getArray (_cfg >> "weapons")) > 0) then {
						"Attack Helicopter"
					} else { "Transport / Utility Heli" };
				};
				case "AIRCRAFT": { "CAS / Strike Aircraft" };
				case "ARTILLERY": { "Artillery / Rocket" };
				case "NAVAL": { "Patrol / Gunboat" };
				default { "Combat Vehicle" };
			}
		};

		// Helper: weapon systems summary
		private _fnc_getWeaponsList = {
			params ["_class"];
			private _cfg = _cfgVeh >> _class;
			private _rawWeapons = +getArray (_cfg >> "weapons");
			private _turretsCfg = _cfg >> "Turrets";
			if (isClass _turretsCfg) then {
				{
					if (isClass _x) then {
						_rawWeapons append getArray (_x >> "weapons");
					};
				} forEach ("true" configClasses _turretsCfg);
			};

			private _ignoredWeapons = ["Horn", "BikeHorn", "TruckHorn", "CarHorn", "SmokeLauncher", "FlareLauncher", "Laserdesignator"];
			private _names = [];
			{
				private _w = _x;
				private _isIgnored = false;
				{ if ((_w find _x) != -1) exitWith { _isIgnored = true; }; } forEach _ignoredWeapons;
				if (!_isIgnored) then {
					private _wCfg = configFile >> "CfgWeapons" >> _w;
					private _wName = if (isClass _wCfg) then { getText (_wCfg >> "displayName") } else { _w };
					if (_wName != "" && !(_wName in _names)) then {
						_names pushBack _wName;
					};
				};
			} forEach _rawWeapons;

			if (count _names == 0) then { "Standard Armament" } else { _names joinString ", " };
		};

		// 1. Query HR Garage (HR_GRG_Vehicles)
		if (!isNil "HR_GRG_Vehicles" && { HR_GRG_Vehicles isEqualType [] }) then {
			{
				private _catMap = _x;
				if (_catMap isEqualType createHashMap) then {
					{
						private _vehData = _catMap get _x;
						if (_vehData isEqualType [] && { count _vehData > 1 }) then {
							private _dispName = _vehData select 0;
							private _class = _vehData select 1;
							private _vehUID = if (_x isEqualType "") then { _x } else { str _x };
							private _dmg = if (count _vehData > 4) then { _vehData select 4 } else { 0 };
							private _fuel = if (count _vehData > 5) then { _vehData select 5 } else { 1 };
							private _mags = if (count _vehData > 6) then { _vehData select 6 } else { [] };

							if (!isNil "_class" && { _class != "" } && { [_class] call _fnc_isCombatVehicle }) then {
								_rawVehicles pushBack [_dispName, _class, _vehUID, _dmg, _fuel, _mags];
							};
						};
					} forEach keys _catMap;
				};
			} forEach HR_GRG_Vehicles;
		};

		// 2. Query fallback vehInGarage if HR_GRG_Vehicles was empty or not initialized
		if (count _rawVehicles == 0 && { !isNil "vehInGarage" && { vehInGarage isEqualType [] } }) then {
			{
				private _class = _x;
				if ([_class] call _fnc_isCombatVehicle) then {
					private _cfg = _cfgVeh >> _class;
					private _dispName = if (isClass _cfg) then { getText (_cfg >> "displayName") } else { _class };
					_rawVehicles pushBack [_dispName, _class, "", 0, 1, []];
				};
			} forEach vehInGarage;
		};

		// Count available copies per class
		private _classCounts = createHashMap;
		{
			private _c = _x select 1;
			_classCounts set [_c, (_classCounts getOrDefault [_c, 0]) + 1];
		} forEach _rawVehicles;

		private _result = [];
		private _processedUIDs = [];
		private _reservedCopy = +_reserved;

		{
			_x params ["_dispName", "_class", "_vehUID", "_dmg", "_fuel", "_mags"];
			private _strUID = if (isNil "_vehUID") then { "" } else { if (_vehUID isEqualType "") then { _vehUID } else { str _vehUID } };

			// If multiple copies exist, avoid listing duplicate UID entries unless unique data
			if (_strUID == "" || { !(_strUID in _processedUIDs) }) then {
				if (_strUID != "") then { _processedUIDs pushBack _strUID; };

				private _rIdx = _reservedCopy find _class;
				if (_rIdx != -1) then {
					_reservedCopy deleteAt _rIdx;
				} else {
					private _cfg = _cfgVeh >> _class;
					if (isNil "_dispName" || { _dispName == "" }) then {
						_dispName = if (isClass _cfg) then { getText (_cfg >> "displayName") } else { _class };
					};

					private _category = [_class] call _fnc_getCategory;
					private _subcat = [_class, _category] call _fnc_getSubcategory;
					private _weaponsList = [_class] call _fnc_getWeaponsList;

					private _isAvailable = true;
					private _reason = "";

					if (_category == "HELICOPTERS" && { !_hasHelipad }) then {
						_isAvailable = false;
						_reason = "Requires Helipad Location";
					};
					if (_category == "AIRCRAFT" && { !_hasAirfield }) then {
						_isAvailable = false;
						_reason = "Requires Airfield";
					};

					private _fnc_getDamageNum = {
						params ["_d"];
						if (isNil "_d") exitWith { 0 };
						if (_d isEqualType 0) exitWith { _d };
						if (_d isEqualType []) exitWith {
							if (count _d == 0) exitWith { 0 };
							private _maxDmg = 0;
							{ if (_x isEqualType 0) then { _maxDmg = _maxDmg max _x; }; } forEach _d;
							_maxDmg
						};
						0
					};

					private _fnc_getFuelNum = {
						params ["_f"];
						if (isNil "_f") exitWith { 1 };
						if (_f isEqualType 0) exitWith { _f };
						if (_f isEqualType []) exitWith {
							if (count _f == 0) exitWith { 1 };
							private _sum = 0;
							{ if (_x isEqualType 0) then { _sum = _sum + _x; }; } forEach _f;
							(_sum / count _f)
						};
						1
					};

					private _dmgNum = [_dmg] call _fnc_getDamageNum;
					private _fuelNum = [_fuel] call _fnc_getFuelNum;

					private _healthPct = (round ((1 - ((_dmgNum max 0) min 1)) * 100)) max 0 min 100;
					private _fuelPct = (round (((_fuelNum max 0) min 1) * 100)) max 0 min 100;
					private _ammoPct = if (count _mags > 0) then { 100 } else { 80 }; // status placeholder

					private _condition = switch (true) do {
						case (_healthPct >= 90): { "Operational" };
						case (_healthPct >= 50): { "Damaged" };
						default { "Critical" };
					};

					private _picture = getText (_cfg >> "editorPreview");
					if (_picture == "") then { _picture = getText (_cfg >> "picture"); };

					private _crewCount = [_class] call A3A_fnc_planning_getVehicleCombatSeatCount;
					private _availableCount = _classCounts getOrDefault [_class, 1];

					_result pushBack [
						_dispName,
						_class,
						_crewCount,
						_strUID,
						_category,
						_subcat,
						_isAvailable,
						_reason,
						_healthPct,
						_fuelPct,
						_ammoPct,
						_condition,
						_weaponsList,
						_picture,
						_availableCount
					];
				};
			};
		} forEach _rawVehicles;

		_result
	};

	diag_log "[A3A Ultimate Tweaks Extender] Siege Planning system initialized.";

	    // Run progressive sector control loop and helper tasks on server
	if (isServer) then {
		[] spawn A3A_fnc_planning_sectorControl;

		A3A_fnc_planning_getAssaultAnchor = {
			// Finds the nearest currently-active ASSAULT (plain infantry) group with alive units to a target position, 
			// and whether it has moved meaningfully from its spawn point yet.
			// Returns [_hasAdvanced, _anchorPos, _anchorDist]. _anchorDist is -1 if there is no
			// active infantry group in this siege.
			params ["_targetPos"];
			private _anchorPos = [];
			private _anchorDist = -1;
			private _hasAdvanced = false;
			private _bestDist = 1e9;
			if (!isNil "A3A_planning_activeGroups") then {
				{
					if (!isNull _x && {
						(_x getVariable ["siege_role", "ASSAULT"]) == "ASSAULT"
					} && {
						count (units _x select { alive _x }) > 0
					}) then {
						private _ldr = leader _x;
						if (alive _ldr) then {
							private _curPos = getPosATL _ldr;
							private _d = _curPos distance2D _targetPos;
							if (_d < _bestDist) then {
								_bestDist = _d;
								_anchorPos = _curPos;
								_anchorDist = _d;
								private _spawnPos = _x getVariable ["siege_spawnPos", []];
								_hasAdvanced = if (count _spawnPos == 3) then {
									(_curPos distance2D _spawnPos) > 20
								} else {
									true
								};
							};
						};
					};
				} forEach A3A_planning_activeGroups;
			};
			[_hasAdvanced, _anchorPos, _anchorDist]
		};

		A3A_fnc_planning_serverDeductGarage = {
			params ["_vehicles"];
			{
				private _targetClass = _x;
				if (!isNil "HR_GRG_Vehicles" && { HR_GRG_Vehicles isEqualType [] }) then {
					private _found = false;
					{
						private _catMap = _x;
						if (_catMap isEqualType createHashMap) then {
							{
								private _vehData = _catMap get _x;
								if (_vehData isEqualType [] && { count _vehData > 1 } && { (_vehData select 1) == _targetClass }) exitWith {
									_catMap deleteAt _x;
									_found = true;
								};
							} forEach keys _catMap;
						};
						if (_found) exitWith {};
					} forEach HR_GRG_Vehicles;
				};

				if (!isNil "vehInGarage" && { vehInGarage isEqualType [] }) then {
					private _idx = vehInGarage find _targetClass;
					if (_idx != -1) then {
						vehInGarage deleteAt _idx;
					};
				};
			} forEach _vehicles;
			publicVariable "vehInGarage";
			if (!isNil "HR_GRG_Vehicles") then { publicVariable "HR_GRG_Vehicles"; };
		};

		A3A_fnc_planning_serverAddGarage = {
			params ["_vehicles"];

			// Resolve each entry (accepts live vehicle objects and classname strings)
			private _vehicleClasses = [];
			private _liveObjects = [];

			{
				if (_x isEqualType objNull) then {
					if (!isNull _x) then {
						_liveObjects pushBack _x;
						private _c = typeOf _x;
						_vehicleClasses pushBack _c;
						if (!isNil "vehInGarage" && { vehInGarage isEqualType [] }) then {
							vehInGarage pushBack _c;
						};
					} else {
						diag_log "[A3A Planning Warning] serverAddGarage: received null object - skipping.";
					};
				} else {
					if (_x isEqualType "") then {
						_vehicleClasses pushBack _x;
						if (!isNil "vehInGarage" && { vehInGarage isEqualType [] }) then {
							vehInGarage pushBack _x;
						};
					} else {
						diag_log format ["[A3A Planning Warning] serverAddGarage: unexpected entry type '%1' - skipping.", typeName _x];
					};
				};
			} forEach _vehicles;

			if (!isNil "vehInGarage" && { vehInGarage isEqualType [] }) then {
				publicVariable "vehInGarage";
			};

			// 1. Try object-based HR Garage registration for live vehicles (preserves damage, fuel, magazines, ammo, persistent state)
			if (count _liveObjects > 0 && { !isNil "HR_GRG_fnc_addVehicles" }) then {
				try {
					private _addedObj = [_liveObjects, ""] call HR_GRG_fnc_addVehicles;
					diag_log format ["[A3A Planning] serverAddGarage: registered %1 live vehicle object(s) with HR_GRG_fnc_addVehicles (result: %2).", count _liveObjects, _addedObj];
				} catch {
					diag_log format ["[A3A Planning Warning] serverAddGarage: exception during HR_GRG_fnc_addVehicles: %1", _exception];
				};
			};

			if (_vehicleClasses isEqualTo []) exitWith {
				diag_log "[A3A Planning Warning] serverAddGarage: no valid vehicle classes resolved - nothing to register with HR Garage.";
			};

			// 2. Class-based HR Garage fallback registration for any class strings not covered by live objects
			if (isNil "HR_GRG_fnc_addVehiclesByClass") exitWith {
				diag_log format ["[A3A Planning Warning] serverAddGarage: HR_GRG_fnc_addVehiclesByClass is nil. vehInGarage updated successfully for: %1", _vehicleClasses];
			};

			private _garageClasses = [];
			private _cfgVehicles = configFile >> "CfgVehicles";
			{
				if (!isClass (_cfgVehicles >> _x)) then {
					diag_log format ["[A3A Planning Warning] serverAddGarage: '%1' is not a valid CfgVehicles class - skipping HR Garage registration.", _x];
					continue;
				};

				if (!isNil "HR_GRG_fnc_getCatIndex" && {
					([_x] call HR_GRG_fnc_getCatIndex) < 0
				}) then {
					diag_log format ["[A3A Planning Warning] serverAddGarage: '%1' is in an unsupported HR Garage category (index < 0) - skipping.", _x];
					continue;
				};

				_garageClasses pushBack _x;
			} forEach _vehicleClasses;

			if (_garageClasses isEqualTo []) exitWith {
				diag_log format ["[A3A Planning Warning] serverAddGarage: all recovered vehicles failed HR Garage validation. Candidates were: %1", _vehicleClasses];
			};

			diag_log format ["[A3A Planning] serverAddGarage: calling HR_GRG_fnc_addVehiclesByClass with: %1", _garageClasses];
			private _added = [_garageClasses, ""] call HR_GRG_fnc_addVehiclesByClass;
			if (_added) then {
				diag_log format ["[A3A Planning] serverAddGarage: successfully registered %1 vehicle(s) with HR Garage: %2", count _garageClasses, _garageClasses];
			} else {
				diag_log format ["[A3A Planning Warning] serverAddGarage: HR_GRG_fnc_addVehiclesByClass returned false for: %1. vehInGarage was already updated - vehicles may still be available on next session load.", _garageClasses];
			};
		};
	};
};

// Client-side native stacked event handler for map clicks
A3A_fnc_planning_onMapClick = {
	params ["_pos"];

	private _display = findDisplay 60000;
	if (isNull _display) exitWith {};

	diag_log format ["[A3A Planning MapClick] Clicked at pos: %1, MapMode: %2", _pos, A3A_planning_mapMode];

	if (!isNil "A3A_planning_mapMode" && {
		A3A_planning_mapMode != ""
	}) then {
		if (A3A_planning_mapMode == "TARGET") then {
			private _validTargets = outposts + airportsX + resourcesX + factories + seaports + milbases;
			private _marker = [_validTargets, _pos] call BIS_fnc_nearestPosition;
			if (getMarkerPos _marker distance2D _pos < 800) then {
				private _side = sidesX getVariable [_marker, sideUnknown];
				if (_side == Occupants || _side == Invaders) then {
					A3A_planning_objective = _marker;
					private _name = markerText ("Dum" + _marker);
					if (_name == "") then {
						_name = _marker;
					};
					["Target Selected", format ["Objective set to %1.", _name], false] call A3A_fnc_planning_showNotification;
					                    A3A_planning_mapMode = ""; // Clear mode

					                    // Remove stacked handler
					["A3A_planning_mapClick", "onMapSingleClick"] call BIS_fnc_removeStackedEventHandler;

					[_display] call A3A_fnc_planning_ui;
				} else {
					["Target Selection Failed", "You must select an enemy-controlled outpost, roadblock, or base.", true] call A3A_fnc_planning_showNotification;
				};
			} else {
				["Target Selection Failed", "No enemy objective close to click location.", true] call A3A_fnc_planning_showNotification;
			};
		};

		if (A3A_planning_mapMode in ["STAGING", "STAGING_ADD", "STAGING_MOVE", "STAGING_DELETE"]) then {
			// Deselect High Command groups to prevent issuing accidental orders or selection conflicts
			player hcSelectGroup [grpNull];

			if (A3A_planning_mapMode == "STAGING_DELETE") exitWith {
				private _nearestMarker = "";
				private _nearestDist = 250;
				{
					private _mName = "A3A_planning_entry_" + _x;
					if (_mName in allMapMarkers) then {
						private _dist = getMarkerPos _mName distance2D _pos;
						if (_dist < _nearestDist) then {
							_nearestDist = _dist;
							_nearestMarker = _x;
						};
					};
				} forEach A3A_planning_entryPoints;

				if (_nearestMarker != "") then {
					private _mName = "A3A_planning_entry_" + _nearestMarker;
					deleteMarkerLocal _mName;

					A3A_planning_entryPoints = A3A_planning_entryPoints - [_nearestMarker];

					private _cleanedQueue = [];
					{
						private _entryName = if (count _x > 7) then { _x select 7 } else { "" };
						if (_entryName != _nearestMarker) then {
							_cleanedQueue pushBack _x;
						};
					} forEach A3A_planning_queue;
					A3A_planning_queue = _cleanedQueue;

					["Staging Removed", format ["Removed staging point %1 and cleared any queued squads assigned to it.", _nearestMarker], false] call A3A_fnc_planning_showNotification;
					A3A_planning_mapMode = "";

					["A3A_planning_mapClick", "onMapSingleClick"] call BIS_fnc_removeStackedEventHandler;
					onMapSingleClick "";

					[_display] call A3A_fnc_planning_ui;
				} else {
					["Selection Failed", "No staging point found within 250m of click.", true] call A3A_fnc_planning_showNotification;
				};
			};

			private _nearEnemy = false;
			private _nearMarkerName = "";
			{
				private _side = sidesX getVariable [_x, sideUnknown];
				if (_side == Occupants || _side == Invaders) then {
					if (getMarkerPos _x distance2D _pos < 500) exitWith {
						_nearEnemy = true;
						_nearMarkerName = markerText ("Dum" + _x);
						if (_nearMarkerName == "") then {
							_nearMarkerName = _x;
						};
					};
				};
			} forEach (outposts + airportsX + resourcesX + factories + seaports + milbases);

			if (_nearEnemy) exitWith {
				["Placement Blocked", format ["You cannot set a staging area within 500m of enemy territory (%1).", _nearMarkerName], true] call A3A_fnc_planning_showNotification;
			};

			if (A3A_planning_mapMode == "STAGING_ADD") then {
				private _allNames = ["Alpha", "Beta", "Gamma", "Delta"];
				private _nextName = "";
				{
					if !(_x in A3A_planning_entryPoints) exitWith {
						_nextName = _x;
					};
				} forEach _allNames;

				if (_nextName != "") then {
					A3A_planning_entryPoints pushBack _nextName;
					private _mName = "A3A_planning_entry_" + _nextName;
					private _m = createMarkerLocal [_mName, _pos];
					_m setMarkerTypeLocal "mil_start";
					_m setMarkerColorLocal "ColorGreen";
					_m setMarkerTextLocal ("Staging: " + _nextName);
					["Staging Area Added", format ["Staging point %1 registered.", _nextName], false] call A3A_fnc_planning_showNotification;
				} else {
					["Limit Reached", "You can have a maximum of 4 staging markers. Use Move Staging mode to relocate one.", true] call A3A_fnc_planning_showNotification;
				};
			};

			if (A3A_planning_mapMode == "STAGING_MOVE") then {
				if (isNil "A3A_planning_selectedStagingToMove") then {
					A3A_planning_selectedStagingToMove = "";
				};

				if (A3A_planning_selectedStagingToMove == "") then {
					// step 1: select marker to move. Check within 250m radius.
					private _nearestMarker = "";
					private _nearestDist = 250;
					{
						private _mName = "A3A_planning_entry_" + _x;
						if (_mName in allMapMarkers) then {
							private _dist = getMarkerPos _mName distance2D _pos;
							if (_dist < _nearestDist) then {
								_nearestDist = _dist;
								_nearestMarker = _x;
							};
						};
					} forEach A3A_planning_entryPoints;

					if (_nearestMarker != "") then {
						A3A_planning_selectedStagingToMove = _nearestMarker;
						("A3A_planning_entry_" + _nearestMarker) setMarkerColorLocal "ColorYellow";
						["Staging Selected", format ["Selected staging point %1. Click anywhere on the map to move it.", _nearestMarker], false] call A3A_fnc_planning_showNotification;
					} else {
						["Selection Failed", "No staging point found within 250m of click.", true] call A3A_fnc_planning_showNotification;
					};
				} else {
					// step 2: Reposition the selected marker.
					private _mName = "A3A_planning_entry_" + A3A_planning_selectedStagingToMove;
					if (_mName in allMapMarkers) then {
						_mName setMarkerPos _pos;
						_mName setMarkerColorLocal "ColorGreen";
						["Staging Area Moved", format ["Moved %1 to new location.", A3A_planning_selectedStagingToMove], false] call A3A_fnc_planning_showNotification;
					};
					A3A_planning_selectedStagingToMove = "";
				};
			};

			            // Legacy STAGING mode (for compatibility or fallback)
			if (A3A_planning_mapMode == "STAGING") then {
				private _moved = false;
				{
					private _mName = "A3A_planning_entry_" + _x;
					if (getMarkerPos _mName distance2D _pos < 250) exitWith {
						_mName setMarkerPos _pos;
						_moved = true;
						["Staging Area Moved", format ["Moved %1 to new location.", _x], false] call A3A_fnc_planning_showNotification;
					};
				} forEach A3A_planning_entryPoints;

				if (!_moved) then {
					private _allNames = ["Alpha", "Beta", "Gamma", "Delta"];
					private _nextName = "";
					{
						if !(_x in A3A_planning_entryPoints) exitWith {
							_nextName = _x;
						};
					} forEach _allNames;

					if (_nextName != "") then {
						A3A_planning_entryPoints pushBack _nextName;
						private _mName = "A3A_planning_entry_" + _nextName;
						private _m = createMarkerLocal [_mName, _pos];
						_m setMarkerTypeLocal "mil_start";
						_m setMarkerColorLocal "ColorGreen";
						_m setMarkerTextLocal ("Staging: " + _nextName);
						["Staging Area Added", format ["Staging point %1 registered.", _nextName], false] call A3A_fnc_planning_showNotification;
					} else {
						["Limit Reached", "You can have a maximum of 4 staging markers. Click near one to move it.", true] call A3A_fnc_planning_showNotification;
					};
				};
			};
			[_display] call A3A_fnc_planning_ui;
		};
	};
};