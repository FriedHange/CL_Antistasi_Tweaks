params ["_group", "_vehicle", "_targetMarker", "_targetPos"];
if (isNull _group || { isNull _vehicle }) exitWith {};

private _syncRetries = 0;
while { count (units _group) == 0 && { _syncRetries < 30 } } do {
	sleep 0.5;
	_syncRetries = _syncRetries + 1;
};
if (count (units _group) == 0) exitWith {
	diag_log format ["[A3A Tweaks] Vehicle Overwatch aborted: sync failed for group %1.", _group];
};

private _isTank = _vehicle isKindOf "Tank" && !(_vehicle isKindOf "APC_Tracked_F");
private _isAPC = _vehicle isKindOf "Wheeled_APC_F" || _vehicle isKindOf "APC_Tracked_F";

private _standoff = switch (true) do {
	case _isTank: { 150 };
	case _isAPC: { 110 };
	default { 80 };
};

_group setBehaviour "COMBAT";
_group setCombatMode "RED";
_group setSpeedMode "FULL";
diag_log format ["[A3A Tweaks] Active Vehicle Overwatch started for group: %1, Vehicle: %2 (Tank: %3, APC: %4)", groupId _group, typeOf _vehicle, _isTank, _isAPC];

private _done = false;
private _lastWpTime = 0;
private _lastWpPos = [0,0,0];

while { !_done } do {
	if (!alive _vehicle || { { alive _x } count (units _group) == 0 }) exitWith {
		_done = true;
	};
	if ((sidesX getVariable [_targetMarker, sideUnknown]) == teamPlayer) exitWith {
		_done = true;
	};

	private _curTgt = getMarkerPos _targetMarker;
	if (_curTgt distance2D [0, 0, 0] < 1) then { _curTgt = _targetPos; };
	private _curPos = getPosATL _vehicle;

	// Target acquisition within 800m
	private _nearEnemies = allUnits select {
		alive _x && { side _x in [Occupants, Invaders] } && { _x distance2D _curPos < 800 || { _x distance2D _curTgt < 600 } }
	};

	private _gunner = gunner _vehicle;
	private _driver = driver _vehicle;

	if (count _nearEnemies > 0) then {
		private _chosenTarget = objNull;
		if (_isTank || _isAPC) then {
			private _enemyVehs = _nearEnemies select { (vehicle _x) != _x };
			if (count _enemyVehs > 0) then { _chosenTarget = _enemyVehs select 0; };
		};
		if (isNull _chosenTarget) then {
			private _cd = 1e9;
			{
				private _d = _x distance2D _curPos;
				if (_d < _cd) then {
					_cd = _d;
					_chosenTarget = _x;
				};
			} forEach _nearEnemies;
		};
		if (!isNull _chosenTarget) then {
			_group reveal [_chosenTarget, 4];
			if (!isNull _gunner) then {
				_gunner doTarget _chosenTarget;
				_gunner doFire _chosenTarget;
				[_gunner, getPosATL _chosenTarget] remoteExec ["A3A_fnc_planning_localDoWatch", owner _gunner];
			};
			if (!isNull _driver) then {
				_driver doTarget _chosenTarget;
				_driver doFire _chosenTarget;
			};
		};
	};

	// Calculate ideal assault support position relative to objective
	private _spawnPos = _group getVariable ["siege_spawnPos", _curPos];
	private _approachDir = _spawnPos vectorFromTo _curTgt;
	if (_approachDir isEqualTo [0, 0, 0]) then { _approachDir = [0, 1, 0]; };

	private _desiredPos = _curTgt vectorAdd ((vectorNormalized _approachDir) vectorMultiply -_standoff);
	if (_curPos distance2D _curTgt < _standoff) then {
		_desiredPos = _curTgt;
	};

	// Periodically update movement waypoints so vehicle continuously pushes with troops
	if ((_curPos distance2D _desiredPos > 35) && { (time - _lastWpTime > 12) || (_desiredPos distance2D _lastWpPos > 30) || (count (waypoints _group) == 0) }) then {
		_lastWpTime = time;
		_lastWpPos = _desiredPos;

		for "_i" from (count (waypoints _group) - 1) to 0 step -1 do { deleteWaypoint [_group, _i]; };
		private _wp = _group addWaypoint [_desiredPos, 0];
		_wp setWaypointType "SAD";
		_wp setWaypointBehaviour "COMBAT";
		_wp setWaypointCombatMode "RED";
		_wp setWaypointSpeed "FULL";
		_wp setWaypointCompletionRadius 25;
		[_group, _wp select 1] remoteExec ["A3A_fnc_planning_localSetCurrentWaypoint", groupOwner _group];

		_group setBehaviour "COMBAT";
		_group setCombatMode "RED";
		_group setSpeedMode "FULL";
	};

	sleep 6;
};