params ["_group", "_type", "_targetMarker", "_targetPos"];
if (isNull _group) exitWith {};

private _syncRetries = 0;
while {count (units _group) == 0 && {_syncRetries < 30}} do { sleep 0.5; _syncRetries = _syncRetries + 1; };
private _leadRetries = 0;
while {isNull (leader _group) && {_leadRetries < 20}} do { sleep 0.5; _leadRetries = _leadRetries + 1; };
if (isNull (leader _group) || {count (units _group) == 0}) exitWith {
    diag_log format ["[A3A Tweaks] Support AI aborted: sync failed for group %1.", _group];
};
for "_i" from (count (waypoints _group) - 1) to 0 step -1 do { deleteWaypoint [_group, _i]; };

private _isMortar = _type in ["Mortar", "Mortar_FALLBACK"];
private _sidePrefix = if (teamPlayer == west) then {"B"} else { if (teamPlayer == east) then {"O"} else {"I"} };

private _fnc_resolveStatic = {
    params ["_key","_fallback"];
    private _list = A3A_faction_reb getOrDefault [_key, []];
    private _found = "";
    { if (!isNil "_x" && {_x != "" && {isClass (configFile >> "CfgVehicles" >> _x)}}) exitWith { _found = _x; }; } forEach _list;
    if (_found == "") then { _found = if (isClass (configFile >> "CfgVehicles" >> _fallback)) then {_fallback} else {"I_HMG_01_high_F"}; };
    _found
};
private _staticClass = if (_isMortar) then {
    ["staticMortars", _sidePrefix + "_Mortar_01_F"] call _fnc_resolveStatic
} else {
    ["staticMGs", _sidePrefix + "_HMG_01_high_F"] call _fnc_resolveStatic
};
if (_staticClass == "" || {!isClass (configFile >> "CfgVehicles" >> _staticClass)}) exitWith {
    diag_log "[A3A Tweaks] Support AI failed: no valid static classname found.";
};

// --- Event thresholds ---
// Mortars hang well back and provide sustained indirect fire; MG teams stay tight on the
// heels of the advancing assault squads so they can keep contributing suppressive fire.
private _idealDist  = if (_isMortar) then {500} else {100};   // Mortar ~500m behind frontline / MG ~100m behind frontline
private _maxDist    = if (_isMortar) then {700} else {180};   // "frontline out of effective range"
private _dangerDist = if (_isMortar) then {150} else {50};    // "position heavily threatened"
private _originalCount = count (units _group);

// MG teams shouldn't wait until they reach their full standoff distance if they run into the
// enemy on the way there - if they already have LOS to a live target within this range while
// still approaching, they stop and deploy on the spot instead of continuing to travel.
private _earlyEngageRange = 250;

private _fnc_rotateDir = {
    params ["_dir","_deg"];
    [(_dir select 0) * cos(_deg) - (_dir select 1) * sin(_deg),
     (_dir select 0) * sin(_deg) + (_dir select 1) * cos(_deg), 0]
};
private _fnc_hasLOS = {
    params ["_fromPos","_toPos"];
    private _from = ATLToASL (_fromPos vectorAdd [0,0,1.6]);
    private _to = ATLToASL (_toPos vectorAdd [0,0,1.6]);
    (!terrainIntersectASL [_from,_to]) && {!lineIntersects [_from,_to,objNull,objNull]}
};

// Checks that a 2D/ATL ground position is actually usable: not water, not a steep slope,
// and not sitting inside/on top of a building, rock, or other solid obstruction.
private _fnc_isValidGroundPos = {
    params ["_pos"];
    if (_pos isEqualTo []) exitWith { false };
    if (surfaceIsWater _pos) exitWith { false };
    private _normal = surfaceNormal _pos;
    // z-component of the surface normal is 1 on flat ground; reject anything steeper than ~35-40 degrees
    if ((_normal select 2) < 0.78) exitWith { false };
    private _blockers = (_pos nearObjects ["House", 4]) + (_pos nearObjects ["Building", 4]) + (_pos nearObjects ["Rocks", 4]) + (_pos nearObjects ["Rock", 4]);
    if (count _blockers > 0) exitWith { false };
    true
};

