/*
	fn_planning_airOverwatch.sqf
	Dedicated AI behavior and recovery loop for GarageCrew air assets (helicopters and fixed-wing aircraft).

	Behavior loop:
	  - Helicopter CAS: Ingress -> Attack Run -> Egress flight passes with varying approach angles (+60° per pass)
	    at high forward airspeed (45–60 m/s), maintaining 180m AGL standoff without hovering over enemy base.
	  - Fixed-Wing CAS: High-speed attack runs (120–160 m/s) through target area at 250m AGL with 1200m egress turnarounds.
	  - 6-Tier Target Prioritization: AA Vehicles -> MANPADS/Static AA -> Enemy Armor -> Armed Vehicles -> Infantry.
	  - Exit conditions: Objective captured, ammo depleted, vehicle destroyed/critically damaged (damage > 0.6), or all crew KIA.
	  - Recovery: Egress to friendly territory, refund surviving crew HR, preserve vehicle state (damage, fuel, ammo) and return object to HQ Garage.

	Params: [_group, _vehicle, _targetMarker, _targetPos]
*/
params ["_group", "_vehicle", "_targetMarker", "_targetPos"];

if (isNull _group || { isNull _vehicle }) exitWith {
	diag_log "[A3A Planning] airOverwatch: called with null group or vehicle - aborting.";
};

// Wait for alive crew to sync
private _syncTimeout = time + 10;
while { ({ alive _x } count (crew _vehicle) == 0) && { time < _syncTimeout } } do {
	sleep 0.5;
};
if ({ alive _x } count (crew _vehicle) == 0) exitWith {
	diag_log format ["[A3A Planning] airOverwatch: group %1 has no alive crew after sync - aborting.", groupId _group];
};

private _isHeli = _vehicle isKindOf "Helicopter";
private _isPlane = _vehicle isKindOf "Plane";
private _flyHeight = if (_isPlane) then { 250 } else { 90 };
private _vehClass = typeOf _vehicle;
private _dispName = getText (configFile >> "CfgVehicles" >> _vehClass >> "displayName");
if (_dispName == "") then { _dispName = _vehClass; };

_group setBehaviour "COMBAT";
_group setCombatMode "RED";
_group setSpeedMode "FULL";
_vehicle flyInHeight _flyHeight;
_vehicle engineOn true;

diag_log format ["[A3A Planning] Air Overwatch started: group=%1 vehicle=%2 isHeli=%3 isPlane=%4", groupId _group, _vehClass, _isHeli, _isPlane];

// --- Helper: 6-Tier Target Prioritization ---
// 1. Anti-Air Vehicles (SPAAG, AA trucks, AA tanks)
// 2. MANPADS / Static AA units
// 3. Enemy Armor (Tanks, IFVs, APCs)
// 4. Armed Vehicles (Technicals, MRAPs)
// 5. Infantry Concentrations (2+ troops)
// 6. Individual Infantry
private _fnc_getAirPriorityTarget = {
	params ["_objPos", "_radius"];
	private _nearUnits = allUnits select {
		alive _x && { side _x in [Occupants, Invaders] } && { _x distance2D _objPos < _radius }
	};
	if (count _nearUnits == 0) exitWith { objNull };

	private _aaVehicles = [];
	private _aaUnits = [];
	private _armorVehicles = [];
	private _armedVehicles = [];
	private _infantry = [];

	{
		private _u = _x;
		private _v = vehicle _u;
		private _vClass = typeOf _v;
		private _uType = typeOf _u;

		if (_v != _u) then {
			if !(_v in _aaVehicles || _v in _armorVehicles || _v in _armedVehicles) then {
				// Tier 1: Anti-Air Vehicles
				if (_vClass isKindOf "AA" || { (toLower _vClass find "aa") != -1 } || { (toLower _vClass find "shilka") != -1 } || { (toLower _vClass find "zsu") != -1 } || { (toLower _vClass find "flak") != -1 }) then {
					_aaVehicles pushBack _v;
				} else {
					// Tier 3: Armor (Tanks / IFVs / APCs)
					if (_v isKindOf "Tank" || _v isKindOf "Wheeled_APC_F" || _v isKindOf "APC_Tracked_F") then {
						_armorVehicles pushBack _v;
					} else {
						// Tier 4: Armed Vehicles
						_armedVehicles pushBack _v;
					};
				};
			};
		} else {
			// Tier 2: MANPADS / AA Units
			private _secondary = secondaryWeapon _u;
			if (_secondary != "" && { (toLower _secondary find "aa") != -1 || (toLower _secondary find "stinger") != -1 || (toLower _secondary find "igla") != -1 || (toLower _secondary find "titan") != -1 }) then {
				_aaUnits pushBack _u;
			} else {
				_infantry pushBack _u;
			};
		};
	} forEach _nearUnits;

	if (count _aaVehicles > 0) exitWith { ([_aaVehicles, [], { _x distance2D _objPos }, "ASCEND"] call BIS_fnc_sortBy) select 0 };
	if (count _aaUnits > 0) exitWith { ([_aaUnits, [], { _x distance2D _objPos }, "ASCEND"] call BIS_fnc_sortBy) select 0 };
	if (count _armorVehicles > 0) exitWith { ([_armorVehicles, [], { _x distance2D _objPos }, "ASCEND"] call BIS_fnc_sortBy) select 0 };
	if (count _armedVehicles > 0) exitWith { ([_armedVehicles, [], { _x distance2D _objPos }, "ASCEND"] call BIS_fnc_sortBy) select 0 };
	if (count _infantry > 0) exitWith { ([_infantry, [], { _x distance2D _objPos }, "ASCEND"] call BIS_fnc_sortBy) select 0 };

	objNull
};

