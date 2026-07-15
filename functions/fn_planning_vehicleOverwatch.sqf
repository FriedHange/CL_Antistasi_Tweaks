params ["_group", "_vehicle", "_targetMarker", "_targetPos"];
if (isNull _group || {isNull _vehicle}) exitWith {};

private _syncRetries = 0;
while {count (units _group) == 0 && {_syncRetries < 30}} do { sleep 0.5; _syncRetries = _syncRetries + 1; };
if (count (units _group) == 0) exitWith {
    diag_log format ["[A3A Tweaks] Vehicle Overwatch aborted: sync failed for group %1.", _group];
};
for "_i" from (count (waypoints _group) - 1) to 0 step -1 do { deleteWaypoint [_group, _i]; };

private _idealDist = 200; private _maxDist = 250; private _dangerDist = 120;
if (_vehicle isKindOf "Tank") then { _idealDist = 220; _maxDist = 280; _dangerDist = 90; }
else { if (_vehicle isKindOf "APC" || {_vehicle isKindOf "Wheeled_APC_F"}) then { _idealDist = 210; _maxDist = 260; _dangerDist = 100; }; };

_group setBehaviour "AWARE"; _group setCombatMode "RED";
diag_log format ["[A3A Tweaks] Event-driven Vehicle Overwatch started for group: %1, Vehicle: %2", groupID _group, typeOf _vehicle];

private _fnc_rotateDir = {
    params ["_dir","_deg"];
    [(_dir select 0) * cos(_deg) - (_dir select 1) * sin(_deg),
     (_dir select 0) * sin(_deg) + (_dir select 1) * cos(_deg), 0]
};
private _fnc_hasLOS = {
    params ["_fromPos","_toPos"];
    private _from = ATLToASL (_fromPos vectorAdd [0,0,1.8]);
    private _to = ATLToASL (_toPos vectorAdd [0,0,1.8]);
    (!terrainIntersectASL [_from,_to]) && {!lineIntersects [_from,_to,objNull,objNull]}
};
private _fnc_findPos = {
    params ["_targetPos","_biasFrom","_dist"];
    private _dir = _targetPos vectorFromTo _biasFrom;
    if (_dir isEqualTo [0,0,0]) then { _dir = [1,0,0]; };
    private _best = [];
    {
        private _testDir = [_dir, _x] call _fnc_rotateDir;
        private _cand = _targetPos vectorAdd (_testDir vectorMultiply _dist);
        private _safe = [_cand, 0, 50, 5, 0, 0.7, 0] call BIS_fnc_findSafePos;
        if (count _safe == 2) then {
            private _cPos = [_safe select 0, _safe select 1, 0];
            if ([_cPos, _targetPos] call _fnc_hasLOS) exitWith { _best = _cPos; };
        };
    } forEach [0,-30,30,-60,60,-90,90,-120,120,150,-150,180];
    if (_best isEqualTo []) then {
        private _safe = [_targetPos vectorAdd (_dir vectorMultiply _dist), 0, 70, 5, 0, 0.7, 0] call BIS_fnc_findSafePos;
        _best = if (count _safe == 2) then { [_safe select 0, _safe select 1, 0] } else { _targetPos vectorAdd (_dir vectorMultiply _dist) };
    };
    _best
};

private _fnc_frontlinePos = {
    params ["_objPos"];
    ([_objPos] call A3A_fnc_planning_getAssaultAnchor) params ["_advanced","_anchorPos","_anchorDist"];
    if (_anchorDist >= 0) exitWith { [_anchorPos, true] };
    private _nearEnemies = allUnits select { alive _x && {side _x in [Occupants, Invaders]} && {_x distance2D _objPos < 400} };
    if (count _nearEnemies > 0) exitWith { [(_nearEnemies select 0) call {getPosATL _this}, true] };
    [_objPos, false]
};

private _confirmNeeded = 3;
private _cRange = 0; private _cLOS = 0; private _cNoTargets = 0;
private _done = false;