// Ring-search for a valid, navigable position at _dist from _biasFrom (offset further away from
// _dirAnchor than _biasFrom is), that also has line of sight to _losTarget. Falls back through
// progressively looser searches, but NEVER hands back an unvalidated/unreachable position --
// a waypoint is only produced once a suitable spot has actually been found.
private _fnc_findPos = {
    params ["_dirAnchor","_biasFrom","_dist","_losTarget"];
    private _dir = _dirAnchor vectorFromTo _biasFrom;
    if (_dir isEqualTo [0,0,0]) then { _dir = [1,0,0]; };
    private _angles = [0,-30,30,-60,60,-90,90,-120,120,150,-150,180];
    private _best = [];

    // Pass 1: valid terrain + LOS to the battle
    {
        private _testDir = [_dir, _x] call _fnc_rotateDir;
        private _cand = _biasFrom vectorAdd (_testDir vectorMultiply _dist);
        private _safe = [_cand, 0, 40, 3, 0, 0.7, 0] call BIS_fnc_findSafePos;
        if (count _safe == 2) then {
            private _cPos = [_safe select 0, _safe select 1, 0];
            if ([_cPos] call _fnc_isValidGroundPos && {[_cPos, _losTarget] call _fnc_hasLOS}) exitWith { _best = _cPos; };
        };
    } forEach _angles;

    // Pass 2: relax the LOS requirement but keep the terrain valid
    if (_best isEqualTo []) then {
        {
            private _testDir = [_dir, _x] call _fnc_rotateDir;
            private _cand = _biasFrom vectorAdd (_testDir vectorMultiply _dist);
            private _safe = [_cand, 0, 60, 4, 0, 0.7, 0] call BIS_fnc_findSafePos;
            if (count _safe == 2) then {
                private _cPos = [_safe select 0, _safe select 1, 0];
                if ([_cPos] call _fnc_isValidGroundPos) exitWith { _best = _cPos; };
            };
        } forEach _angles;
    };

    // Pass 3: expanding radius search around the bias point for any reachable, valid terrain
    if (_best isEqualTo []) then {
        private _radius = 60;
        private _tries = 0;
        while {_best isEqualTo [] && {_tries < 6}} do {
            private _safe = [_biasFrom, 0, _radius, 4, 0, 0.7, 0] call BIS_fnc_findSafePos;
            if (count _safe == 2) then {
                private _cPos = [_safe select 0, _safe select 1, 0];
                if ([_cPos] call _fnc_isValidGroundPos) then { _best = _cPos; };
            };
            _radius = _radius + 40;
            _tries = _tries + 1;
        };
    };

    // Last resort: hold at the bias point itself rather than leaving the group without any waypoint
    if (_best isEqualTo [] && {[_biasFrom] call _fnc_isValidGroundPos}) then { _best = _biasFrom; };
    if (_best isEqualTo []) then { _best = _biasFrom; };
    _best
};

diag_log format ["[A3A Tweaks] Event-driven Support AI started for group: %1, Type: %2", groupID _group, _type];

private _fnc_frontlinePos = {
    // Prefer the nearest advancing assault group's leader position; fall back to nearest
    // live enemy near the objective; only use the bare objective marker as a last resort
    // (and treat that case as "no reliable battle point yet" for LOS/range purposes).
    params ["_objPos"];
    ([_objPos] call A3A_fnc_planning_getAssaultAnchor) params ["_advanced","_anchorPos","_anchorDist"];
    if (_anchorDist >= 0) exitWith { [_anchorPos, true] };
    private _nearEnemies = allUnits select { alive _x && {side _x in [Occupants, Invaders]} && {_x distance2D _objPos < 350} };
    if (count _nearEnemies > 0) exitWith { [(_nearEnemies select 0) call {getPosATL _this}, true] };
    [_objPos, false]
};

private _staticVeh = objNull;
private _watcher = objNull;
private _done = false;
private _lastFireTime = 0;

// Debounce counters - a relocation condition must persist across several checks before we
// actually pack up, so a single bad frame (someone walks past, momentary LOS blip) doesn't
// tear down a perfectly good position. Mortars get a longer debounce than MG teams since
// their whole value is staying put and providing sustained fire; they were previously
// repositioning far too readily.
private _confirmNeeded = if (_isMortar) then {5} else {3}; // ~50s (mortar) / ~30s (MG) of sustained condition
private _cRange = 0; private _cLOS = 0; private _cNoTargets = 0;

