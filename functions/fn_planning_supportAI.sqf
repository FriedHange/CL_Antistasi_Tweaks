/*
    fn_planning_supportAI.sqf
    Handles MG and Mortar support AI loops with dynamic threat tracking and re-positioning.
    Runs on the server.
*/

params [
    ["_group", groupNull, [groupNull]],
    ["_type", "", [""]], // "MG", "Mortar", "MG_FALLBACK", "Mortar_FALLBACK"
    ["_targetMarker", "", [""]],
    ["_targetPos", [0,0,0], [[]]]
];

if (isNull _group) exitWith {};

// Wait for group units to sync to the server (multiplayer network safety)
private _syncRetries = 0;
while {count (units _group) == 0 && {_syncRetries < 30}} do {
    sleep 0.5;
    _syncRetries = _syncRetries + 1;
};

// Wait for leader
private _leadRetries = 0;
while {isNull (leader _group) && {_leadRetries < 20}} do {
    sleep 0.5;
    _leadRetries = _leadRetries + 1;
};

if (isNull (leader _group) || {count (units _group) == 0}) exitWith {
    diag_log format ["[A3A Ultimate Tweaks Extender] Support AI aborted: sync failed for group %1.", _group];
};

// Take full control of the group's orders now that specialized support AI is active.
// Clear the fallback HOLD waypoint from spawn so it can never later compete with
// the standoff positioning managed by this loop.
for "_i" from (count (waypoints _group) - 1) to 0 step -1 do {
    deleteWaypoint [_group, _i];
};

diag_log format ["[A3A Ultimate Tweaks Extender] Support AI started for group: %1, Type: %2", groupID _group, _type];

private _isMortar = _type in ["Mortar", "Mortar_FALLBACK"];
private _sidePrefix = if (teamPlayer == west) then { "B" } else { if (teamPlayer == east) then { "O" } else { "I" } };

// Effective standoff ranges. Mortars sit well back for indirect fire, MGs need LOS at closer range.
private _idealDist    = if (_isMortar) then { 700 } else { 150 };
private _minDist      = if (_isMortar) then { 400 } else { 60  };
private _maxDist       = if (_isMortar) then { 900 } else { 300 };
private _dangerDist    = if (_isMortar) then { 300 } else { 50  };  // Fall back if enemies reach this close to US
private _quietTimeout   = 45;                                       // Creep closer if no contacts near the AO for this long

// Resolve the static weapon classname. Checks every entry in the faction's configured list
// (not just the first) so modded factions with a partially-invalid list still work correctly.
private _fnc_resolveStatic = {
    params ["_key", "_fallback"];
    private _list = A3A_faction_reb getOrDefault [_key, []];
    private _found = "";
    {
        if (!isNil "_x" && {_x != "" && {isClass (configFile >> "CfgVehicles" >> _x)}}) exitWith {
            _found = _x;
        };
    } forEach _list;
    if (_found == "") then {
        _found = if (isClass (configFile >> "CfgVehicles" >> _fallback)) then { _fallback } else { "I_HMG_01_high_F" };
    };
    _found
};

private _staticClass = if (_isMortar) then {
    ["staticMortars", _sidePrefix + "_Mortar_01_F"] call _fnc_resolveStatic
} else {
    ["staticMGs", _sidePrefix + "_HMG_01_high_F"] call _fnc_resolveStatic
};

if (_staticClass == "" || {!isClass (configFile >> "CfgVehicles" >> _staticClass)}) exitWith {
    diag_log "[A3A Ultimate Tweaks Extender] Support AI failed: no valid static classname found (vanilla or modded).";
};

diag_log format ["[A3A Ultimate Tweaks Extender] Support group %1 resolved static class: %2", groupID _group, _staticClass];

private _lastFireTime = 0;
private _currentDist = _idealDist;
private _staticVeh = objNull;
private _done = false;

