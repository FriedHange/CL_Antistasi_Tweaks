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
	params ["_marker"];

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
				count (units _group) > 0
			}) then {
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
					// Collect vehicles driven/carried by this group
					private _groupVehicles = [];
					{
						private _veh = vehicle _x;
						if (_veh != _x && {
							alive _veh && {
								!(_veh in _groupVehicles)
							}
						}) then {
							_groupVehicles pushBack _veh;
						};
					} forEach _aliveUnits;

					                    // --- Garrison mode ---
					if (_captureAction == 1) then {
						{
							if (alive _x) then {
								_garrisonList pushBack (typeOf _x);
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
					} forEach _aliveUnits;
					deleteGroup _group;
				};
			};
		} forEach A3A_planning_activeGroups;

		        // --- vehicle recovery ---
		if (count _allRecoveredVehicles > 0) then {
			diag_log format ["[A3A Planning] Recovering %1 siege vehicles to HQ Garage: %2", count _allRecoveredVehicles, _allRecoveredVehicles];
			[_allRecoveredVehicles] call A3A_fnc_planning_serverAddGarage;
		};

		        // --- apply garrison ---
		        // We call A3A_fnc_garrisonUpdate once per unit type on the server (machine 2).
		        // This is the same pathway used by Antistasi's own garrison recruiter (fn_garrisonAdd.sqf)
		        // and correctly handles:
		        //   • Writing to the new-style structured garrison variables (%1_garrison, %1_requested)
		        //   • Immediately spawning the unit if the location is currently loaded (spawner == 2)
		        //   • Deferring to natural spawn if the location is currently unloaded
		if (_captureAction == 1 && {
			_totalGarrisonedCount > 0
		}) then {
			diag_log format ["[A3A Planning] Garrisoning %1 surviving siege troops at '%2' via A3A_fnc_garrisonUpdate.", _totalGarrisonedCount, _marker];
			[_garrisonList, teamPlayer, _marker, 2] remoteExec ["A3A_fnc_garrisonUpdate", 2];

			// If the zone is currently loaded, spawn each garrison unit individually using
			// A3A_fnc_createSDKGarrisonsTemp — the same function fn_garrisonAdd.sqf uses when
			// a player manually garrisons a unit into an already-loaded location.
			// This spawns only infantry/crew without touching the flag, statics, crates, or
			// any other world objects placed at the captured base.
			if ((spawner getVariable [_marker, 2]) != 2) then {
				diag_log format ["[A3A Planning] Zone '%1' is currently loaded (spawner=%2). Spawning %3 garrison units via createSDKGarrisonsTemp.", _marker, spawner getVariable _marker, count _garrisonList];
				[_marker, _garrisonList] spawn {
					params ["_marker", "_garrisonList"];
					{
						[_marker, _x] remoteExec ["A3A_fnc_createSDKGarrisonsTemp", 2];
						sleep 0.5;
					} forEach _garrisonList;
				};
			};

			private _msg = format ["Garrisoned %1 surviving siege troops at %2.", _totalGarrisonedCount, markerText ("Dum" + _marker)];
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
				format ["Refunded %1 € and %2 HR for surviving siege troops at %3.", _totalRefundMoney, _totalRefundHR, markerText ("Dum" + _marker)]
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
	sleep 8;

	if (!isNil "A3A_planning_objective" && {
		A3A_planning_objective != "" && {
			A3A_planning_assaultStarted
		}
	}) then {
		private _marker = A3A_planning_objective;
		private _side = sidesX getVariable [_marker, sideUnknown];
		private _targetPos = getMarkerPos _marker;

		        // --- SCENARIO A: Sector has already been captured (e.g., manually by player) ---
		        // This catches cases where the player seizes the flag manually before our AI
		        // gets to it, or any external capture that changes the side to teamPlayer.
		if (_side == teamPlayer) then {
			[_marker] call _fnc_postCapture;
		} else {
			// --- SCENARIO B: Assault in progress (enemies still own the position) ---

			            // count remaining enemy defenders within the AO (150m)
			private _totalEnemies = {
				alive _x && {
					side _x == Occupants || {
						side _x == Invaders
					}
				} && {
					_x distance2D _targetPos < 150
				}
			} count allUnits;

			private _aliveGroups = A3A_planning_activeGroups select {
				!isNull _x && {
					count (units _x) > 0
				}
			};
			private _autoCapture = missionNamespace getVariable ["A3A_planning_autoCapture", true];

			            // Only ASSAULT (and vehicle crew) squads are ever eligible to physically walk onto and
			private _hasAssaultOrCrew = {
				(_x getVariable ["siege_role", "ASSAULT"]) in ["ASSAULT", "CREW"]
			} count _aliveGroups > 0;

			private _captureEligibleRoles = if (_hasAssaultOrCrew) then { ["ASSAULT", "CREW"] } else { ["ASSAULT", "CREW", "VEHICLE"] };

			private _captureEligibleGroups = _aliveGroups select {
				(_x getVariable ["siege_role", "ASSAULT"]) in _captureEligibleRoles
			};

			if (_autoCapture && {
				_totalEnemies == 0
			}) then {
				// All enemies within 150m are eliminated! get nearest surviving eligible group
				if (count _captureEligibleGroups > 0) then {
					// find group closest to the flag
					private _sortedGroups = [_captureEligibleGroups, [], {
						(leader _x) distance2D _targetPos
					}, "ASCEND"] call BIS_fnc_sortBy;
					private _closestGroup = _sortedGroups select 0;

					                    // Order them to move directly to the flag position
					if (_closestGroup getVariable ["siege_orderedToFlag", false] isNotEqualTo true) then {
						_closestGroup setVariable ["siege_orderedToFlag", true, true];
						diag_log format ["[A3A Planning] All enemies eliminated. Ordering group %1 to seize the flag at %2.", groupId _closestGroup, _targetPos];

						                        // Clear waypoints and assign a move waypoint directly on top of the flag
						for "_i" from (count (waypoints _closestGroup) - 1) to 1 step -1 do {
							deleteWaypoint [_closestGroup, _i];
						};
						private _wp = _closestGroup addWaypoint [_targetPos, 0];
						_wp setWaypointType "MOVE";
						_wp setWaypointBehaviour "CARELESS";
						_wp setWaypointSpeed "FULL";
						[_closestGroup, _wp select 1] remoteExec ["A3A_fnc_planning_localSetCurrentWaypoint", groupOwner _closestGroup];

						_closestGroup setBehaviour "CARELESS";
						_closestGroup setSpeedMode "FULL";
					};

					// Refresh movement orders for all units in the closest group every loop tick
					private _orderedVehicles = [];
					{
						private _veh = vehicle _x;
						if (_veh != _x) then {
							if !(_veh in _orderedVehicles) then {
								_orderedVehicles pushBack _veh;
								private _driver = driver _veh;
								if (!isNull _driver && { alive _driver }) then {
									[_driver, _targetPos] remoteExec ["A3A_fnc_planning_localDoMove", owner _driver];
								};
							};
						} else {
							[_x, _targetPos] remoteExec ["A3A_fnc_planning_localDoMove", owner _x];
						};
					} forEach (units _closestGroup);

					                    // Check if any friendly unit has reached the flag (within 15m)
					private _nearFlag = {
						alive _x && {
							side _x == teamPlayer
						} && {
							_x distance2D _targetPos < 15
						}
					} count allUnits;
					if (_nearFlag > 0 && {
						!(missionNamespace getVariable ["A3A_planning_captureTriggered", false])
					}) then {
						diag_log format ["[A3A Planning] Rebel unit reached flag area. Seizing %1...", _marker];

						A3A_planning_captureTriggered = true;
						publicVariable "A3A_planning_captureTriggered";

						                        // Put all surviving forces on a GUARD waypoint at the objective
						                        // so they hold briefly while markerChange fires and cleans up.
						{
							if (!isNull _x && {
								count (units _x) > 0
							}) then {
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

						                        // Trigger the native Antistasi sector capture (side flip)
						[teamPlayer, _marker] spawn A3A_fnc_markerChange;

						                        // Clean up map markers on clients immediately
						[true] remoteExec ["A3A_fnc_planning_localCleanupMarkers", 0];

						                        // --- ISSUE 1 FIX: Process survivors immediately ---
						                        // markerChange runs asynchronously (spawn), so wait a brief moment
						                        // for the side variable to be written before processing.
						                        // We call _fnc_postCapture in a short-delay spawn so the main
						                        // loop does not block, but survivors are processed on this same
						                        // tick rather than waiting up to 8s for the next iteration.
						[_marker, _fnc_postCapture] spawn {
							params ["_marker", "_fnc_postCapture"];
							// Wait up to 5s for markerChange to flip the side variable
							private _timeout = time + 5;
							waitUntil {
								sleep 0.5;
								(sidesX getVariable [_marker, sideUnknown]) == teamPlayer || {
									time > _timeout
								}
							};
							[_marker] call _fnc_postCapture;
						};
					};
				};
			} else {
				// if there are no surviving rebel groups and target is still enemy-controlled, the siege has failed
				if (count _aliveGroups == 0 && {
					count A3A_planning_activeGroups > 0
				}) then {
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
};