while {!_done} do {
    if (!alive (leader _group) || {count (units _group) == 0}) exitWith { _done = true; };
    if ((sidesX getVariable [_targetMarker, sideUnknown]) == teamPlayer) exitWith { _done = true; };

    // --- Pack up any existing emplacement before relocating ---
    if (!isNull _staticVeh) then {
        { unassignVehicle _x; [_x] orderGetIn false; } forEach (crew _staticVeh);
        deleteVehicle _staticVeh; _staticVeh = objNull; sleep 1;
    };
    _cRange = 0; _cLOS = 0; _cNoTargets = 0;

    private _curTargetPos = getMarkerPos _targetMarker;
    if (_curTargetPos distance2D [0,0,0] < 1) then { _curTargetPos = _targetPos; };

    // Bias the NEW position off the frontline (if the assault has started) so support follows
    // the advancing infantry rather than always re-centering on the objective itself. The
    // deploy position is placed _idealDist further BEHIND the frontline (i.e. further from the
    // objective than the frontline anchor itself), not simply _idealDist from the objective.
    ([_curTargetPos] call _fnc_frontlinePos) params ["_biasPos","_haveBattlePoint"];
    private _searchAnchor = if (_haveBattlePoint) then { _biasPos } else { _curTargetPos };
    private _deployPos = [_curTargetPos, _searchAnchor, _idealDist, _searchAnchor] call _fnc_findPos;

    // --- 1. Move to the support position ---
    for "_i" from (count (waypoints _group) - 1) to 0 step -1 do { deleteWaypoint [_group, _i]; };
    private _wp = _group addWaypoint [_deployPos, 0];
    _wp setWaypointType "MOVE";
    _wp setWaypointCompletionRadius 50; // Don't force units to chase an exact pixel; settle nearby
    [_group, _wp select 1] remoteExec ["A3A_fnc_planning_localSetCurrentWaypoint", groupOwner _group];
    _group setBehaviour "AWARE"; _group setSpeedMode "NORMAL";
    { [_x, _deployPos] remoteExec ["A3A_fnc_planning_localDoMove", owner _x]; } forEach (units _group);

    private _reached = false;
    private _earlyDeploy = false;
    private _moveTimeout = time + 120;
    while {true} do {
        if (!alive (leader _group) || {count (units _group) == 0}) exitWith { _done = true; };
        if ((sidesX getVariable [_targetMarker, sideUnknown]) == teamPlayer) exitWith { _done = true; };
        if ((leader _group) distance2D _deployPos < 25) exitWith { _reached = true; };

        // MG teams (not mortars - they fire indirectly and gain nothing from stopping early):
        // if the enemy is already visible and in range while still en route to the calculated
        // standoff point, stop right here and deploy immediately rather than arriving late.
        if (!_isMortar) then {
            private _curLeaderPos = getPosATL (leader _group);
            private _engageIdx = allUnits findIf {
                alive _x && {side _x in [Occupants, Invaders]} && {_x distance2D _curLeaderPos < _earlyEngageRange} && {[_curLeaderPos, getPosATL _x] call _fnc_hasLOS}
            };
            if (_engageIdx != -1) exitWith { _reached = true; _earlyDeploy = true; };
        };

        if (time > _moveTimeout) exitWith {};
        sleep 2;
    };
    if (_done) exitWith {};
    if (!_reached) then { continue; };

    if (_earlyDeploy) then {
        // Halt in place instead of continuing on to the further standoff position.
        { doStop _x; } forEach (units _group);
        for "_i" from (count (waypoints _group) - 1) to 0 step -1 do { deleteWaypoint [_group, _i]; };
        diag_log format ["[A3A Tweaks] %1 stopping early to deploy - enemy contact during approach.", groupID _group];
    };

    // --- 2. Assemble & occupy the emplacement ---
    _staticVeh = createVehicle [_staticClass, getPosATL (leader _group), [], 0, "NONE"];
    [_staticVeh, teamPlayer] call A3A_fnc_AIVEHinit;
    private _gunner = selectRandom (units _group);
    _watcher = ((units _group) - [_gunner]) param [0, objNull];
    [_gunner, _staticVeh] remoteExec ["A3A_fnc_planning_localMoveInGunner", owner _gunner];
    { removeBackpackGlobal _x; } forEach (units _group);
    _group setBehaviour "COMBAT";
    { _x setUnitPos "AUTO"; } forEach (units _group);

    diag_log format ["[A3A Tweaks] %1 deployed %2 at %3m. Holding until a relocation event fires.", groupID _group, _staticClass, _idealDist];

    // --- 3. Hold and fight until a relocation event fires ---
    private _relocate = false;
    while {alive (leader _group) && {count (units _group) > 0} && {alive _staticVeh} && {!_relocate}} do {
        if ((sidesX getVariable [_targetMarker, sideUnknown]) == teamPlayer) exitWith { _done = true; };

        // Instant triggers: casualties and direct threat never wait for debounce.
        private _aliveCount = {alive _x} count (units _group);
        if (_aliveCount <= (_originalCount / 2)) exitWith { _relocate = true; diag_log "[A3A Tweaks] Relocating: heavy casualties."; };

        private _curPos = getPosATL _staticVeh;
        private _threatsNearUs = { alive _x && {side _x in [Occupants, Invaders]} && {_x distance2D _curPos < _dangerDist} } count allUnits;
        if (_threatsNearUs > 0) exitWith { _relocate = true; diag_log "[A3A Tweaks] Relocating: position threatened."; };

        // Debounced triggers, evaluated against the FRONTLINE, not the fixed objective.
        private _liveObjPos = getMarkerPos _targetMarker;
        ([_liveObjPos] call _fnc_frontlinePos) params ["_frontPos","_haveBattlePoint"];

        if (_haveBattlePoint) then {
            if (_curPos distance2D _frontPos > _maxDist) then { _cRange = _cRange + 1; } else { _cRange = 0; };
            if !([_curPos, _frontPos] call _fnc_hasLOS) then { _cLOS = _cLOS + 1; } else { _cLOS = 0; };
        } else {
            // No frontline/enemy contact established yet - don't punish the unit for that.
            _cRange = 0; _cLOS = 0;
        };

        private _targetsInRange = { alive _x && {side _x in [Occupants, Invaders]} && {_x distance2D _curPos < _maxDist} } count allUnits;
        if (_targetsInRange == 0 && {_haveBattlePoint}) then { _cNoTargets = _cNoTargets + 1; } else { _cNoTargets = 0; };

        if (_cRange >= _confirmNeeded) exitWith { _relocate = true; diag_log "[A3A Tweaks] Relocating: frontline out of effective range."; };
        if (_cLOS >= _confirmNeeded) exitWith { _relocate = true; diag_log "[A3A Tweaks] Relocating: LOS to the battle lost."; };
        if (_cNoTargets >= _confirmNeeded) exitWith { _relocate = true; diag_log "[A3A Tweaks] Relocating: no enemies in engagement range."; };

        // Not relocating -> fight from here
        private _targetsNearAO = allUnits select { alive _x && {side _x in [Occupants, Invaders]} && {_x distance2D _liveObjPos < 350} };
        if (count _targetsNearAO > 0) then {
            if (_isMortar && {time - _lastFireTime > 25}) then {
                _lastFireTime = time;
                private _tgt = selectRandom _targetsNearAO;
                private _mags = magazines _staticVeh;
                if (count _mags > 0) then {
                    [_staticVeh, getPosATL _tgt, _mags # 0, 3] remoteExec ["A3A_fnc_planning_localArtilleryFire", owner _staticVeh];
                };
            };
            if (!_isMortar && {!isNull _watcher}) then {
                private _closest = _targetsNearAO select 0; private _cd = 1e9;
                { private _d = _x distance2D _curPos; if (_d < _cd) then { _cd = _d; _closest = _x; }; } forEach _targetsNearAO;
                [_watcher, getPosATL _closest] remoteExec ["A3A_fnc_planning_localDoWatch", owner _watcher];
            };
        } else {
            if (!_isMortar && {!isNull _watcher}) then {
                [_watcher, _liveObjPos] remoteExec ["A3A_fnc_planning_localDoWatch", owner _watcher];
            };
        };

        sleep 10;
    };
    if (_done) exitWith {};
};

if (!isNull _staticVeh && {(sidesX getVariable [_targetMarker, sideUnknown]) != teamPlayer} && {!alive (leader _group)}) then {
    deleteVehicle _staticVeh;
};
