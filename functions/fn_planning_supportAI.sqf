/*
    fn_planning_supportAI.sqf
    Handles MG and Mortar support AI loops.
    Runs on the server.
*/

params [
    ["_group", groupNull, [groupNull]],
    ["_type", "", [""]], // "MG" or "Mortar"
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

diag_log format ["[A3A Ultimate Tweaks Extender] Support AI started for group: %1, Type: %2", groupID _group, _type];

private _leader = leader _group;

// 1. Move to support positioning distance
// Mortars: 700m from target. MGs: 150m from target.
private _deployDist = if (_type == "Mortar") then { 700 } else { 150 };
private _stagingPos = getPos _leader;
private _dir = _stagingPos vectorFromTo _targetPos;
private _distToTarget = _stagingPos distance2D _targetPos;

private _deployPos = _targetPos;
if (_distToTarget > _deployDist) then {
    // Move along vector from staging to target until we are at _deployDist
    _deployPos = _targetPos vectorAdd (_dir vectorMultiply -_deployDist);
    
    // Find safe position near that spot
    private _safePos = [_deployPos, 0, 40, 3, 0, 0.7, 0] call BIS_fnc_findSafePos;
    if (count _safePos == 2) then { _deployPos = [_safePos # 0, _safePos # 1, 0]; };
};

// Send move order
private _wp = _group addWaypoint [_deployPos, 0];
_wp setWaypointType "MOVE";
[_group, _wp select 1] remoteExec ["A3A_fnc_planning_localSetCurrentWaypoint", groupOwner _group];

_group setBehaviour "AWARE";
_group setSpeedMode "NORMAL";

{
    [_x, _deployPos] remoteExec ["A3A_fnc_planning_localDoMove", owner _x];
} forEach (units _group);

// Wait until group is close to deployment position or objective captured
private _reached = false;
while {alive _leader && {count (units _group) > 0}} do {
    private _isCaptured = (sidesX getVariable [_targetMarker, sideUnknown]) == teamPlayer;
    if (_isCaptured) exitWith {};

    if (_leader distance2D _deployPos < 25) exitWith { _reached = true; };
    sleep 5;
};

if (!_reached) exitWith {
    diag_log format ["[A3A Ultimate Tweaks Extender] Support AI ended early for group %1.", _group];
};

// 2. Assemble static weapon
// Find the static classname from faction definition
private _staticClass = "";
private _sidePrefix = if (teamPlayer == west) then { "B" } else { if (teamPlayer == east) then { "O" } else { "I" } };

if (_type in ["MG", "MG_FALLBACK"]) then {
    private _mgs = A3A_faction_reb getOrDefault ["staticMGs", []];
    if (count _mgs > 0) then { _staticClass = _mgs # 0; };
    if (isNil "_staticClass" || {_staticClass == "" || {!isClass (configFile >> "CfgVehicles" >> _staticClass)}}) then {
        _staticClass = _sidePrefix + "_HMG_01_high_F";
        if (!isClass (configFile >> "CfgVehicles" >> _staticClass)) then { _staticClass = "I_HMG_01_high_F"; };
        diag_log format ["[A3A Ultimate Tweaks Extender] Falling back HMG static to '%1'.", _staticClass];
    };
};
if (_type in ["Mortar", "Mortar_FALLBACK"]) then {
    private _mortars = A3A_faction_reb getOrDefault ["staticMortars", []];
    if (count _mortars > 0) then { _staticClass = _mortars # 0; };
    if (isNil "_staticClass" || {_staticClass == "" || {!isClass (configFile >> "CfgVehicles" >> _staticClass)}}) then {
        _staticClass = _sidePrefix + "_Mortar_01_F";
        if (!isClass (configFile >> "CfgVehicles" >> _staticClass)) then { _staticClass = "I_Mortar_01_F"; };
        diag_log format ["[A3A Ultimate Tweaks Extender] Falling back Mortar static to '%1'.", _staticClass];
    };
};

if (_staticClass == "") exitWith {
    diag_log "[A3A Ultimate Tweaks Extender] Support AI failed: static classname not found.";
};

private _units = units _group;

// Spawn the static weapon
private _staticVeh = createVehicle [_staticClass, getPos _leader, [], 0, "NONE"];
[_staticVeh, teamPlayer] call A3A_fnc_AIVEHinit;

// Find gunner and loader
private _gunner = selectRandom _units;
private _otherUnits = _units - [_gunner];
private _watcher = if (count _otherUnits > 0) then { _otherUnits select 0 } else { objNull };

// Move gunner in
[_gunner, _staticVeh] remoteExec ["A3A_fnc_planning_localMoveInGunner", owner _gunner];

// Delete their backpacks since they are now deployed
{
    removeBackpackGlobal _x;
} forEach _units;

diag_log format ["[A3A Ultimate Tweaks Extender] Support AI group %1 deployed static %2.", groupID _group, _staticClass];

// 3. Operation loop
private _lastFireTime = 0;
while {alive _leader && {count (units _group) > 0} && {alive _staticVeh}} do {
    private _isCaptured = (sidesX getVariable [_targetMarker, sideUnknown]) == teamPlayer;
    if (_isCaptured) exitWith {};

    // If mortar, execute periodic fire support on enemies
    if (_type == "Mortar" && {time - _lastFireTime > 25}) then {
        _lastFireTime = time;
        private _enemies = allUnits select {
            alive _x && 
            {side _x == Occupants || {side _x == Invaders}} && 
            {_x distance2D _targetPos < 350}
        };

        if (count _enemies > 0) then {
            private _target = selectRandom _enemies;
            private _mags = magazines _staticVeh;
            if (count _mags > 0) then {
                [_staticVeh, getPos _target, _mags # 0, 3] remoteExec ["A3A_fnc_planning_localArtilleryFire", owner _staticVeh];
            };
        };
    };

    // If MG, watch target pos
    if (_type == "MG" && {!isNull _watcher}) then {
        [_watcher, _targetPos] remoteExec ["A3A_fnc_planning_localDoWatch", owner _watcher];
    };

    sleep 10;
};

// Cleanup if not captured but loop ended
if (alive _staticVeh && {(sidesX getVariable [_targetMarker, sideUnknown]) != teamPlayer}) then {
    deleteVehicle _staticVeh;
};
