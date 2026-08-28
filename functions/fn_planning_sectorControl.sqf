/*
	    fn_planning_sectorControl.sqf
	    Runs on the server. Periodically monitors the active attack objective.
	    if all enemy forces within 150m are eliminated and auto-capture is enabled,
	    orders the nearest surviving squad to move to the central flag to seize the position.
	    Once a friendly unit reaches the flag (within 15m), triggers the native Antistasi capture event (A3A_fnc_markerChange)
	    and immediately processes surviving siege troops (refund or garrison).
	    if auto-capture is disabled, player retains manual capture responsibility, and this script
	    performs the post-capture garrisoning once the manual side change is detected on the next tick.
	    Cleans up all client-side map markers upon conclusion.
*/

if (!isServer) exitWith {};

diag_log "[A3A Ultimate Tweaks Extender] Starting flag-capture sector control loop...";


private _fnc_postCapture = {
	params [["_marker", "", [""]]];
	if (_marker == "") then {
		_marker = missionNamespace getVariable ["A3A_planning_objective", ""];
	};
	if (_marker == "") exitWith {
		diag_log "[A3A Planning Warning] _fnc_postCapture invoked with empty marker name.";
	};

	private _captureAction = missionNamespace getVariable ["A3A_tweak_siegeRefundOrGarrison", 1];

	if (_captureAction > 0 && {
		!isNil "A3A_planning_activeGroups" && {
			count A3A_planning_activeGroups > 0
		}
	}) then {
		private _totalRefundMoney = 0;
		private _totalRefundHR = 0;
		private _totalGarrisonedCount = 0;
		private _garrisonList = [];
		private _allRecoveredVehicles = [];

		{
			private _group = _x;
			if (!isNull _group && {
				{ alive _x } count (units _group) > 0
			}) then {
				// AIR_CREW groups manage their own recovery via fn_planning_airOverwatch.
				// Skip them here to avoid double-processing.
				private _role = _group getVariable ["siege_role", "ASSAULT"];
				if (_role == "AIR_CREW") then {
					diag_log format ["[A3A Planning] sectorControl: skipping AIR_CREW group %1 (managed by airOverwatch).", groupId _group];
				} else {
					private _costMoney = _group getVariable ["siege_costMoney", 0];
					private _costHR = _group getVariable ["siege_costHR", 0];
					private _originalCount = _group getVariable ["siege_originalCount", 0];

					private _aliveUnits = (units _group) select {
						alive _x
					};
					private _aliveCount = count _aliveUnits;

					if (_aliveCount > 0 && {
						_originalCount > 0
					}) then {
						// Collect vehicles driven/carried by this group (excluding static emplacements from garage recovery)
						private _groupVehicles = [];
						private _staticEmplacements = [];
						{
							private _veh = vehicle _x;
							if (_veh != _x && {
								alive _veh && {
									!(_veh in _groupVehicles) && {
										!(_veh in _staticEmplacements)
									}
								}
							}) then {
								if (_veh isKindOf "StaticWeapon") then {
									_staticEmplacements pushBack _veh;
								} else {
									_groupVehicles pushBack _veh;
								};
							};
						} forEach _aliveUnits;

						private _trackedStatic = _group getVariable ["siege_staticVehicle", objNull];
						if (!isNull _trackedStatic && { !(_trackedStatic in _staticEmplacements) }) then {
							_staticEmplacements pushBack _trackedStatic;
						};

						// --- Garrison mode ---
						if (_captureAction == 1) then {
							private _perUnitMoney = if (_originalCount > 0) then { _costMoney / _originalCount } else { 100 };
							private _perUnitHR = if (_originalCount > 0) then { _costHR / _originalCount } else { 1 };

							{
								if (alive _x) then {
									private _uType = _x getVariable ["unitType", typeOf _x];
									_garrisonList pushBack [_uType, _perUnitMoney, _perUnitHR];
									_totalGarrisonedCount = _totalGarrisonedCount + 1;
								};
							} forEach _aliveUnits;

							{
								_allRecoveredVehicles pushBack (typeOf _x);
							} forEach _groupVehicles;
						};

						// --- Refund mode ---
						if (_captureAction == 2) then {
							private _ratio = _aliveCount / _originalCount;
							_totalRefundMoney = _totalRefundMoney + round (_costMoney * _ratio);
							_totalRefundHR = _totalRefundHR + round (_costHR * _ratio);
						};

						// Clean up world objects (classnames already captured above)
						{
							deleteVehicle _x;
						} forEach _groupVehicles;
						{
							deleteVehicle _x;
						} forEach _staticEmplacements;
						{
							deleteVehicle _x;
						} forEach _aliveUnits;
						deleteGroup _group;
					};
				};
			};
		} forEach A3A_planning_activeGroups;

		// --- vehicle recovery ---
		if (count _allRecoveredVehicles > 0) then {
			diag_log format ["[A3A Planning] Recovering %1 siege vehicles to HQ Garage: %2", count _allRecoveredVehicles, _allRecoveredVehicles];
			[_allRecoveredVehicles] call A3A_fnc_planning_serverAddGarage;
		};

		private _markerDispName = markerText ("Dum" + _marker);
		if (_markerDispName == "") then { _markerDispName = markerText _marker; };
		if (_markerDispName == "" && !isNil "A3A_fnc_localizar") then { _markerDispName = [_marker] call A3A_fnc_localizar; };
		if (_markerDispName == "") then { _markerDispName = _marker; };

		// --- apply garrison (with Antistasi capacity capping & overflow refund) ---
		if (_captureAction == 1 && { _totalGarrisonedCount > 0 }) then {
			private _maxCapacity = if (!isNil "A3A_fnc_garrisonLimit") then {
				[_marker] call A3A_fnc_garrisonLimit
			} else {
					private _airports = missionNamespace getVariable ["airportsX", []];
					private _milbases = missionNamespace getVariable ["milbases", []];
					private _outposts = missionNamespace getVariable ["outposts", []];
					switch (true) do {
						case (_marker in _airports): { 40 };
						case (_marker in _milbases): { 30 };
						case (_marker in _outposts): { 20 };
						default { 20 };
					};
				};

				private _existingGarrison = if (!isNil "garrison") then { garrison getVariable [_marker, []] } else { [] };
				private _currentCount = count _existingGarrison;
				private _availableSlots = (_maxCapacity - _currentCount) max 0;

				private _unitsToGarrison = [];
				private _unitsOverflow = [];

				if (count _garrisonList <= _availableSlots) then {
					_unitsToGarrison = _garrisonList;
				} else {
					_unitsToGarrison = _garrisonList select [0, _availableSlots];
					_unitsOverflow = _garrisonList select [_availableSlots, (count _garrisonList) - _availableSlots];
				};

				if (count _unitsToGarrison > 0) then {
					private _classnamesToGarrison = _unitsToGarrison apply { _x select 0 };
					diag_log format ["[A3A Planning] Garrisoning %1 surviving siege troops at '%2' (Cap: %3, Existing: %4, Available: %5).", count _classnamesToGarrison, _marker, _maxCapacity, _currentCount, _availableSlots];
					[_classnamesToGarrison, teamPlayer, _marker, 2] remoteExec ["A3A_fnc_garrisonUpdate", 2];

					// If the zone is currently loaded by a player (spawner != 2), physically spawn the garrison units in the world immediately
					private _spawnerState = if (!isNil "spawner") then { spawner getVariable [_marker, 2] } else { 2 };
					if (_spawnerState != 2) then {
						diag_log format ["[A3A Planning] Zone '%1' is currently loaded (spawner=%2). Spawning %3 garrison units via createSDKGarrisonsTemp.", _marker, _spawnerState, count _classnamesToGarrison];
						[_marker, _classnamesToGarrison] spawn {
							params ["_marker", "_units"];
							{
								if (!isNil "A3A_fnc_createSDKGarrisonsTemp") then {
									[_marker, _x] remoteExec ["A3A_fnc_createSDKGarrisonsTemp", 2];
								};
								sleep 0.3;
							} forEach _units;
						};
					};
				};

				if (count _unitsOverflow > 0) then {
					private _overflowMoney = 0;
					private _overflowHR = 0;
					{
						_overflowMoney = _overflowMoney + (_x select 1);
						_overflowHR = _overflowHR + (_x select 2);
					} forEach _unitsOverflow;

					_overflowMoney = round _overflowMoney;
					_overflowHR = round _overflowHR;

					if (_overflowMoney > 0 || _overflowHR > 0) then {
						[_overflowHR, _overflowMoney] remoteExec ["A3A_fnc_resourcesFIA", 2];
						diag_log format ["[A3A Planning] Refunded %1 overflow siege troops (%2 HR, %3 €) exceeding garrison capacity at %4.", count _unitsOverflow, _overflowHR, _overflowMoney, _marker];
					};
				};

				private _msg = format ["Garrisoned %1 surviving siege troops at %2 (Capacity: %3/%4).", count _unitsToGarrison, _markerDispName, (count _unitsToGarrison + _currentCount) min _maxCapacity, _maxCapacity];
				if (count _unitsOverflow > 0) then {
					_msg = _msg + format [" Refunded %1 overflow troops.", count _unitsOverflow];
				};
				if (count _allRecoveredVehicles > 0) then {
					_msg = _msg + format [" Recovered %1 vehicles to HQ Garage.", count _allRecoveredVehicles];
				};

				[
					"Siege Garrison",
					_msg
				] remoteExec ["A3A_fnc_customHint", 0];
			};

		// --- apply refund ---
		if (_captureAction == 2 && {
			(_totalRefundMoney > 0 || {
				_totalRefundHR > 0
			})
		}) then {
			[_totalRefundHR, _totalRefundMoney] remoteExec ["A3A_fnc_resourcesFIA", 2];
			[
				"Siege Refund",
				format ["Refunded %1 € and %2 HR for surviving siege troops at %3.", _totalRefundMoney, _totalRefundHR, _markerDispName]
			] remoteExec ["A3A_fnc_customHint", 0];
		};

		A3A_planning_activeGroups = [];
		publicVariable "A3A_planning_activeGroups";
	};

	// Reset siege state unconditionally (even if no groups survived or action == 0)
	A3A_planning_objective = "";
	A3A_planning_assaultStarted = false;
	A3A_planning_captureTriggered = false;
	A3A_planning_stage = 1;

	[true] remoteExec ["A3A_fnc_planning_localCleanupMarkers", 0];

	diag_log format ["[A3A Planning] %1 captured - cleanup action %2 executed.", _marker, _captureAction];
};

