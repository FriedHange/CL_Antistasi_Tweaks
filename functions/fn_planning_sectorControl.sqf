/*
    fn_planning_sectorControl.sqf
    Runs on the server. Periodically monitors the active attack objective.
    If all enemy forces within 150m are eliminated and auto-capture is enabled,
    orders the nearest surviving squad to move to the central flag to seize the position.
    Once a friendly unit reaches the flag (within 15m), triggers the native Antistasi capture event (A3A_fnc_markerChange)
    and converts all surviving units into the persistent garrison for that location.
    If auto-capture is disabled, player retains manual capture responsibility, and this script
    performs the post-capture garrisoning once the manual side change is detected.
    Cleans up all client-side map markers upon conclusion.
*/

if (!isServer) exitWith {};

diag_log "[A3A Ultimate Tweaks Extender] Starting flag-capture sector control loop...";

while {true} do {
    sleep 8;

    if (!isNil "A3A_planning_objective" && {A3A_planning_objective != "" && {A3A_planning_assaultStarted}}) then {
        private _marker = A3A_planning_objective;
        private _side = sidesX getVariable [_marker, sideUnknown];
        private _targetPos = getMarkerPos _marker;

        // --- SCENARIO A: Sector has already been captured (e.g., manually by player or other forces) ---
        if (_side == teamPlayer) then {
            private _nearbyEnemies = { alive _x && {side _x in [Occupants, Invaders]} && {_x distance2D _targetPos < 500} } count allUnits;
            if (_nearbyEnemies > 0) then {
                // Captured but not secure yet - defenders stay put; re-check again next tick.
            } else {
                private _captureAction = missionNamespace getVariable ["A3A_tweak_siegeRefundOrGarrison", 1];
                if (_captureAction > 0 && {!isNil "A3A_planning_activeGroups" && {count A3A_planning_activeGroups > 0}}) then {
                private _totalRefundMoney = 0;
                private _totalRefundHR = 0;
                private _totalGarrisonedCount = 0;
                private _garrisonList = [];
                private _allRecoveredVehicles = [];

                {
                    private _group = _x;
                    if (!isNull _group && {count (units _group) > 0}) then {
                        private _costMoney = _group getVariable ["siege_costMoney", 0];
                        private _costHR = _group getVariable ["siege_costHR", 0];
                        private _originalCount = _group getVariable ["siege_originalCount", 0];
                        
                        private _aliveUnits = (units _group) select { alive _x };
                        private _aliveCount = count _aliveUnits;
                        
                        if (_aliveCount > 0 && {_originalCount > 0}) then {
                            private _groupVehicles = [];
                            {
                                private _veh = vehicle _x;
                                if (_veh != _x && {alive _veh && {!(_veh in _groupVehicles)}}) then {
                                    _groupVehicles pushBack _veh;
                                };
                            } forEach _aliveUnits;

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

                            if (_captureAction == 2) then {
                                private _ratio = _aliveCount / _originalCount;
                                _totalRefundMoney = _totalRefundMoney + round (_costMoney * _ratio);
                                _totalRefundHR = _totalRefundHR + round (_costHR * _ratio);
                            };
                            
                            // Clean up physical units/vehicles
                            { deleteVehicle _x; } forEach _groupVehicles;
                            { deleteVehicle _x; } forEach _aliveUnits;
                            deleteGroup _group;
                        };
                    };
                } forEach A3A_planning_activeGroups;

                // Add recovered vehicles to HQ Garage
                if (count _allRecoveredVehicles > 0) then {
                    [_allRecoveredVehicles] call A3A_fnc_planning_serverAddGarage;
                };

                // Apply manual capture garrisoning
                if (_captureAction == 1 && {_totalGarrisonedCount > 0}) then {
                    private _currentGarrison = garrison getVariable [_marker, []];
                    _currentGarrison append _garrisonList;
                    garrison setVariable [_marker, _currentGarrison, true];

                    if (isServer) then {
                        [garrison, _marker] remoteExec ["A3A_fnc_garrisonUpdate", 2];
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

                // Apply manual capture refund
                if (_captureAction == 2 && {(_totalRefundMoney > 0 || {_totalRefundHR > 0})}) then {
                    [_totalRefundHR, _totalRefundMoney] remoteExec ["A3A_fnc_resourcesFIA", 2];
                    [
                        "Siege Refund",
                        format ["Refunded %1 € and %2 HR for surviving siege troops at %3.", _totalRefundMoney, _totalRefundHR, markerText ("Dum" + _marker)]
                    ] remoteExec ["A3A_fnc_customHint", 0];
                };
                
                A3A_planning_activeGroups = [];
                publicVariable "A3A_planning_activeGroups";
            };

            A3A_planning_objective = "";
            A3A_planning_assaultStarted = false;
            A3A_planning_captureTriggered = false;
            A3A_planning_stage = 1;
            
            // Clean up markers on clients
            [true] remoteExec ["A3A_fnc_planning_localCleanupMarkers", 0];
            };
        } else {
            // --- SCENARIO B: Assault in progress (enemies still own the position) ---

            // Count remaining enemy defenders within the AO (150m)
            private _totalEnemies = { alive _x && {side _x == Occupants || {side _x == Invaders}} && {_x distance2D _targetPos < 150} } count allUnits;
            
            private _aliveGroups = A3A_planning_activeGroups select { !isNull _x && {count (units _x) > 0} };
            private _autoCapture = missionNamespace getVariable ["A3A_planning_autoCapture", true];

            // Only ASSAULT (and vehicle CREW) squads are ever eligible to physically walk onto and
            // seize the flag. Support elements (MG/Mortar emplacement teams and armed VehicleSquad
            // overwatch) must stay on their scripted standoff behavior and are never pulled off
            // station to rush the objective — pulling from the full _aliveGroups list here was
            // causing random support squads to receive a raw MOVE waypoint straight onto the flag,
            // and letting the objective get "captured" (and the siege reset) the moment a support
            // group happened to be geometrically closest, well before it had done its job.
            private _captureEligibleGroups = _aliveGroups select {
                (_x getVariable ["siege_role", "ASSAULT"]) in ["ASSAULT", "CREW"]
            };

            if (_autoCapture && {_totalEnemies == 0}) then {
                // All enemies within 150m are eliminated! Get nearest surviving eligible group
                if (count _captureEligibleGroups > 0) then {
                    // Find group closest to the flag
                    private _sortedGroups = [_captureEligibleGroups, [], { (leader _x) distance2D _targetPos }, "ASCEND"] call BIS_fnc_sortBy;
                    private _closestGroup = _sortedGroups select 0;
                    
                    // Order them to move directly to the flag position
                    if (_closestGroup getVariable ["siege_orderedToFlag", false] isNotEqualTo true) then {
                        _closestGroup setVariable ["siege_orderedToFlag", true, true];
                        diag_log format ["[A3A Planning] All enemies eliminated. Ordering group %1 to seize the flag at %2.", groupID _closestGroup, _targetPos];
                        
                        // Clear waypoints and assign a MOVE waypoint directly on top of the flag
                        for "_i" from (count (waypoints _closestGroup) - 1) to 1 step -1 do {
                            deleteWaypoint [_closestGroup, _i];
                        };
                        private _wp = _closestGroup addWaypoint [_targetPos, 0];
                        _wp setWaypointType "MOVE";
                        [_closestGroup, _wp select 1] remoteExec ["A3A_fnc_planning_localSetCurrentWaypoint", groupOwner _closestGroup];
                        
                        {
                            [_x, _targetPos] remoteExec ["A3A_fnc_planning_localDoMove", owner _x];
                        } forEach (units _closestGroup);
                    };

                    // Check if any friendly unit has reached the flag (within 15m)
                    private _nearFlag = { alive _x && {side _x == teamPlayer} && {_x distance2D _targetPos < 15} } count allUnits;
                    if (_nearFlag > 0 && {!(missionNamespace getVariable ["A3A_planning_captureTriggered", false])}) then {
                        diag_log format ["[A3A Planning] Rebel unit reached flag area. Seizing %1...", _marker];

                        A3A_planning_captureTriggered = true;
                        publicVariable "A3A_planning_captureTriggered";

                        // Order surviving forces to hold and defend the objective instead of
                        // being deleted immediately - Scenario A (above) performs the actual
                        // garrison/refund conversion on a later tick, once the area is
                        // confirmed clear of remaining enemies.
                        {
                            if (!isNull _x && {count (units _x) > 0}) then {
                                for "_i" from (count (waypoints _x) - 1) to 0 step -1 do { deleteWaypoint [_x, _i]; };
                                private _wp = _x addWaypoint [_targetPos, 0];
                                _wp setWaypointType "GUARD";
                                _x setBehaviour "AWARE";
                                _x setCombatMode "RED";
                                [_x, _wp select 1] remoteExec ["A3A_fnc_planning_localSetCurrentWaypoint", groupOwner _x];
                            };
                        } forEach _aliveGroups;

                        // Trigger the native Antistasi sector capture function (side flip only)
                        [teamPlayer, _marker] spawn A3A_fnc_markerChange;
                        // Clean up markers on clients
                        [true] remoteExec ["A3A_fnc_planning_localCleanupMarkers", 0];
                    };
                };
            } else {
                // If there are no surviving rebel groups and target is still enemy-controlled, the siege has failed
                if (count _aliveGroups == 0 && {count A3A_planning_activeGroups > 0}) then {
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