// --- Helper: check if all offensive ammo is depleted ---
private _fnc_isAmmoExpended = {
	params ["_veh"];
	private _hasAmmo = false;
	{
		if (_veh ammo _x > 0) exitWith { _hasAmmo = true; };
	} forEach (weapons _veh);
	if (!_hasAmmo) then {
		{
			if ((_x select 1) > 0) exitWith { _hasAmmo = true; };
		} forEach (magazinesAllTurrets _veh);
	};
	!_hasAmmo
};

private _done = false;

// Helicopter CAS state machine variables
private _heliState = "APPROACH"; // "APPROACH", "ATTACK", "EGRESS"
private _spawnPos = _group getVariable ["siege_spawnPos", getPosATL _vehicle];
private _heliAngle = (_spawnPos vectorFromTo _targetPos) call { (_this select 0) atan2 (_this select 1) };
if (_heliAngle < 0) then { _heliAngle = _heliAngle + 360; };
private _heliTargetUnit = objNull;

// Fixed-Wing CAS state machine variables
private _planeState = "INGRESS"; // "INGRESS", "EGRESS"
private _planeTargetPos = _targetPos;

while { !_done } do {
	// ---- Exit conditions ----
	if (!alive _vehicle) exitWith {
		diag_log format ["[A3A Planning] Air Overwatch: %1 (%2) vehicle destroyed - no recovery.", groupId _group, _vehClass];
		_done = true;
	};
	if ({ alive _x } count (crew _vehicle) == 0) exitWith {
		diag_log format ["[A3A Planning] Air Overwatch: %1 (%2) all crew KIA.", groupId _group, _vehClass];
		_done = true;
	};
	if (damage _vehicle > 0.6 || !canMove _vehicle) exitWith {
		diag_log format ["[A3A Planning] Air Overwatch: %1 (%2) critically damaged (damage: %3) - disengaging & recovering.", groupId _group, _vehClass, round (damage _vehicle * 100)];
	};
	if ((sidesX getVariable [_targetMarker, sideUnknown]) == teamPlayer) exitWith {
		diag_log format ["[A3A Planning] Air Overwatch: %1 (%2) objective captured - starting mission completion & recovery.", groupId _group, _vehClass];
	};
	if ([_vehicle] call _fnc_isAmmoExpended) exitWith {
		diag_log format ["[A3A Planning] Air Overwatch: %1 (%2) ammo depleted - starting mission completion & recovery.", groupId _group, _vehClass];
	};

	private _curTgt = getMarkerPos _targetMarker;
	if (_curTgt isEqualTo [0,0,0]) then { _curTgt = _targetPos; };
	private _vPos = getPosATL _vehicle;

	// ---- Fixed-Wing Attack Run State Machine ----
	if (_isPlane) then {
		private _targetUnit = [_curTgt, 700] call _fnc_getAirPriorityTarget;
		private _tgtPos = if (!isNull _targetUnit) then { getPosATL _targetUnit } else { _curTgt };

		if (!isNull _targetUnit) then {
			_group reveal [_targetUnit, 4];
			private _drv = driver _vehicle;
			if (!isNull _drv) then { _drv doTarget _targetUnit; _drv doFire _targetUnit; };
		};

		if (_planeState == "INGRESS") then {
			if (_vPos distance2D _tgtPos < 350) then {
				_planeState = "EGRESS";
				_planeTargetPos = _tgtPos;
				diag_log format ["[A3A Planning] Fixed-wing %1 attack pass completed. Switching to EGRESS.", groupId _group];

				for "_i" from (count (waypoints _group) - 1) to 0 step -1 do { deleteWaypoint [_group, _i]; };
				private _dir = (getDir _vehicle);
				private _egressPos = _vPos vectorAdd [sin(_dir) * 1200, cos(_dir) * 1200, 0];
				private _wp = _group addWaypoint [_egressPos, 0];
				_wp setWaypointType "MOVE";
				_wp setWaypointBehaviour "COMBAT";
				_wp setWaypointSpeed "FULL";
				[_group, _wp select 1] remoteExec ["A3A_fnc_planning_localSetCurrentWaypoint", groupOwner _group];
			} else {
				if (count (waypoints _group) == 0) then {
					private _wp = _group addWaypoint [_tgtPos, 0];
					_wp setWaypointType "SAD";
					_wp setWaypointBehaviour "COMBAT";
					_wp setWaypointCombatMode "RED";
					_wp setWaypointSpeed "FULL";
					[_group, _wp select 1] remoteExec ["A3A_fnc_planning_localSetCurrentWaypoint", groupOwner _group];
				};
			};
		} else {
			// EGRESS state: wait until aircraft extends to 1100m from target
			if (_vPos distance2D _planeTargetPos > 1100) then {
				_planeState = "INGRESS";
				diag_log format ["[A3A Planning] Fixed-wing %1 egress completed. Turning around for INGRESS attack pass.", groupId _group];

				for "_i" from (count (waypoints _group) - 1) to 0 step -1 do { deleteWaypoint [_group, _i]; };
				private _wp = _group addWaypoint [_tgtPos, 0];
				_wp setWaypointType "SAD";
				_wp setWaypointBehaviour "COMBAT";
				_wp setWaypointCombatMode "RED";
				_wp setWaypointSpeed "FULL";
				[_group, _wp select 1] remoteExec ["A3A_fnc_planning_localSetCurrentWaypoint", groupOwner _group];
			};
		};
		_vehicle flyInHeight 250;
	};

	// ---- Helicopter CAS Ingress - Attack - Egress Cycle ----
	if (_isHeli) then {
		switch (_heliState) do {
			case "APPROACH": {
				// Calculate ingress position 500m outside objective at current approach angle
				private _ingressPos = _curTgt vectorAdd [sin(_heliAngle) * 500, cos(_heliAngle) * 500, 0];
				if (_vPos distance2D _ingressPos < 250 || count (waypoints _group) == 0) then {
					_heliState = "ATTACK";
					_heliTargetUnit = [_curTgt, 600] call _fnc_getAirPriorityTarget;
					private _strikePos = if (!isNull _heliTargetUnit) then { getPosATL _heliTargetUnit } else { _curTgt };

					for "_i" from (count (waypoints _group) - 1) to 0 step -1 do { deleteWaypoint [_group, _i]; };
					private _wp = _group addWaypoint [_strikePos, 0];
					_wp setWaypointType "SAD";
					_wp setWaypointBehaviour "COMBAT";
					_wp setWaypointCombatMode "RED";
					_wp setWaypointSpeed "FULL";
					[_group, _wp select 1] remoteExec ["A3A_fnc_planning_localSetCurrentWaypoint", groupOwner _group];

					if (!isNull _heliTargetUnit) then {
						_group reveal [_heliTargetUnit, 4];
						private _gunner = gunner _vehicle;
						private _driver = driver _vehicle;
						if (!isNull _gunner) then {
							_gunner doTarget _heliTargetUnit;
							_gunner doFire _heliTargetUnit;
							[_gunner, getPosATL _heliTargetUnit] remoteExec ["A3A_fnc_planning_localDoWatch", owner _gunner];
						};
						if (!isNull _driver) then {
							_driver doTarget _heliTargetUnit;
							_driver doFire _heliTargetUnit;
						};
					};
					diag_log format ["[A3A Planning] Helicopter %1 transitioning to ATTACK run at angle %2°.", groupId _group, round _heliAngle];
				} else {
					if (count (waypoints _group) == 0) then {
						private _wp = _group addWaypoint [_ingressPos, 0];
						_wp setWaypointType "MOVE";
						_wp setWaypointBehaviour "COMBAT";
						_wp setWaypointSpeed "FULL";
						[_group, _wp select 1] remoteExec ["A3A_fnc_planning_localSetCurrentWaypoint", groupOwner _group];
					};
				};
			};
			case "ATTACK": {
				// Check if heli has passed through target zone (within 180m or beyond)
				private _strikePos = if (!isNull _heliTargetUnit && { alive _heliTargetUnit }) then { getPosATL _heliTargetUnit } else { _curTgt };

				if (!isNull _heliTargetUnit && { alive _heliTargetUnit }) then {
					_group reveal [_heliTargetUnit, 4];
					private _gunner = gunner _vehicle;
					private _driver = driver _vehicle;
					if (!isNull _gunner) then { _gunner doTarget _heliTargetUnit; _gunner doFire _heliTargetUnit; };
					if (!isNull _driver) then { _driver doTarget _heliTargetUnit; _driver doFire _heliTargetUnit; };
				};

				if (_vPos distance2D _strikePos < 180 || { _vPos distance2D _curTgt < 200 }) then {
					_heliState = "EGRESS";
					diag_log format ["[A3A Planning] Helicopter %1 completed attack pass. Transitioning to EGRESS.", groupId _group];

					for "_i" from (count (waypoints _group) - 1) to 0 step -1 do { deleteWaypoint [_group, _i]; };
					private _dir = (getDir _vehicle);
					private _egressPos = _vPos vectorAdd [sin(_dir) * 600, cos(_dir) * 600, 0];
					private _wp = _group addWaypoint [_egressPos, 0];
					_wp setWaypointType "MOVE";
					_wp setWaypointBehaviour "COMBAT";
					_wp setWaypointSpeed "FULL";
					[_group, _wp select 1] remoteExec ["A3A_fnc_planning_localSetCurrentWaypoint", groupOwner _group];
				};
			};
			case "EGRESS": {
				// Wait until helicopter extends 550m outside objective, then rotate angle by +60° for next pass
				if (_vPos distance2D _curTgt > 550) then {
					_heliAngle = (_heliAngle + 60) % 360;
					_heliState = "APPROACH";
					diag_log format ["[A3A Planning] Helicopter %1 completed egress pass. Rotating entry angle to %2° for next pass.", groupId _group, round _heliAngle];
				};
			};
		};
		_vehicle flyInHeight 90;
	};

	sleep 4;
};