while {!_done} do {
    if (!alive _vehicle || {{alive _x} count (units _group) == 0}) exitWith { _done = true; };
    if ((sidesX getVariable [_targetMarker, sideUnknown]) == teamPlayer) exitWith { _done = true; };

    _cRange = 0; _cLOS = 0; _cNoTargets = 0;

    private _curTgt = getMarkerPos _targetMarker;
    if (_curTgt distance2D [0,0,0] < 1) then { _curTgt = _targetPos; };

    // Stage forward from behind the FRONTLINE, not straight at the objective - this keeps the
    // vehicle out of the AO center while letting it advance in steps as the assault progresses.
    ([_curTgt] call _fnc_frontlinePos) params ["_frontPos","_haveBattlePoint"];
    private _biasPoint = if (_haveBattlePoint) then { _frontPos } else { _curTgt };
    // Deploy behind the frontline (further from the objective than the leading infantry),
    // never in front of them.
    private _dirBehind = _curTgt vectorFromTo _biasPoint;
    if (_dirBehind isEqualTo [0,0,0]) then { _dirBehind = getPosATL _vehicle vectorFromTo _curTgt; };
    private _standoffPoint = _biasPoint vectorAdd (_dirBehind vectorMultiply 40); // stay just behind them
    private _deployPos = [_curTgt, _standoffPoint, _idealDist] call _fnc_findPos;

    // --- 1. Move to position ---
    for "_i" from (count (waypoints _group) - 1) to 0 step -1 do { deleteWaypoint [_group, _i]; };
    private _wp = _group addWaypoint [_deployPos, 0];
    _wp setWaypointType "MOVE";
    [_group, _wp select 1] remoteExec ["A3A_fnc_planning_localSetCurrentWaypoint", groupOwner _group];
    _group setBehaviour "AWARE"; _group setCombatMode "RED"; _group setSpeedMode "NORMAL";
    { [_x, _deployPos] remoteExec ["A3A_fnc_planning_localDoMove", owner _x]; } forEach (units _group);

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
    if (!_reached) then { continue; };

    // --- 2. Stop and engage ---
    _group setBehaviour "COMBAT"; _group setCombatMode "RED";
    { _x setUnitPos "AUTO"; } forEach (units _group);
    diag_log format ["[A3A Tweaks] %1 holding overwatch at %2m behind the frontline.", groupID _group, _idealDist];

    private _relocate = false;
    while {alive _vehicle && {{alive _x} count (units _group) > 0} && {!_relocate}} do {
        if ((sidesX getVariable [_targetMarker, sideUnknown]) == teamPlayer) exitWith { _done = true; };

        private _curPos = getPosATL _vehicle;
        private _threatsNearUs = { alive _x && {side _x in [Occupants, Invaders]} && {_x distance2D _curPos < _dangerDist} } count allUnits;
        if (_threatsNearUs > 0) exitWith { _relocate = true; diag_log "[A3A Tweaks] Vehicle relocating: position threatened."; };

        private _liveTgt = getMarkerPos _targetMarker;
        ([_liveTgt] call _fnc_frontlinePos) params ["_frontPos2","_haveBattlePoint2"];

        if (_haveBattlePoint2) then {
            // Only "too far" matters here - the frontline advanced beyond effective support distance.
            if (_curPos distance2D _frontPos2 > _maxDist) then { _cRange = _cRange + 1; } else { _cRange = 0; };
            if !([_curPos, _frontPos2] call _fnc_hasLOS) then { _cLOS = _cLOS + 1; } else { _cLOS = 0; };
        } else {
            _cRange = 0; _cLOS = 0;
        };

        private _targetsInRange = { alive _x && {side _x in [Occupants, Invaders]} && {_x distance2D _curPos < _maxDist} } count allUnits;
        if (_targetsInRange == 0 && {_haveBattlePoint2}) then { _cNoTargets = _cNoTargets + 1; } else { _cNoTargets = 0; };

        if (_cRange >= _confirmNeeded) exitWith { _relocate = true; diag_log "[A3A Tweaks] Vehicle relocating: frontline moved beyond support distance."; };
        if (_cLOS >= _confirmNeeded) exitWith { _relocate = true; diag_log "[A3A Tweaks] Vehicle relocating: LOS to the battle lost."; };
        if (_cNoTargets >= _confirmNeeded) exitWith { _relocate = true; diag_log "[A3A Tweaks] Vehicle relocating: no enemies in engagement range."; };

        private _targetsNearAO = allUnits select { alive _x && {side _x in [Occupants, Invaders]} && {_x distance2D _liveTgt < 400} };
        private _gunner = gunner _vehicle;
        if (count _targetsNearAO > 0) then {
            if (!isNull _gunner) then {
                private _closest = _targetsNearAO select 0; private _cd = 1e9;
                { private _d = _x distance2D _curPos; if (_d < _cd) then { _cd = _d; _closest = _x; }; } forEach _targetsNearAO;
                [_gunner, getPosATL _closest] remoteExec ["A3A_fnc_planning_localDoWatch", owner _gunner];
            };
        } else {
            if (!isNull _gunner) then { [_gunner, _liveTgt] remoteExec ["A3A_fnc_planning_localDoWatch", owner _gunner]; };
        };

        sleep 8;
    };
    if (_done) exitWith {};
};
