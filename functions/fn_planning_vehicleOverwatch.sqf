/*
    fn_planning_vehicleOverwatch.sqf
    Handles armed vehicle (Technical/AT/AA/APC/Tank) fire-support behavior.
    Instead of driving into the objective, the vehicle holds at a stand-off distance
    and engages defenders from range, relocating if threatened or if the fight moves on.
    Runs on the server.
*/

params [
    ["_group", groupNull, [groupNull]],
    ["_vehicle", objNull, [objNull]],
    ["_targetMarker", "", [""]],
    ["_targetPos", [0,0,0], [[]]]
];

if (isNull _group || {isNull _vehicle}) exitWith {};

private _syncRetries = 0;
while {count (units _group) == 0 && {_syncRetries < 30}} do {
    sleep 0.5;
    _syncRetries = _syncRetries + 1;
};

if (count (units _group) == 0) exitWith {
    diag_log format ["[A3A Ultimate Tweaks Extender] Vehicle Overwatch aborted: sync failed for group %1.", _group];
};

// Take full control of the group's orders now that specialized overwatch AI is active.
// Clear the fallback HOLD waypoint from spawn so it can never later compete with
// the standoff positioning managed by this loop.
for "_i" from (count (waypoints _group) - 1) to 0 step -1 do {
    deleteWaypoint [_group, _i];
};

diag_log format ["[A3A Ultimate Tweaks Extender] Vehicle Overwatch started for group: %1, Vehicle: %2", groupID _group, typeOf _vehicle];

// Stand-off distances by armor class - lighter vehicles need to stay further out to survive
private _idealDist  = 320;
private _minDist    = 120;
private _maxDist    = 500;
private _dangerDist = 120;

if (_vehicle isKindOf "Tank") then {
    _idealDist = 220; _minDist = 100; _maxDist = 400; _dangerDist = 90;
} else {
    if (_vehicle isKindOf "APC" || {_vehicle isKindOf "Wheeled_APC_F"}) then {
        _idealDist = 260; _minDist = 100; _maxDist = 450; _dangerDist = 100;
    };
};

private _currentDist = _idealDist;
private _lastContactTime = time;
private _done = false;

while {!_done} do {

    if (!alive _vehicle || {{alive _x} count (units _group) == 0}) exitWith { _done = true; };
    if ((sidesX getVariable [_targetMarker, sideUnknown]) == teamPlayer) exitWith { _done = true; };

    // --- 1. Move to standoff position ---
    private _stagingPos = getPosATL _vehicle;
    private _dir = _stagingPos vectorFromTo _targetPos;
    private _distToTarget = _stagingPos distance2D _targetPos;

    private _deployPos = _targetPos;
    if (_distToTarget > _currentDist) then {
        _deployPos = _targetPos vectorAdd (_dir vectorMultiply -_currentDist);
        private _safePos = [_deployPos, 0, 60, 5, 0, 0.7, 0] call BIS_fnc_findSafePos;
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
    _group setCombatMode "RED";
    _group setSpeedMode "NORMAL";

    { [_x, _deployPos] remoteExec ["A3A_fnc_planning_localDoMove", owner _x]; } forEach (units _group);

    // --- 2. Wait until in position ---
    private _reached = false;
    private _moveTimeout = time + 120;
    while {true} do {
        if (!alive _vehicle || {{alive _x} count (units _group) == 0}) exitWith { _done = true; };
        if ((sidesX getVariable [_targetMarker, sideUnknown]) == teamPlayer) exitWith { _done = true; };
        if (_vehicle distance2D _deployPos < 30) exitWith { _reached = true; };
        if (time > _moveTimeout) exitWith {};
        sleep 5;
    };

    if (_done) exitWith {};

    if (!_reached) then {
        _currentDist = (_currentDist - 60) max _minDist;
    } else {

        // --- 3. Hold position, engage defenders near the objective from range ---
        _group setBehaviour "COMBAT";
        _group setCombatMode "RED";
        { _x setUnitPos "AUTO"; } forEach (units _group);

        private _relocate = false;
        _lastContactTime = time;

        while {alive _vehicle && {{alive _x} count (units _group) > 0} && {!_relocate}} do {
            if ((sidesX getVariable [_targetMarker, sideUnknown]) == teamPlayer) exitWith { _done = true; };

            // Self-preservation: is anything closing in on us specifically?
            private _threatsNearUs = { alive _x && {side _x in [Occupants, Invaders]} && {_x distance2D (getPosATL _vehicle) < _dangerDist} } count allUnits;

            if (_threatsNearUs > 0) then {
                _relocate = true;
                _currentDist = (_currentDist + 150) min _maxDist;
            } else {
                private _targetsNearAO = allUnits select { alive _x && {side _x in [Occupants, Invaders]} && {_x distance2D _targetPos < 400} };
                private _gunner = gunner _vehicle;

                if (count _targetsNearAO > 0) then {
                    _lastContactTime = time;
                    if (!isNull _gunner) then {
                        private _closest = _targetsNearAO select 0;
                        private _closestDist = 1e9;
                        {
                            private _d = _x distance2D (getPosATL _vehicle);
                            if (_d < _closestDist) then { _closestDist = _d; _closest = _x; };
                        } forEach _targetsNearAO;
                        [_gunner, getPosATL _closest] remoteExec ["A3A_fnc_planning_localDoWatch", owner _gunner];
                    };
                } else {
                    if (!isNull _gunner) then {
                        [_gunner, _targetPos] remoteExec ["A3A_fnc_planning_localDoWatch", owner _gunner];
                    };
                    if (time - _lastContactTime > 45 && {_currentDist > _minDist}) then {
                        _relocate = true;
                        _currentDist = (_currentDist - 150) max _minDist;
                    };
                };
            };

            sleep 8;
        };
    };
};