// ---------------------------------------------------------------------------
// Main loop
// ---------------------------------------------------------------------------
while { true } do {
	sleep 5;

	if (call A3A_fnc_planning_isSiegeActive) then {
		private _marker = missionNamespace getVariable ["A3A_planning_objective", ""];
		if (_marker == "" || { !(_marker in allMapMarkers) }) then {
			A3A_planning_assaultStarted = false;
			continue;
		};
		private _side = sidesX getVariable [_marker, sideUnknown];
		private _targetPos = getMarkerPos _marker;

		// --- SCENARIO A: Sector has already been captured (e.g., manually by player) ---
		// Guard: if captureTriggered is true, the auto-capture inner spawn is still running
		// (or just finished) and will call _fnc_postCapture itself. Skip here to avoid
		// double-execution which would find activeGroups already empty and skip garrison/refund.
		if (_side == teamPlayer && { !(missionNamespace getVariable ["A3A_planning_captureTriggered", false]) }) then {
			[_marker] call _fnc_postCapture;
		} else {
			// --- SCENARIO B: Assault in progress ---

			// Get the active AO radius (using dynamic calculation: >=750m for airports, >=450m for milbases, etc.)
			private _aoRadius = [_marker] call A3A_fnc_planning_getAORadius;

			// Find physical flag object if present near marker
			private _flagObj = objNull;
			private _nearFlags = nearestObjects [_targetPos, ["FlagCarrierCore", "FlagPole_F", "FlagCarrier"], 250];
			if (count _nearFlags > 0) then {
				_flagObj = _nearFlags select 0;
			};
			private _actualFlagPos = if (!isNull _flagObj) then { getPosATL _flagObj } else { _targetPos };

			// Scan all relevant enemy defenders across the entire configured AO
			private _enemyUnits = allUnits select {
				alive _x && {
					(side (group _x) in [Occupants, Invaders] || side _x in [Occupants, Invaders]) && {
						!captive _x && {
							lifeState _x != "INCAPACITATED" && {
								!(_x getVariable ["incapacitated", false]) && {
									!(_x getVariable ["ACE_isUnconscious", false]) && {
										!(_x getVariable ["surrendered", false]) && {
											// Exclude high-altitude aircraft from ground AO defenders
											(isNull objectParent _x || !((vehicle _x) isKindOf "Air") || ((getPosATL _x) select 2) < 35) && {
												[_x, _marker] call A3A_fnc_planning_isInsideAO
											}
										}
									}
								}
							}
						}
					}
				}
			};
			private _totalEnemies = count _enemyUnits;

			// Core base defenders: enemies in immediate compound or marker area
			private _coreEnemies = _enemyUnits select {
				(_x distance2D _actualFlagPos < 150) || {
					if (!isNil "A3A_fnc_isWithinMarkerArea") then { [_x, _marker] call A3A_fnc_isWithinMarkerArea } else { false }
				}
			};

			private _aliveGroups = A3A_planning_activeGroups select {
				!isNull _x && {
					count (units _x select { alive _x }) > 0
				}
			};
			private _autoCapture = missionNamespace getVariable ["A3A_planning_autoCapture", true];

			// Include all viable ground troops (assault infantry squads, combat vehicles, and unmounted support teams)
			// to actively hunt down remaining enemy AI troops across the entire AO.
			private _clearingGroups = _aliveGroups select {
				private _role = _x getVariable ["siege_role", "ASSAULT"];
				private _isStaticDeployed = _x getVariable ["siege_isStaticDeployed", false];
				(_role in ["ASSAULT", "VEHICLE", "CREW", "INFANTRY"]) || (!_isStaticDeployed && { _role in ["MG", "MORTAR"] })
			};

			// Maintain aggressive assault momentum & extract infantry stuck on terrain/buildings
			{
				private _grp = _x;
				private _ldr = leader _grp;
				if (alive _ldr) then {
					private _assignedDest = _grp getVariable ["siege_clearingTarget", _actualFlagPos];
					private _lastPos = _grp getVariable ["siege_lastPos", [0, 0, 0]];
					private _stuckCount = _grp getVariable ["siege_stuckCount", 0];
					private _curPos = getPosATL _ldr;

					if (_curPos distance2D _lastPos < 2.5 && { _curPos distance2D _assignedDest > 20 }) then {
						_stuckCount = _stuckCount + 1;
						_grp setVariable ["siege_stuckCount", _stuckCount];

						if (_stuckCount >= 3) then { // Stuck for >= 15 seconds
							diag_log format ["[A3A Planning] Un-sticking squad %1 stuck near %2 moving to %3", groupId _grp, _curPos, _assignedDest];
							_grp setBehaviour "AWARE";
							_grp setSpeedMode "FULL";
							_grp setFormation "LINE";
							{
								if (alive _x && { vehicle _x == _x }) then {
									_x setUnitPos "UP";
									private _dest = _assignedDest vectorAdd [random 20 - 10, random 20 - 10, 0];
									_x doMove _dest;
								};
							} forEach (units _grp);
							_grp setVariable ["siege_stuckCount", 0];
						};
					} else {
						_grp setVariable ["siege_lastPos", _curPos];
						_grp setVariable ["siege_stuckCount", 0];
						if ((behaviour _ldr) in ["COMBAT", "STEALTH"]) then {
							_grp setSpeedMode "FULL";
							_grp setFormation "LINE";
						};
					};
				};
			} forEach _clearingGroups;

			// --- DYNAMIC AO PERIMETER CLEARING LOOP ---
			if (_totalEnemies > 0 && { count _coreEnemies > 0 }) then {
				// Group detected enemies into spatial/tactical clusters (within 45m of each other)
				private _clusters = [];
				{
					private _u = _x;
					private _uPos = getPosATL _u;
					private _veh = vehicle _u;
					private _isStatic = (_veh != _u) && { _veh isKindOf "StaticWeapon" };
					private _isVeh = (_veh != _u) && { !_isStatic };

					private _merged = false;
					{
						_x params ["_cPos", "_cUnits", "_cHasVeh", "_cHasStatic"];
						if (_uPos distance2D _cPos < 45) exitWith {
							_cUnits pushBack _u;
							if (_isVeh) then { _x set [2, true]; };
							if (_isStatic) then { _x set [3, true]; };
							_merged = true;
						};
					} forEach _clusters;

					if (!_merged) then {
						_clusters pushBack [_uPos, [_u], _isVeh, _isStatic, 0];
					};
				} forEach _enemyUnits;

				// Calculate centroid and priority score for each cluster
				{
					_x params ["_cPos", "_cUnits", "_cHasVeh", "_cHasStatic"];
					private _sumX = 0; private _sumY = 0; private _sumZ = 0;
					private _n = count _cUnits;
					{
						private _p = getPosATL _x;
						_sumX = _sumX + (_p select 0);
						_sumY = _sumY + (_p select 1);
						_sumZ = _sumZ + (_p select 2);
					} forEach _cUnits;
					private _centroid = [_sumX / _n, _sumY / _n, _sumZ / _n];
					_x set [0, _centroid];

					// Priority Scoring:
					// 1. Vehicles: +50
					// 2. Statics: +40
					// 3. Concentration: + (count * 6)
					// 4. Threats close to friendly troops (<150m): +30
					private _score = 40;
					if (_cHasVeh) then { _score = _score + 50; };
					if (_cHasStatic) then { _score = _score + 40; };
					if (_n >= 2) then { _score = _score + (_n * 6); };

					private _nearFriendly = false;
					{
						private _fLdr = leader _x;
						if (alive _fLdr && { (_centroid distance2D _fLdr) < 150 }) exitWith {
							_nearFriendly = true;
						};
					} forEach _clearingGroups;
					if (_nearFriendly) then { _score = _score + 30; };

					_x set [4, _score];
				} forEach _clusters;

				// Assign suitable assault squads to clear detected enemy clusters
				{
					private _group = _x;
					private _ldr = leader _group;
					if (alive _ldr) then {
						private _ldrPos = getPosATL _ldr;
						private _inAO = (_ldrPos distance2D _targetPos) <= (_aoRadius + 150);

						if (_inAO) then {
							private _curTarget = _group getVariable ["siege_clearingTarget", [0, 0, 0]];
							private _assignedTime = _group getVariable ["siege_clearingTime", 0];

							// Check if current assignment is still valid (alive enemies within 50m of target)
							private _enemiesNearTarget = {
								alive _x && {
									(side (group _x) in [Occupants, Invaders] || side _x in [Occupants, Invaders]) && {
										!captive _x && {
											!(_x getVariable ["incapacitated", false]) && {
												!(_x getVariable ["surrendered", false]) && {
													(_x distance2D _curTarget) < 50
												}
											}
										}
									}
								}
							} count allUnits;

							private _needsNewTarget = (_curTarget isEqualTo [0, 0, 0]) || { _enemiesNearTarget == 0 } || { (time - _assignedTime) > 30 };

							if (_needsNewTarget && { count _clusters > 0 }) then {
								// Find the best cluster for this squad
								private _bestCluster = [];
								private _bestScore = -1e9;

								{
									private _cluster = _x;
									_cluster params ["_cPos", "_cUnits", "_cHasVeh", "_cHasStatic", "_baseScore"];
									private _dist = _ldrPos distance2D _cPos;

									// Count other squads already clearing this cluster
									private _otherAssigned = 0;
									{
										if (_x != _group) then {
											private _otherTgt = _x getVariable ["siege_clearingTarget", [0, 0, 0]];
											if (_otherTgt distance2D _cPos < 45) then {
												_otherAssigned = _otherAssigned + 1;
											};
										};
									} forEach _clearingGroups;

									private _effScore = _baseScore - (_dist * 0.1) - (_otherAssigned * 35);
									if ((_group getVariable ["siege_role", "ASSAULT"]) == "VEHICLE" && { _cHasVeh || _cHasStatic }) then {
										_effScore = _effScore + 40;
									};
									if (_effScore > _bestScore) then {
										_bestScore = _effScore;
										_bestCluster = _cluster;
									};
								} forEach _clusters;

								if (count _bestCluster > 0) then {
									private _chosenPos = _bestCluster select 0;
									private _chosenUnits = _bestCluster select 1;

									_group setVariable ["siege_clearingTarget", _chosenPos, true];
									_group setVariable ["siege_clearingTime", time, true];
									_group setVariable ["siege_orderedToFlag", false, true];

									// Reveal enemies to squad
									{
										_group reveal [_x, 4];
									} forEach _chosenUnits;

									private _role = _group getVariable ["siege_role", "ASSAULT"];
									if (_role != "VEHICLE") then {
										for "_i" from (count (waypoints _group) - 1) to 0 step -1 do {
											deleteWaypoint [_group, _i];
										};
										private _wp = _group addWaypoint [_chosenPos, 0];
										_wp setWaypointType "SAD";
										_wp setWaypointBehaviour "COMBAT";
										_wp setWaypointCombatMode "RED";
										_wp setWaypointSpeed "FULL";
										_wp setWaypointCompletionRadius 25;
										[_group, _wp select 1] remoteExec ["A3A_fnc_planning_localSetCurrentWaypoint", groupOwner _group];

										_group setBehaviour "COMBAT";
										_group setCombatMode "RED";
										_group setSpeedMode "FULL";

										// Issue immediate movement command to all infantry units in the group
										{
											if (alive _x && { vehicle _x == _x }) then {
												[_x, _chosenPos] remoteExec ["A3A_fnc_planning_localDoMove", owner _x];
											};
										} forEach (units _group);
									};

									diag_log format ["[A3A Planning] Squad %1 dispatched to clear AO perimeter target at %2 (%3 enemies, score: %4).", groupId _group, _chosenPos, count _chosenUnits, _bestScore];
								};
							};
						};
					};
				} forEach _clearingGroups;
			} else {
				// --- STEP G: Base core cleared (0 core enemies remaining) ---
				if (_autoCapture && { count _clearingGroups > 0 }) then {
					// Prefer infantry squads to physically capture the central flag
					private _infantryGroups = _clearingGroups select { (_x getVariable ["siege_role", "ASSAULT"]) in ["ASSAULT", "INFANTRY"] };
					private _candidateGroups = if (count _infantryGroups > 0) then { _infantryGroups } else { _clearingGroups };

					private _sortedGroups = [_candidateGroups, [], {
						(leader _x) distance2D _actualFlagPos
					}, "ASCEND"] call BIS_fnc_sortBy;
					private _closestGroup = _sortedGroups select 0;

					// Order closest squad to move onto the flag in CARELESS / FULL sprint
					if (_closestGroup getVariable ["siege_orderedToFlag", false] isNotEqualTo true) then {
						_closestGroup setVariable ["siege_orderedToFlag", true, true];
						diag_log format ["[A3A Planning] Base core cleared (0 core enemies, %1 total). Ordering squad %2 to seize flag at %3.", _totalEnemies, groupId _closestGroup, _actualFlagPos];

						for "_i" from (count (waypoints _closestGroup) - 1) to 0 step -1 do {
							deleteWaypoint [_closestGroup, _i];
						};
						private _wp = _closestGroup addWaypoint [_actualFlagPos, 0];
						_wp setWaypointType "MOVE";
						_wp setWaypointBehaviour "CARELESS";
						_wp setWaypointSpeed "FULL";
						[_closestGroup, _wp select 1] remoteExec ["A3A_fnc_planning_localSetCurrentWaypoint", groupOwner _closestGroup];

						_closestGroup setBehaviour "CARELESS";
						_closestGroup setSpeedMode "FULL";
					};

					// Refresh movement orders towards the flag
					private _orderedVehicles = [];
					{
						private _veh = vehicle _x;
						if (_veh != _x) then {
							if !(_veh in _orderedVehicles) then {
								_orderedVehicles pushBack _veh;
								private _driver = driver _veh;
								if (!isNull _driver && { alive _driver }) then {
									[_driver, _actualFlagPos] remoteExec ["A3A_fnc_planning_localDoMove", owner _driver];
								};
							};
						} else {
							[_x, _actualFlagPos] remoteExec ["A3A_fnc_planning_localDoMove", owner _x];
						};
					} forEach (units _closestGroup);

					// Check if any friendly unit has reached the flag compound (within 45m or marker area)
					private _nearFlag = {
						alive _x && {
							(side (group _x) == teamPlayer || side _x == teamPlayer) && {
								!(_x getVariable ["incapacitated", false]) && {
									(_x distance2D _actualFlagPos < 45) || {
										(_x distance2D _targetPos < 45) || {
											if (!isNil "A3A_fnc_isWithinMarkerArea") then { [_x, _marker] call A3A_fnc_isWithinMarkerArea } else { false }
										}
									}
								}
							}
						}
					} count allUnits;

					if (_nearFlag > 0 && { !(missionNamespace getVariable ["A3A_planning_captureTriggered", false]) }) then {
						diag_log format ["[A3A Planning] Rebel unit reached flag area. Seizing %1...", _marker];

						A3A_planning_captureTriggered = true;
						publicVariable "A3A_planning_captureTriggered";

						// Put all surviving forces on GUARD waypoint at objective
						{
							if (!isNull _x && { count (units _x select { alive _x }) > 0 }) then {
								for "_i" from (count (waypoints _x) - 1) to 0 step -1 do {
									deleteWaypoint [_x, _i];
								};
								private _wp = _x addWaypoint [_targetPos, 0];
								_wp setWaypointType "GUARD";
								_x setBehaviour "AWARE";
								_x setCombatMode "RED";
								[_x, _wp select 1] remoteExec ["A3A_fnc_planning_localSetCurrentWaypoint", groupOwner _x];
							};
						} forEach _aliveGroups;

						[teamPlayer, _marker] spawn A3A_fnc_markerChange;
						[true] remoteExec ["A3A_fnc_planning_localCleanupMarkers", 0];

						[_marker, _fnc_postCapture] spawn {
							params ["_marker", "_fnc_postCapture"];
							// Allow up to 30s for A3A_fnc_markerChange to propagate the side variable change.
							// 10s was too short on busy/laggy servers, causing postCapture to run before
							// sidesX confirmed ownership and causing Scenario A to double-fire on the next tick.
							private _timeout = time + 30;
							while { (sidesX getVariable [_marker, sideUnknown]) != teamPlayer && { time < _timeout } } do {
								sleep 0.5;
							};
							if ((sidesX getVariable [_marker, sideUnknown]) == teamPlayer) then {
								[_marker] call _fnc_postCapture;
							};
						};
					};
				};

				// If autoCapture is false, put assault groups on GUARD around objective
				if (!_autoCapture && { count _clearingGroups > 0 }) then {
					{
						if (_x getVariable ["siege_guardingCleared", false] isNotEqualTo true) then {
							_x setVariable ["siege_guardingCleared", true, true];
							for "_i" from (count (waypoints _x) - 1) to 0 step -1 do {
								deleteWaypoint [_x, _i];
							};
							private _wp = _x addWaypoint [_targetPos, 0];
							_wp setWaypointType "GUARD";
							_x setBehaviour "AWARE";
							_x setCombatMode "RED";
							[_x, _wp select 1] remoteExec ["A3A_fnc_planning_localSetCurrentWaypoint", groupOwner _x];
						};
					} forEach _clearingGroups;
				};
			};

			// Check for siege failure
			if (count _aliveGroups == 0 && { count A3A_planning_activeGroups > 0 }) then {
				diag_log format ["[A3A Planning] Siege failed for %1. All forces eliminated.", _marker];

				A3A_planning_activeGroups = [];
				publicVariable "A3A_planning_activeGroups";

				A3A_planning_assaultStarted = false;
				publicVariable "A3A_planning_assaultStarted";

				A3A_planning_stage = 1;

				[
					"Siege Failed",
					"All assault forces have been eliminated. The planning markers remain active for reinforcement waves."
				] remoteExec ["A3A_fnc_customHint", 0];
			};
		};
	};
};