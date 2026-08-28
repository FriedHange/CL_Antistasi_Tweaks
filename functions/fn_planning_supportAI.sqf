params ["_group", "_type", "_targetMarker", "_targetPos"];
if (isNull _group) exitWith {};

private _syncRetries = 0;
while {
	count (units _group) == 0 && {
		_syncRetries < 30
	}
} do {
	sleep 0.5;
	_syncRetries = _syncRetries + 1;
};
private _leadRetries = 0;
while {
	isNull (leader _group) && {
		_leadRetries < 20
	}
} do {
	sleep 0.5;
	_leadRetries = _leadRetries + 1;
};
if (isNull (leader _group) || {
	count (units _group) == 0
}) exitWith {
	diag_log format ["[A3A Tweaks] Support AI aborted: sync failed for group %1.", _group];
};
for "_i" from (count (waypoints _group) - 1) to 0 step -1 do {
	deleteWaypoint [_group, _i];
};

private _isMortar = _type in ["Mortar", "Mortar_FALLBACK"];
private _sidePrefix = if (teamPlayer == west) then {
	"B"
} else {
	if (teamPlayer == east) then {
		"O"
	} else {
		"I"
	}
};

private _fnc_resolveStatic = {
	params ["_key", "_fallback"];
	private _list = A3A_faction_reb getOrDefault [_key, []];
	private _found = "";
	{
		if (!isNil "_x" && {
			_x != "" && {
				isClass (configFile >> "CfgVehicles" >> _x)
			}
		}) exitWith {
			_found = _x;
		};
	} forEach _list;
	if (_found == "") then {
		_found = if (isClass (configFile >> "CfgVehicles" >> _fallback)) then {
			_fallback
		} else {
			"I_HMG_01_high_F"
		};
	};
	_found
};
private _staticClass = if (_isMortar) then {
	["staticMortars", _sidePrefix + "_Mortar_01_F"] call _fnc_resolveStatic
} else {
	["staticMGs", _sidePrefix + "_HMG_01_high_F"] call _fnc_resolveStatic
};
if (_staticClass == "" || {
	!isClass (configFile >> "CfgVehicles" >> _staticClass)
}) exitWith {
	diag_log "[A3A Tweaks] Support AI failed: no valid static classname found.";
};

