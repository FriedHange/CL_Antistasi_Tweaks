/*
    fn_planning_sectorControl.sqf
    Runs on the server. Periodically monitors the active attack objective.
    If all enemy forces within 150m are eliminated and auto-capture is enabled,
    orders the nearest surviving squad to move to the central flag to seize the position.
    Once a friendly unit reaches the flag (within 15m), triggers the native Antistasi capture event
    (A3A_fnc_markerChange) and IMMEDIATELY garrisons or refunds all surviving siege forces -
    no delayed cleanup. Antistasi's normal garrison system takes over defense of the objective
    from that point on.
    If auto-capture is disabled, player retains manual capture responsibility, and this script
    performs the same immediate garrisoning/refund the next time it notices the marker already
    flipped to the player's side.
    Cleans up all client-side map markers upon conclusion.
*/

if (!isServer) exitWith {};

diag_log "[A3A Ultimate Tweaks Extender] Starting flag-capture sector control loop...";

// Shared handler: garrisons or refunds every currently active siege group and clears them.
// Used both for the scripted auto-capture path and for a manually/externally captured marker.
private _fnc_processCaptureRewards = {
    params ["_marker"];

    if (isNil "A3A_planning_activeGroups" || {count A3A_planning_activeGroups == 0}) exitWith {};

    private _captureAction = missionNamespace getVariable ["A3A_tweak_siegeRefundOrGarrison", 1];

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

                    { _allRecoveredVehicles pushBack (typeOf _x); } forEach _groupVehicles;
                };

                if (_captureAction == 2) then {
                    private _ratio = _aliveCount / _originalCount;
                    _totalRefundMoney = _totalRefundMoney + round (_costMoney * _ratio);
                    _totalRefundHR = _totalRefundHR + round (_costHR * _ratio);
                };

                { deleteVehicle _x; } forEach _groupVehicles;
                { deleteVehicle _x; } forEach _aliveUnits;
                deleteGroup _group;
            };
        };
    } forEach A3A_planning_activeGroups;

    if (count _allRecoveredVehicles > 0) then {
        [_allRecoveredVehicles] call A3A_fnc_planning_serverAddGarage;
    };

    if (_captureAction == 1 && {_totalGarrisonedCount > 0}) then {
        private _currentGarrison = garrison getVariable [_marker, []];
        _currentGarrison append _garrisonList;
        garrison setVariable [_marker, _currentGarrison, true];

        [garrison, _marker] remoteExec ["A3A_fnc_garrisonUpdate", 2];

        private _msg = format ["Garrisoned %1 surviving siege troops at %2.", _totalGarrisonedCount, markerText ("Dum" + _marker)];
        if (count _allRecoveredVehicles > 0) then {
            _msg = _msg + format [" Recovered %1 vehicles to HQ Garage.", count _allRecoveredVehicles];
        };

        ["Siege Garrison", _msg] remoteExec ["A3A_fnc_customHint", 0];
    };

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

// Shared handler: resets planning state and clears client markers. Called right after rewards
// have been processed, so no leftover siege groups are ever waiting around for a later tick.
private _fnc_resetPlanningState = {
    A3A_planning_objective = "";
    A3A_planning_assaultStarted = false;
    A3A_planning_captureTriggered = false;
    A3A_planning_stage = 1;

    [true] remoteExec ["A3A_fnc_planning_localCleanupMarkers", 0];
};

while {true} do {
    sleep 8;

    if (!isNil "A3A_planning_objective" && {A3A_planning_objective != "" && {A3A_planning_assaultStarted}}) then {
        private _marker = A3A_planning_objective;
        private _side = sidesX getVariable [_marker, sideUnknown];
        private _targetPos = getMarkerPos _marker;

        // --- SCENARIO A: Sector was found already captured through some path outside this
        // script's own capture confirmation below (e.g. manually by player action while
        // auto-capture was disabled). Process any leftover siege forces immediately. ---
        if (_side == teamPlayer) then {
            [_marker] call _fnc_processCaptureRewards;
            call _fnc_resetPlanningState;

            diag_log format ["[A3A Planning] %1 found already captured - reward processing executed immediately.", _marker];
        } else {
            // --- SCENARIO B: Assault in progress (enemies still own the position) ---

            // Count remaining enemy defenders within the AO (150m)
            private _totalEnemies = { alive _x && {side _x == Occupants || {side _x == Invaders}} && {_x distance2D _targetPos < 150} } count allUnits;

            private _aliveGroups = A3A_planning_activeGroups select { !isNull _x && {count (units _x) > 0} };
            private _autoCapture = missionNamespace getVariable ["A3A_planning_autoCapture", true];

            // Only ASSAULT (and vehicle CREW) squads are ever eligible to physically walk onto and
            // seize the flag. Support elements (MG/Mortar emplacement teams and armed VehicleSquad
            // overwatch) must stay on their scripted standoff behavior.
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

                        // Trigger the native Antistasi sector capture function (side flip only)
                        [teamPlayer, _marker] spawn A3A_fnc_markerChange;

                        // Immediately garrison/refund surviving siege forces and reset planning
                        // state - no waiting for nearby enemies to clear or for a later tick.
                        // Antistasi's normal garrison system takes over defense from here.
                        [_marker] call _fnc_processCaptureRewards;
                        call _fnc_resetPlanningState;

                        diag_log format ["[A3A Planning] %1 captured - reward processing executed immediately.", _marker];
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
