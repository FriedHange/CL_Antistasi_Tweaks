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

// Standoff behind the nearest advancing friendly infantry squad (or from target if no infantry)
private _standoffBehindInfantry = switch (true) do {
	case _isTank: { 90 };
	case _isAPC: { 65 };
	default { 45 };
};
private _minStandoffFromTarget = switch (true) do {
	case _isTank: { 180 };
	case _isAPC: { 130 };
	default { 90 };
};

_group setBehaviour "COMBAT";
_group setCombatMode "RED";
_group setSpeedMode "NORMAL";
diag_log format ["[A3A Tweaks] Active Vehicle Overwatch started for group: %1, Vehicle: %2 (Tank: %3, APC: %4)", groupId _group, typeOf _vehicle, _isTank, _isAPC];

private _done = false;
private _lastWpTime = 0;
private _lastWpPos = [0,0,0];

while { !_done } do {
	if (!alive _vehicle || { { alive _x } count (units _group) == 0 }) exitWith {
		_done = true;
	};
	if !(call A3A_fnc_planning_isSiegeActive) exitWith {
		_done = true;
	};
	if (A3A_planning_objective != _targetMarker) exitWith {
		_done = true;
	};
	if ((sidesX getVariable [_targetMarker, sideUnknown]) == teamPlayer) exitWith {
		_done = true;
	};

	private _curTgt = getMarkerPos _targetMarker;
	if (_curTgt distance2D [0, 0, 0] < 1) then { _curTgt = _targetPos; };
	private _curPos = getPosATL _vehicle;

	// Target acquisition within 800m or anywhere within the objective AO
	private _nearEnemies = allUnits select {
		alive _x && {
			(side (group _x) in [Occupants, Invaders] || side _x in [Occupants, Invaders])
		} && {
			!captive _x && {
				lifeState _x != "INCAPACITATED" && {
					!(_x getVariable ["incapacitated", false]) && {
						!(_x getVariable ["ACE_isUnconscious", false]) && {
							!(_x getVariable ["surrendered", false]) && {
								(_x distance2D _curPos < 800) || {
									if (!isNil "A3A_fnc_planning_isInsideAO") then {
										[_x, _targetMarker] call A3A_fnc_planning_isInsideAO
									} else {
										_x distance2D _curTgt < 600
									}
								}
							}
						}
					}
				}
			}
		}
	};

	private _gunner = gunner _vehicle;
	private _driver = driver _vehicle;

	// Prioritize: 1. Enemy armed vehicles/tanks, 2. Statics, 3. Closest infantry
	if (count _nearEnemies > 0) then {
		private _chosenTarget = objNull;
		private _enemyVehs = _nearEnemies select { (vehicle _x) != _x };
		if (count _enemyVehs > 0) then {
			_chosenTarget = _enemyVehs select 0;
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
			if (!isNull _gunner && { alive _gunner }) then {
				_gunner doTarget _chosenTarget;
				_gunner doFire _chosenTarget;
				[_gunner, getPosATL _chosenTarget] remoteExec ["A3A_fnc_planning_localDoWatch", owner _gunner];
			};
			if (!isNull _driver && { alive _driver }) then {
				_driver doTarget _chosenTarget;
			};
		};
	};

	// Determine active tactical target (assigned enemy cluster or base objective)
	private _clearingTarget = _group getVariable ["siege_clearingTarget", [0, 0, 0]];
	private _activeTarget = if (_clearingTarget isNotEqualTo [0, 0, 0]) then { _clearingTarget } else { _curTgt };

	// Query friendly assault infantry anchor
	([_activeTarget] call A3A_fnc_planning_getAssaultAnchor) params ["_hasAdvanced", "_anchorPos", "_anchorDist"];

	private _desiredPos = _curPos;
	private _speedSetting = "NORMAL";

	// Assign a persistent lateral flank offset per vehicle group (-45m to +45m) to avoid driving in the exact line of infantry
	private _flankOffset = _group getVariable ["siege_vehFlankOffset", nil];
	if (isNil "_flankOffset") then {
		_flankOffset = selectRandom [-45, -30, 30, 45];
		_group setVariable ["siege_vehFlankOffset", _flankOffset, true];
	};

	if (_anchorDist >= 0 && { count _anchorPos == 3 }) then {
		// Friendly assault infantry is active!
		if (!_hasAdvanced) then {
			// Infantry is still assembling or moving up from staging - hold position and support
			_desiredPos = _curPos;
			_speedSetting = "LIMITED";
		} else {
			// Calculate standoff support position behind the infantry anchor with lateral flank offset
			private _dirToTgt = _anchorPos vectorFromTo _activeTarget;
			if (_dirToTgt isEqualTo [0, 0, 0]) then { _dirToTgt = [0, 1, 0]; };
			private _normDir = vectorNormalized _dirToTgt;
			private _perpDir = [-(_normDir select 1), (_normDir select 0), 0];

			// Apply lateral variance (±12m) and longitudinal standoff variance (±15m)
			private _standoffVar = (_standoffBehindInfantry + (random 20 - 10)) max 35;
			private _lateralVar = _flankOffset + (random 16 - 8);

			// Desired position is behind the friendly infantry + offset to the flank
			_desiredPos = _anchorPos vectorAdd (_normDir vectorMultiply -_standoffVar) vectorAdd (_perpDir vectorMultiply _lateralVar);

			// Ensure vehicle doesn't push closer to target than minimum combat standoff
			if (_desiredPos distance2D _activeTarget < _minStandoffFromTarget) then {
				private _dirFromSpawn = (_group getVariable ["siege_spawnPos", _curPos]) vectorFromTo _activeTarget;
				if (_dirFromSpawn isEqualTo [0,0,0]) then { _dirFromSpawn = [0,1,0]; };
				_desiredPos = _activeTarget vectorAdd ((vectorNormalized _dirFromSpawn) vectorMultiply -_minStandoffFromTarget) vectorAdd (_perpDir vectorMultiply _lateralVar);
			};

			// Adjust speed based on distance to infantry anchor
			private _distToInfantry = _curPos distance2D _anchorPos;
			if (_distToInfantry > 160) then {
				_speedSetting = "FULL"; // Catch up if left far behind
			} else {
				if (_curPos distance2D _activeTarget < _anchorDist) then {
					// Vehicle is ahead of infantry! Slow down to let infantry advance
					_speedSetting = "LIMITED";
				} else {
					_speedSetting = "NORMAL";
				};
			};
		};
	} else {
		// No friendly infantry active (or all KIA) - vehicle acts as primary assault with standoff and flank offset
		private _spawnPos = _group getVariable ["siege_spawnPos", _curPos];
		private _approachDir = _spawnPos vectorFromTo _activeTarget;
		if (_approachDir isEqualTo [0, 0, 0]) then { _approachDir = [0, 1, 0]; };
		private _normApproach = vectorNormalized _approachDir;
		private _perpDir = [-(_normApproach select 1), (_normApproach select 0), 0];

		private _standoffVar = (_minStandoffFromTarget + (random 25 - 12)) max 60;
		_desiredPos = _activeTarget vectorAdd (_normApproach vectorMultiply -_standoffVar) vectorAdd (_perpDir vectorMultiply (_flankOffset + (random 16 - 8)));
		_speedSetting = "NORMAL";
	};

	// Multi-vehicle separation: check nearby friendly vehicles to prevent bumper-to-bumper collisions
	private _otherFriendlyVehs = (vehicles select {
		alive _x && { _x != _vehicle } && { side _x == teamPlayer } && { (_x distance2D _desiredPos) < 25 }
	});
	if (count _otherFriendlyVehs > 0) then {
		private _otherVeh = _otherFriendlyVehs select 0;
		private _pushDir = (getPosATL _otherVeh) vectorFromTo _desiredPos;
		if (_pushDir isEqualTo [0, 0, 0]) then { _pushDir = [random 2 - 1, random 2 - 1, 0]; };
		_desiredPos = _desiredPos vectorAdd ((vectorNormalized _pushDir) vectorMultiply 30);
	};

	// Periodically update waypoint towards desired standoff position
	if ((_curPos distance2D _desiredPos > 25) && { (time - _lastWpTime > 8) || (_desiredPos distance2D _lastWpPos > 30) || (count (waypoints _group) == 0) }) then {
		_lastWpTime = time;
		_lastWpPos = _desiredPos;

		for "_i" from (count (waypoints _group) - 1) to 0 step -1 do { deleteWaypoint [_group, _i]; };
		private _wp = _group addWaypoint [_desiredPos, 0];
		_wp setWaypointType "SAD";
		_wp setWaypointBehaviour "COMBAT";
		_wp setWaypointCombatMode "RED";
		_wp setWaypointSpeed _speedSetting;
		_wp setWaypointCompletionRadius 35;
		[_group, _wp select 1] remoteExec ["A3A_fnc_planning_localSetCurrentWaypoint", groupOwner _group];

		_group setBehaviour "COMBAT";
		_group setCombatMode "RED";
		_group setSpeedMode _speedSetting;

		if (!isNull _driver && { alive _driver }) then {
			[_driver, _desiredPos] remoteExec ["A3A_fnc_planning_localDoMove", owner _driver];
		};
	};

	sleep 5;
};