// --- Backpack preservation & restoration helpers ---
private _fnc_preserveBagsOnDeploy = {
	params ["_grp"];
	private _wBag = _grp getVariable ["siege_weaponBag", ""];
	private _sBag = _grp getVariable ["siege_supportBag", ""];
	private _alive = (units _grp) select { alive _x };
	if (count _alive > 0 && { _wBag == "" && { backpack (_alive # 0) != "" } }) then {
		_wBag = backpack (_alive # 0);
		_grp setVariable ["siege_weaponBag", _wBag, true];
	};
	if (count _alive > 1 && { _sBag == "" && { backpack (_alive # 1) != "" } }) then {
		_sBag = backpack (_alive # 1);
		_grp setVariable ["siege_supportBag", _sBag, true];
	};
	{
		if (backpack _x != "") then {
			_x setVariable ["CL_savedBackpack", backpack _x, true];
		};
		removeBackpackGlobal _x;
	} forEach (units _grp);
};

private _fnc_restoreBagsOnDisassemble = {
	params ["_grp"];
	private _wBag = _grp getVariable ["siege_weaponBag", ""];
	private _sBag = _grp getVariable ["siege_supportBag", ""];
	private _alive = (units _grp) select { alive _x };
	if (count _alive > 0) then {
		private _u1 = _alive # 0;
		private _saved1 = _u1 getVariable ["CL_savedBackpack", _wBag];
		if (_saved1 == "") then { _saved1 = _wBag; };
		if (backpack _u1 == "" && { _saved1 != "" }) then {
			_u1 addBackpackGlobal _saved1;
		};
	};
	if (count _alive > 1) then {
		private _u2 = _alive # 1;
		private _saved2 = _u2 getVariable ["CL_savedBackpack", _sBag];
		if (_saved2 == "") then { _saved2 = _sBag; };
		if (backpack _u2 == "" && { _saved2 != "" }) then {
			_u2 addBackpackGlobal _saved2;
		};
	};
};

// --- Event thresholds ---
private _idealDist = if (_isMortar) then {
	125
} else {
	200
};
private _maxDist = if (_isMortar) then {
	3500
} else {
	750
};
private _dangerDist = 35;
private _originalCount = count (units _group);

// Minimum dwell time before evaluating relocation
private _minDwellTime = if (_isMortar) then {
	25
} else {
	20
};
private _lastDeployTime = 0;

// Mortar Balance: a crew may only assemble its tube twice per siege. Once that's spent
// the survivors permanently convert to assault infantry.
private _maxMortarDeployments = 2;
private _mortarDeployCount = 0;

// --- Mortar ammo Cap ---
private _maxMortarRoundsCfg = 16;
private _mortarAmmoUnlimited = (_maxMortarRoundsCfg <= 0);
private _mortarRoundsFired = 0;

private _confirmNeeded = if (_isMortar) then {
	5
} else {
	2
};
private _minClusterSize = 2;
private _mortarFireCooldown = 20;
private _mortarRoundsPerBurst = 4;

// The FIRST mortar deployment assembles immediately wherever the crew currently stands
private _firstDeployment = true;
private _isFirstApproach = true;
private _clusterMissStreak = 0;
private _maxClusterMisses = 3;

private _fnc_rotateDir = {
	params ["_dir", "_deg"];
	[(_dir select 0) * cos(_deg) - (_dir select 1) * sin(_deg),
	(_dir select 0) * sin(_deg) + (_dir select 1) * cos(_deg), 0]
};
private _fnc_hasLOS = {
	params ["_fromPos", "_toPos"];
	private _from = ATLToASL (_fromPos vectorAdd [0, 0, 1.6]);
	private _to = ATLToASL (_toPos vectorAdd [0, 0, 1.6]);
	(!terrainIntersectASL [_from, _to]) && {
		!lineIntersects [_from, _to, objNull, objNull]
	}
};

private _fnc_isValidGroundPos = {
	params ["_pos"];
	if (_pos isEqualTo []) exitWith {
		false
	};
	if (surfaceIsWater _pos) exitWith {
		false
	};
	private _normal = surfaceNormal _pos;
	if ((_normal select 2) < 0.78) exitWith {
		false
	};
	private _blockers = (_pos nearObjects ["House", 4]) + (_pos nearObjects ["Building", 4]) + (_pos nearObjects ["Rocks", 4]) + (_pos nearObjects ["Rock", 4]);
	if (count _blockers > 0) exitWith {
		false
	};
	true
};

// Helper to query living enemy units in direct Line of Sight
private _fnc_findEnemiesInLOS = {
	params ["_fromPos", "_range"];
	private _visible = allUnits select {
		alive _x && {
			side _x in [Occupants, Invaders] && {
				!(_x getVariable ["incapacitated", false]) && {
					_x distance2D _fromPos <= _range && {
						[_fromPos, getPosATL _x] call _fnc_hasLOS
					}
				}
			}
		}
	};
	_visible
};

// Position finder for mortars and approach waypoints
private _fnc_findPos = {
	params ["_dirAnchor", "_biasFrom", "_dist", "_losTarget", ["_requireArc", false, [false]]];
	private _dir = _dirAnchor vectorFromTo _biasFrom;
	if (_dir isEqualTo [0, 0, 0]) then {
		_dir = [1, 0, 0];
	};
	private _angles = [0, -30, 30, -60, 60, -90, 90, -120, 120, 150, -150, 180];
	private _candidates = [];

	{
		private _testDir = [_dir, _x] call _fnc_rotateDir;
		private _cand = _biasFrom vectorAdd (_testDir vectorMultiply _dist);
		private _safe = [_cand, 0, 45, 3, 0, 0.7, 0] call BIS_fnc_findSafePos;
		if (count _safe == 2) then {
			private _cPos = [_safe select 0, _safe select 1, 0];
			private _qualifies = [_cPos] call _fnc_isValidGroundPos && {
				[_cPos, _losTarget] call _fnc_hasLOS
			};
			if (_qualifies) then {
				private _elev = getTerrainHeightASL _cPos;
				_candidates pushBack [_cPos, _elev];
			};
		};
	} forEach _angles;

	if (count _candidates > 0) exitWith {
		_candidates = [_candidates, [], { _x select 1 }, "DESCEND"] call BIS_fnc_sortBy;
		(_candidates select 0) select 0
	};

	private _best = [];
	{
		private _testDir = [_dir, _x] call _fnc_rotateDir;
		private _cand = _biasFrom vectorAdd (_testDir vectorMultiply _dist);
		private _safe = [_cand, 0, 60, 4, 0, 0.7, 0] call BIS_fnc_findSafePos;
		if (count _safe == 2) then {
			private _cPos = [_safe select 0, _safe select 1, 0];
			if ([_cPos] call _fnc_isValidGroundPos) exitWith {
				_best = _cPos;
			};
		};
	} forEach _angles;

	if (_best isEqualTo []) then {
		private _radius = 60;
		private _tries = 0;
		while {
			_best isEqualTo [] && {
				_tries < 6
			}
		} do {
			private _safe = [_biasFrom, 0, _radius, 4, 0, 0.7, 0] call BIS_fnc_findSafePos;
			if (count _safe == 2) then {
				private _cPos = [_safe select 0, _safe select 1, 0];
				if ([_cPos] call _fnc_isValidGroundPos) then {
					_best = _cPos;
				};
			};
			_radius = _radius + 40;
			_tries = _tries + 1;
		};
	};

	if (_best isEqualTo [] && {
		[_biasFrom] call _fnc_isValidGroundPos
	}) then {
		_best = _biasFrom;
	};
	if (_best isEqualTo []) then {
		_best = _biasFrom;
	};
	_best
};

diag_log format ["[A3A Tweaks] Support AI active for group: %1, Type: %2", groupId _group, _type];

private _fnc_frontlinePos = {
	params ["_objPos", ["_allowFallback", true, [true]]];
	([_objPos] call A3A_fnc_planning_getAssaultAnchor) params ["_advanced", "_anchorPos", "_anchorDist"];
	if (_anchorDist >= 0) exitWith {
		[_anchorPos, true]
	};
	if (_anchorDist == -1) exitWith {
		[_objPos, true]
	};
	if (!_allowFallback) exitWith {
		[_objPos, false]
	};
	private _nearEnemies = allUnits select {
		alive _x && {
			side _x in [Occupants, Invaders]
		} && {
			_x distance2D _objPos < 350
		}
	};
	if (count _nearEnemies > 0) exitWith {
		[(_nearEnemies select 0) call {
			getPosATL _this
		}, true]
	};
	[_objPos, false]
};

private _staticVeh = objNull;
private _watcher = objNull;
private _gunner = objNull;
private _done = false;
private _lastFireTime = 0;

private _cRange = 0;
private _cLOS = 0;
private _cNoTargets = 0;

while { !_done } do {
	if (isNull _group || { { alive _x } count (units _group) == 0 }) exitWith {
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

	// --- Mortar Balance: deployments/ammunition exhausted, graduate survivors to assault infantry ---
	if (_isMortar && {
		_mortarDeployCount >= _maxMortarDeployments || {
			!_mortarAmmoUnlimited && {
				_mortarRoundsFired >= _maxMortarRoundsCfg
			}
		}
	}) exitWith {
		diag_log format ["[A3A Tweaks] %1 has expended its mortar deployments/ammunition (%2/%3 rounds fired). Surviving crew converting to assault infantry.", groupId _group, _mortarRoundsFired, _maxMortarRoundsCfg];
		_group setVariable ["siege_role", "ASSAULT", true];
		_group setVariable ["siege_isStaticDeployed", false, true];
		_group setVariable ["siege_staticVehicle", objNull, true];
		if (!isNull _staticVeh) then {
			{
				unassignVehicle _x;
				[_x] orderGetIn false;
			} forEach (crew _staticVeh);
			deleteVehicle _staticVeh;
			_staticVeh = objNull;
		};
		[_group] call _fnc_restoreBagsOnDisassemble;
		for "_i" from (count (waypoints _group) - 1) to 0 step -1 do {
			deleteWaypoint [_group, _i];
		};
		private _wp = _group addWaypoint [_targetPos, 0];
		_wp setWaypointType "SAD";
		[_group, _wp select 1] remoteExec ["A3A_fnc_planning_localSetCurrentWaypoint", groupOwner _group];
		_group setBehaviour "AWARE";
		_group setCombatMode "RED"; _group setSpeedMode "NORMAL";
		{
			[_x, _targetPos] remoteExec ["A3A_fnc_planning_localDoMove", owner _x];
		} forEach (units _group);
		_done = true;
	};
	if (_done) exitWith {};

	// --- Pack up any existing emplacement before moving & restore backpacks ---
	if (!isNull _staticVeh) then {
		{
			unassignVehicle _x;
			[_x] orderGetIn false;
		} forEach (crew _staticVeh);
		deleteVehicle _staticVeh;
		_staticVeh = objNull;
		_group setVariable ["siege_isStaticDeployed", false, true];
		_group setVariable ["siege_staticVehicle", objNull, true];
		[_group] call _fnc_restoreBagsOnDisassemble;
		sleep 1;
	};
	_cRange = 0;
	_cLOS = 0; _cNoTargets = 0;

	private _curTargetPos = getMarkerPos _targetMarker;
	if (_curTargetPos distance2D [0, 0, 0] < 1) then {
		_curTargetPos = _targetPos;
	};

	private _reached = false;
	private _spottedEnemy = objNull;

	if (_isMortar && _firstDeployment) then {
		// Mortars assemble immediately at staging
		for "_i" from (count (waypoints _group) - 1) to 0 step -1 do {
			deleteWaypoint [_group, _i];
		};
		{
			doStop _x;
		} forEach (units _group);
		_reached = true;
	} else {
		([_curTargetPos, !_isFirstApproach] call _fnc_frontlinePos) params ["_biasPos", "_haveBattlePoint"];

		if (!_haveBattlePoint && _isMortar) then {
			_isFirstApproach = false;
			sleep 10;
			continue;
		};

		private _searchAnchor = if (_haveBattlePoint) then { _biasPos } else { _curTargetPos };
		private _deployPos = [_curTargetPos, _searchAnchor, _idealDist, _searchAnchor, !_isMortar] call _fnc_findPos;

		// Move towards the combat area / support position
		for "_i" from (count (waypoints _group) - 1) to 0 step -1 do {
			deleteWaypoint [_group, _i];
		};
		private _wp = _group addWaypoint [_deployPos, 0];
		_wp setWaypointType "MOVE";
		_wp setWaypointCompletionRadius 35;
		[_group, _wp select 1] remoteExec ["A3A_fnc_planning_localSetCurrentWaypoint", groupOwner _group];
		_group setBehaviour (if (_isMortar) then { "AWARE" } else { "COMBAT" });
		_group setCombatMode "RED";
		_group setSpeedMode "NORMAL";
		{
			[_x, _deployPos] remoteExec ["A3A_fnc_planning_localDoMove", owner _x];
		} forEach (units _group);

		private _moveTimeout = time + 120;
		while { true } do {
			if (!alive (leader _group) || { count (units _group) == 0 }) exitWith {
				_done = true;
			};
			if ((sidesX getVariable [_targetMarker, sideUnknown]) == teamPlayer) exitWith {
				_done = true;
			};

			if (_isMortar) then {
				// Mortars deploy when reaching calculated artillery standoff position
				if ((leader _group) distance2D _deployPos < 25 || time > _moveTimeout) exitWith {
					_reached = true;
				};
			} else {
				// MG squads: ONLY assemble when they have direct Line of Sight to actual alive enemy units!
				private _curLeaderPos = getPosATL (leader _group);
				private _visibleEnemies = [_curLeaderPos, _maxDist] call _fnc_findEnemiesInLOS;

				if (count _visibleEnemies > 0) exitWith {
					// Found real enemies with direct LOS! Assemble here and engage.
					_spottedEnemy = _visibleEnemies select 0;
					_reached = true;
					diag_log format ["[A3A Tweaks] %1 spotted %2 enemy/enemies with direct LOS (closest: %3 at %4m). Assembling MG now.", groupId _group, count _visibleEnemies, typeOf _spottedEnemy, round (_curLeaderPos distance2D _spottedEnemy)];
				};

				// If reached intermediate waypoint without seeing any enemies, advance closer to the frontline/objective
				if ((leader _group) distance2D _deployPos < 20 || time > _moveTimeout) then {
					([_curTargetPos, true] call _fnc_frontlinePos) params ["_newBiasPos", "_newHaveBattle"];
					_deployPos = if (_newHaveBattle) then {
						_newBiasPos vectorAdd [random 30 - 15, random 30 - 15, 0]
					} else {
						_curTargetPos vectorAdd [random 40 - 20, random 40 - 20, 0]
					};
					_moveTimeout = time + 60;
					{
						[_x, _deployPos] remoteExec ["A3A_fnc_planning_localDoMove", owner _x];
					} forEach (units _group);
				};
			};

			sleep 1.5;
		};

		if (_done) exitWith {};
		if (!_reached) then {
			continue;
		};

		// Stop marching before assembly
		{
			doStop _x;
		} forEach (units _group);
		for "_i" from (count (waypoints _group) - 1) to 0 step -1 do {
			deleteWaypoint [_group, _i];
		};
	};

	_isFirstApproach = false;

	// --- 2. Assemble & occupy emplacement (Distance-independent, facing enemies) ---
	private _gunnerPos = getPosATL (leader _group);
	private _lookTarget = if (!isNull _spottedEnemy && { alive _spottedEnemy }) then {
		getPosATL _spottedEnemy
	} else {
		if (!isNil "_biasPos") then { _biasPos } else { _curTargetPos }
	};
	private _targetDir = _gunnerPos getDir _lookTarget;

	_staticVeh = createVehicle [_staticClass, _gunnerPos, [], 0, "NONE"];
	_staticVeh setDir _targetDir;
	_staticVeh setVectorUp (surfaceNormal _gunnerPos);
	[_staticVeh, teamPlayer] call A3A_fnc_AIVEHinit;
	_staticVeh allowCrewInImmobile true;
	_group setVariable ["siege_isStaticDeployed", true, true];
	_group setVariable ["siege_staticVehicle", _staticVeh, true];
	_lastDeployTime = time;

	private _aliveUnits = (units _group) select { alive _x };
	_gunner = _aliveUnits param [0, objNull];
	_watcher = (_aliveUnits - [_gunner]) param [0, objNull];

	if (!isNull _gunner && { !isNull _staticVeh }) then {
		[_gunner, _staticVeh] remoteExec ["A3A_fnc_planning_localMoveInGunner", owner _gunner];
		_gunner setSkill ["spotDistance", 1.0];
		_gunner setSkill ["aimingAccuracy", 0.85];
		_gunner setSkill ["courage", 1.0];
		_gunner doWatch _lookTarget;
		if (!isNull _spottedEnemy) then {
			_gunner reveal [_spottedEnemy, 4];
		};
	};

	// Preserve and strip backpacks during active deployment
	[_group] call _fnc_preserveBagsOnDeploy;

	_group setBehaviour "COMBAT";
	{
		_x setUnitPos "AUTO";
	} forEach (units _group);

	// Assistant repositioning & tactical covering stance
	if (!isNull _watcher && { !isNull _staticVeh }) then {
		private _assistOffset = _staticVeh modelToWorld [-2.5, -1.2, 0];
		private _assistSafe = [_assistOffset, 0, 4, 1, 0, 0.7, 0] call BIS_fnc_findSafePos;
		if (count _assistSafe == 2) then { _assistOffset = [_assistSafe select 0, _assistSafe select 1, 0]; };
		if (_watcher distance2D _staticVeh > 20) then {
			_watcher setPosATL _assistOffset;
		};
		_watcher setUnitPos "MIDDLE";
		_watcher doWatch _lookTarget;
		_watcher doMove _assistOffset;
	};

	if (_isMortar) then {
		_mortarDeployCount = _mortarDeployCount + 1;
		_firstDeployment = false;
		diag_log format ["[A3A Tweaks] %1 deployed %2 (deployment %3/%4). Holding for fire missions.", groupId _group, _staticClass, _mortarDeployCount, _maxMortarDeployments];
	} else {
		diag_log format ["[A3A Tweaks] %1 deployed %2 with direct LOS to enemy at %3m (facing %4 deg).", groupId _group, _staticClass, round (_gunnerPos distance2D _lookTarget), round _targetDir];
	};

	// --- 3. Hold and engage until relocation event fires ---
	private _relocate = false;
	while {
		alive (leader _group) && {
			count (units _group) > 0
		} && {
			alive _staticVeh
		} && {
			!_relocate
		}
	} do {
		if ((sidesX getVariable [_targetMarker, sideUnknown]) == teamPlayer) exitWith {
			_done = true;
		};

		// Gunner casualty replacement: assistant hops into static weapon if gunner falls
		if (alive _staticVeh && { isNull (gunner _staticVeh) || { !alive (gunner _staticVeh) || { (gunner _staticVeh) getVariable ["incapacitated", false] } } }) then {
			private _availableCrew = (units _group) select { alive _x && { !(_x getVariable ["incapacitated", false]) && { _x != (gunner _staticVeh) } } };
			if (count _availableCrew > 0) then {
				private _newGunner = _availableCrew select 0;
				diag_log format ["[A3A Tweaks] %1 gunner down; assistant %2 taking over static weapon.", groupId _group, _newGunner];
				[_newGunner, _staticVeh] remoteExec ["A3A_fnc_planning_localMoveInGunner", owner _newGunner];
				_newGunner setSkill ["spotDistance", 1.0];
				_newGunner setSkill ["aimingAccuracy", 0.85];
				_newGunner setSkill ["courage", 1.0];
				_newGunner doWatch _lookTarget;
				_gunner = _newGunner;
				_watcher = (_availableCrew - [_newGunner]) param [0, objNull];
			};
		};

		private _aliveCount = {
			alive _x
		} count (units _group);
		if (_aliveCount <= (_originalCount / 2)) exitWith {
			_relocate = true;
			diag_log "[A3A Tweaks] Relocating: heavy casualties.";
		};

		private _curPos = getPosATL _staticVeh;
		private _threatsNearUs = {
			alive _x && {
				side _x in [Occupants, Invaders]
			} && {
				_x distance2D _curPos < _dangerDist
			}
		} count allUnits;
		if (_threatsNearUs > 0) exitWith {
			_relocate = true;
			diag_log "[A3A Tweaks] Relocating: position threatened (< 35m).";
		};

		if (!_isMortar) then {
			// For MG teams: actively scan for living enemies in direct Line of Sight
			private _visibleEnemies = [_curPos, _maxDist] call _fnc_findEnemiesInLOS;

			if (count _visibleEnemies > 0) then {
				_cNoTargets = 0;
				private _closest = _visibleEnemies select 0;
				private _closestPos = getPosATL _closest;
				if (!isNull _gunner) then {
					_gunner reveal [_closest, 4];
					_gunner doWatch _closestPos;
				};
				if (!isNull _watcher) then {
					[_watcher, _closestPos] remoteExec ["A3A_fnc_planning_localDoWatch", owner _watcher];
				};
			} else {
				// No enemies in direct LOS anymore
				_cNoTargets = _cNoTargets + 1;
				if (_cNoTargets >= _confirmNeeded && { (time - _lastDeployTime) > _minDwellTime }) exitWith {
					_relocate = true;
					diag_log "[A3A Tweaks] MG Relocating: no enemies in direct Line of Sight. Advancing to re-engage.";
				};
			};
		} else {
			// Mortar logic: indirect AO bombardment
			private _liveObjPos = getMarkerPos _targetMarker;
			([_liveObjPos] call _fnc_frontlinePos) params ["_frontPos", "_haveBattlePoint2"];

			private _aoRadius = if (!isNil "A3A_fnc_planning_getAORadius") then { [_targetMarker] call A3A_fnc_planning_getAORadius } else { 600 };
			private _fnc_isOnObjective = {
				params ["_unit"];
				if (!isNil "A3A_fnc_planning_isInsideAO" && { [_unit, _targetMarker] call A3A_fnc_planning_isInsideAO }) exitWith {
					true
				};
				private _p = getPosATL _unit;
				if (_p distance2D _liveObjPos < _aoRadius) exitWith {
					true
				};
				if (_haveBattlePoint2 && {
					_p distance2D _frontPos < 300
				}) exitWith {
					true
				};
				false
			};

			private _mortarCandidates = allUnits select {
				alive _x && {
					side _x in [Occupants, Invaders]
				} && {
					_x distance2D _curPos < _maxDist
				} && {
					[_x] call _fnc_isOnObjective
				}
			};

			if (count _mortarCandidates > 0 && {
				time - _lastFireTime > _mortarFireCooldown
			} && {
				_mortarAmmoUnlimited || {
					_mortarRoundsFired < _maxMortarRoundsCfg
				}
			}) then {
				if (isNil "A3A_planning_activeMortarTargets") then {
					A3A_planning_activeMortarTargets = [];
				};
				A3A_planning_activeMortarTargets = A3A_planning_activeMortarTargets select {
					(_x select 1) > time
				};

				private _clusterRadius = 60;
				private _rankedTargets = _mortarCandidates apply {
					private _candPos = getPosATL _x;
					[_x, _candPos, ({
						_x distance2D _candPos < _clusterRadius
					} count _mortarCandidates)]
				};
				_rankedTargets = [_rankedTargets, [], {
					_x select 2
				}, "DESCEND"] call BIS_fnc_sortBy;

				private _effectiveMinCluster = if (_clusterMissStreak >= _maxClusterMisses) then {
					1
				} else {
					_minClusterSize
				};

				private _chosen = [];
				{
					_x params ["_cand", "_candPos", "_clusterCount"];
					if (_chosen isEqualTo [] && {
						_clusterCount >= _effectiveMinCluster
					}) then {
						private _alreadyClaimed = A3A_planning_activeMortarTargets findIf {
							(_x select 0) distance2D _candPos < 80
						} != -1;
						if (!_alreadyClaimed) then {
							_chosen = [_candPos, _clusterCount];
						};
					};
				} forEach _rankedTargets;

				if (_chosen isEqualTo []) then {
					_clusterMissStreak = _clusterMissStreak + 1;
				} else {
					_clusterMissStreak = 0;
				};

				if (_chosen isNotEqualTo []) then {
					_chosen params ["_impactBasePos", "_clusterCount"];

					private _ffRadius = 40;
					private _friendliesNearImpact = {
						alive _x && {
							side _x == teamPlayer
						} && {
							_x distance2D _impactBasePos < _ffRadius
						}
					} count allUnits;

					if (_friendliesNearImpact > 0) then {
						diag_log format ["[A3A Tweaks] %1 withheld fire mission - %2 friendly unit(s) within %3m of impact point.", groupId _group, _friendliesNearImpact, _ffRadius];
					} else {
						private _roundsThisMission = if (_mortarAmmoUnlimited) then {
							_mortarRoundsPerBurst
						} else {
							_mortarRoundsPerBurst min (_maxMortarRoundsCfg - _mortarRoundsFired)
						};
						_lastFireTime = time;

						private _distToTarget = _curPos distance2D _impactBasePos;
						private _dispersionRadius = ((15 + _distToTarget * 0.035) min 120) max 15;
						private _ang = random 360;
						private _rad = _dispersionRadius * sqrt (random 1);
						private _dispersedPos = _impactBasePos vectorAdd [_rad * sin _ang, _rad * cos _ang, 0];

						private _mags = magazines _staticVeh;
						if (count _mags > 0) then {
							[_staticVeh, _dispersedPos, _mags # 0, _roundsThisMission] remoteExec ["A3A_fnc_planning_localArtilleryFire", owner _staticVeh];
							_mortarRoundsFired = _mortarRoundsFired + _roundsThisMission;

							A3A_planning_activeMortarTargets pushBack [_impactBasePos, time + _mortarFireCooldown];

							diag_log format ["[A3A Tweaks] %1 fired %2 round(s) at a cluster of %3 enemies (%4/%5 total used).", groupId _group, _roundsThisMission, _clusterCount, _mortarRoundsFired, _maxMortarRoundsCfg];
						};
					};
				};
			};
		};

		sleep 10;
	};
	if (_done) exitWith {};
};

// Siege conclusion cleanup: restore backpacks if surviving
if (!isNull _staticVeh) then {
	if ((sidesX getVariable [_targetMarker, sideUnknown]) == teamPlayer || { count ((units _group) select { alive _x }) > 0 }) then {
		{
			unassignVehicle _x;
			[_x] orderGetIn false;
		} forEach (crew _staticVeh);
		deleteVehicle _staticVeh;
		_staticVeh = objNull;
		_group setVariable ["siege_isStaticDeployed", false, true];
		_group setVariable ["siege_staticVehicle", objNull, true];
		[_group] call _fnc_restoreBagsOnDisassemble;
	} else {
		deleteVehicle _staticVeh;
		_staticVeh = objNull;
	};
};