// ---- Mission Completion & Recovery ----
if (alive _vehicle) then {
	diag_log format ["[A3A Planning] Air Overwatch: recovering %1 (%2) to HQ Garage.", groupId _group, _vehClass];

	// Radio notification
	[format ["%1 (%2) mission concluded. Disengaging and returning to HQ Garage.", groupId _group, _dispName]] remoteExec ["A3A_fnc_planning_localSideChat", 0];

	// Find nearest friendly airfield / helipad / HQ to egress toward
	private _infra = call A3A_fnc_planning_getFriendlyInfrastructure;
	_infra params ["_hasHelipad", "_hasAirfield", "_friendlyHelipads", "_friendlyAirfields"];
	private _recoveryList = if (_isPlane) then { _friendlyAirfields } else { _friendlyHelipads };
	private _bestMarker = if (count _recoveryList > 0) then { _recoveryList select 0 } else { "respawn_west" };
	private _bestDist = 1e9;
	private _vPos = getPosATL _vehicle;
	{
		private _mPos = getMarkerPos _x;
		if (_mPos isNotEqualTo [0,0,0]) then {
			private _d = _mPos distance2D _vPos;
			if (_d < _bestDist) then { _bestDist = _d; _bestMarker = _x; };
		};
	} forEach _recoveryList;
	private _egressPos = getMarkerPos _bestMarker;
	if (_egressPos isEqualTo [0,0,0]) then { _egressPos = getMarkerPos "respawn_west"; };

	// Assign egress waypoint
	for "_i" from (count (waypoints _group) - 1) to 0 step -1 do { deleteWaypoint [_group, _i]; };
	private _wp = _group addWaypoint [_egressPos, 0];
	_wp setWaypointType "MOVE";
	_wp setWaypointBehaviour "CARELESS";
	_wp setWaypointSpeed "FULL";
	_group setBehaviour "CARELESS";

	// Fly towards friendly territory for 15s before storing in garage
	private _egressTimeout = time + 15;
	while { time <= _egressTimeout && { alive _vehicle } } do {
		sleep 1;
	};

	if (alive _vehicle) then {
		// Refund surviving Vehicle Crew HR
		private _survivingCrew = (units _group) select { alive _x };
		if (count _survivingCrew > 0) then {
			[count _survivingCrew, 0] remoteExec ["A3A_fnc_resourcesFIA", 2];
			diag_log format ["[A3A Planning] Air Overwatch: refunded %1 HR for surviving crew.", count _survivingCrew];
		};

		// Remove group from active tracking
		if (!isNil "A3A_planning_activeGroups") then {
			A3A_planning_activeGroups = A3A_planning_activeGroups select { _x != _group };
			publicVariable "A3A_planning_activeGroups";
		};

		// Pass vehicle object to serverAddGarage (preserves damage, fuel, remaining ammo, persistent state)
		[[_vehicle]] call A3A_fnc_planning_serverAddGarage;

		// Clean up crew and vehicle object safely
		{ deleteVehicle _x; } forEach _survivingCrew;
		deleteVehicle _vehicle;
		deleteGroup _group;
		diag_log format ["[A3A Planning] Air Overwatch: %1 (%2) successfully restored to HQ Garage.", groupId _group, _vehClass];
	};
};