while {!_done} do {

    if (!alive (leader _group) || {count (units _group) == 0}) exitWith { _done = true; };
    if ((sidesX getVariable [_targetMarker, sideUnknown]) == teamPlayer) exitWith { _done = true; };

    // Tear down any static from a previous cycle before relocating
    if (!isNull _staticVeh) then {
        { unassignVehicle _x; [_x] orderGetIn false; } forEach (crew _staticVeh);
        deleteVehicle _staticVeh;
        _staticVeh = objNull;
        sleep 1;
    };

    private _leader = leader _group;

    // --- 1. Move to standoff positioning distance ---
    private _stagingPos = getPosATL _leader;
    private _dir = _stagingPos vectorFromTo _targetPos;
    private _distToTarget = _stagingPos distance2D _targetPos;

    private _deployPos = _targetPos;
    if (_distToTarget > _currentDist) then {
        _deployPos = _targetPos vectorAdd (_dir vectorMultiply -_currentDist);
        private _safePos = [_deployPos, 0, 40, 3, 0, 0.7, 0] call BIS_fnc_findSafePos;
        if (count _safePos == 2) then { _deployPos = [_safePos # 0, _safePos # 1, 0]; };
    };

    // Clear any previous relocation waypoint so orders never stack up and compete
    for "_i" from (count (waypoints _group) - 1) to 0 step -1 do {
        deleteWaypoint [_group, _i];
    };

    private _wp = _group addWaypoint [_deployPos, 0];
    _wp setWaypointType "MOVE";
    [_group, _wp select 1] remoteExec ["A3A_fnc_planning_localSetCurrentWaypoint", groupOwner _group];

    _group setBehaviour "AWARE";
    _group setSpeedMode "NORMAL";

    { [_x, _deployPos] remoteExec ["A3A_fnc_planning_localDoMove", owner _x]; } forEach (units _group);

    // --- 2. Wait until in position (or aborted) ---
    private _reached = false;
    private _moveTimeout = time + 120;
    while {true} do {
        if (!alive _leader || {count (units _group) == 0}) exitWith { _done = true; };
        if ((sidesX getVariable [_targetMarker, sideUnknown]) == teamPlayer) exitWith { _done = true; };
        if (_leader distance2D _deployPos < 25) exitWith { _reached = true; };
        if (time > _moveTimeout) exitWith {};
        sleep 5;
    };

    if (_done) exitWith {};

    if (!_reached) then {
        // Couldn't get there (blocked/stuck route) - try again next cycle from a slightly closer point
        _currentDist = (_currentDist - 50) max _minDist;
    } else {

        // --- 3. Assemble the static weapon ---
        _staticVeh = createVehicle [_staticClass, getPosATL _leader, [], 0, "NONE"];
        [_staticVeh, teamPlayer] call A3A_fnc_AIVEHinit;

        private _units = units _group;
        private _gunner = selectRandom _units;
        private _otherUnits = _units - [_gunner];
        private _watcher = if (count _otherUnits > 0) then { _otherUnits select 0 } else { objNull };

        [_gunner, _staticVeh] remoteExec ["A3A_fnc_planning_localMoveInGunner", owner _gunner];
        { removeBackpackGlobal _x; } forEach _units;

        diag_log format ["[A3A Ultimate Tweaks Extender] Support AI group %1 deployed static %2 at standoff %3m.", groupID _group, _staticClass, _currentDist];

        // --- 4. Operate until forced to relocate, captured, or destroyed ---
        private _lastContactTime = time;
        private _relocate = false;

        while {alive _leader && {count (units _group) > 0} && {alive _staticVeh} && {!_relocate}} do {
            if ((sidesX getVariable [_targetMarker, sideUnknown]) == teamPlayer) exitWith { _done = true; };

            // Self-preservation: are enemies closing in on OUR position?
            private _threatsNearUs = { alive _x && {side _x in [Occupants, Invaders]} && {_x distance2D (getPosATL _staticVeh) < _dangerDist} } count allUnits;

            if (_threatsNearUs > 0) then {
                _relocate = true;
                _currentDist = (_currentDist + 150) min _maxDist;
            } else {
                // Suppression targets: enemies actually defending the objective
                private _targetsNearAO = allUnits select { alive _x && {side _x in [Occupants, Invaders]} && {_x distance2D _targetPos < 350} };

                if (count _targetsNearAO > 0) then {
                    _lastContactTime = time;

                    if (_isMortar && {time - _lastFireTime > 25}) then {
                        _lastFireTime = time;
                        private _target = selectRandom _targetsNearAO;
                        private _mags = magazines _staticVeh;
                        if (count _mags > 0) then {
                            [_staticVeh, getPosATL _target, _mags # 0, 3] remoteExec ["A3A_fnc_planning_localArtilleryFire", owner _staticVeh];
                        };
                    };

                    if (!_isMortar && {!isNull _watcher}) then {
                        private _closest = _targetsNearAO select 0;
                        private _closestDist = 1e9;
                        {
                            private _d = _x distance2D (getPosATL _staticVeh);
                            if (_d < _closestDist) then { _closestDist = _d; _closest = _x; };
                        } forEach _targetsNearAO;
                        [_watcher, getPosATL _closest] remoteExec ["A3A_fnc_planning_localDoWatch", owner _watcher];
                    };
                } else {
                    if (!_isMortar && {!isNull _watcher}) then {
                        [_watcher, _targetPos] remoteExec ["A3A_fnc_planning_localDoWatch", owner _watcher];
                    };

                    // Quiet for too long - the fight likely moved on. Creep closer to stay useful.
                    if (time - _lastContactTime > _quietTimeout && {_currentDist > _minDist}) then {
                        _relocate = true;
                        _currentDist = (_currentDist - 150) max _minDist;
                    };
                };
            };

            sleep 10;
        };
    };
};

// Final cleanup if we're ending while still holding a static and the objective wasn't captured
if (!isNull _staticVeh && {(sidesX getVariable [_targetMarker, sideUnknown]) != teamPlayer} && {!alive (leader _group)}) then {
    deleteVehicle _staticVeh;
};
