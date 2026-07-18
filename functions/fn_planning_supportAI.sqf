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

// --- Event thresholds ---
// Mortars now hold much closer to the frontline, relocate in short 150-300m hops instead of
// jumping across the map, and can engage out to roughly half their effective range (~3000m)
// so they start contributing fire much earlier. MG teams still hug the advancing infantry.
private _idealDist = if (_isMortar) then {
	125
} else {
	100
};   // Mortar ~100-150m behind frontline (was 500m) / MG ~100m behind frontline
private _maxDist = if (_isMortar) then {
	700
} else {
	180
};   // "frontline/targets out of effective range"
private _dangerDist = if (_isMortar) then {
	150
} else {
	50
};    // "position heavily threatened"
private _originalCount = count (units _group);

// Mortars need a longer minimum dwell time than MG teams so a single momentary LOS/range
// blip doesn't trigger an immediate pack-up right after deploying.
private _minDwellTime = if (_isMortar) then {
	25
} else {
	15
};
private _lastDeployTime = 0;

// Mortar Balance: a crew may only assemble its tube twice per siege. Once that's spent
// (packed up, lost, or abandoned a second time) the survivors permanently convert to
// ordinary assault infantry rather than deploying a third mortar.
private _maxMortarDeployments = 2;
private _mortarDeployCount = 0;

// --- Mortar ammo Cap ---
// Hardcoded (no longer lobby-tweakable): 16 rounds per mortar crew before converting to infantry.
private _maxMortarRoundsCfg = 16;
private _mortarAmmoUnlimited = (_maxMortarRoundsCfg <= 0);
private _mortarRoundsFired = 0;

private _confirmNeeded = if (_isMortar) then {
	5
} else {
	3
};
private _minClusterSize = 2;
private _mortarFireCooldown = 20;
private _mortarRoundsPerBurst = 4;

// The FIRST mortar deployment assembles immediately wherever the crew currently stands
// (their staging position), instead of marching out to a calculated standoff point first.
private _firstDeployment = true;

private _isFirstApproach = true;
private _clusterMissStreak = 0;
private _maxClusterMisses = 3; // after this many empty cycles, drop the cluster requirement to 1

// MG teams (not mortars) will break off early to deploy if they spot a live target while
// still en route to their calculated standoff point.
private _earlyEngageRange = 250;

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

// MG-only: reject candidates that are technically clear but buried in forest/heavy
// vegetation - these give a bad or nonexistent firing arc even though _fnc_hasLOS
// might pass on the single line sampled to the frontline anchor.
private _fnc_hasClearFiringArc = {
	params ["_pos", "_losTarget"];
	if !([_pos, _losTarget] call _fnc_hasLOS) exitWith {
		false
	};

	    // Reject if the position itself is choked with trees/bushes (poor firing arc even
	    // with a clear center line - foliage this dense blocks peripheral sightlines).
	private _foliageCount = count ((_pos nearObjects ["Tree", 12]) + (_pos nearObjects ["Bush", 12]));
	if (_foliageCount > 6) exitWith {
		false
	};

	    // Sample two lateral offsets either side of the direct line to the frontline anchor
	    // to confirm an actual arc exists, not just one lucky unobstructed pixel.
	private _dir = _pos vectorFromTo _losTarget;
	private _mag2D = sqrt ((_dir select 0)^2 + (_dir select 1)^2);
	if (_mag2D < 0.01) exitWith {
		true
	};
	private _perp = [-(_dir select 1) / _mag2D, (_dir select 0) / _mag2D, 0];
	private _sample1 = _losTarget vectorAdd (_perp vectorMultiply 20);
	private _sample2 = _losTarget vectorAdd (_perp vectorMultiply -20);
	private _clearSamples = 0;
	if ([_pos, _sample1] call _fnc_hasLOS) then {
		_clearSamples = _clearSamples + 1;
	};
	if ([_pos, _sample2] call _fnc_hasLOS) then {
		_clearSamples = _clearSamples + 1;
	};
	_clearSamples >= 1
};

private _fnc_findPos = {
	params ["_dirAnchor", "_biasFrom", "_dist", "_losTarget", ["_requireArc", false, [false]]];
	private _dir = _dirAnchor vectorFromTo _biasFrom;
	if (_dir isEqualTo [0, 0, 0]) then {
		_dir = [1, 0, 0];
	};
	private _angles = [0, -30, 30, -60, 60, -90, 90, -120, 120, 150, -150, 180];
	private _best = [];

	{
		private _testDir = [_dir, _x] call _fnc_rotateDir;
		private _cand = _biasFrom vectorAdd (_testDir vectorMultiply _dist);
		private _safe = [_cand, 0, 40, 3, 0, 0.7, 0] call BIS_fnc_findSafePos;
		if (count _safe == 2) then {
			private _cPos = [_safe select 0, _safe select 1, 0];
			private _qualifies = if (_requireArc) then {
				[_cPos] call _fnc_isValidGroundPos && {
					[_cPos, _losTarget] call _fnc_hasClearFiringArc
				}
			} else {
				[_cPos] call _fnc_isValidGroundPos && {
					[_cPos, _losTarget] call _fnc_hasLOS
				}
			};
			if (_qualifies) exitWith {
				_best = _cPos;
			};
		};
	} forEach _angles;

	if (_best isEqualTo []) then {
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
	};

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

diag_log format ["[A3A Tweaks] Event-driven Support AI started for group: %1, Type: %2", groupId _group, _type];

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
private _done = false;
private _lastFireTime = 0;

private _confirmNeeded = if (_isMortar) then {
	5
} else {
	3
};
private _cRange = 0;
private _cLOS = 0; private _cNoTargets = 0;

while { !_done } do {
	if (!alive (leader _group) || {
		count (units _group) == 0
	}) exitWith {
		_done = true;
	};
	if ((sidesX getVariable [_targetMarker, sideUnknown]) == teamPlayer) exitWith {
		_done = true;
	};

	    // --- Mortar Balance: deployments/ammunition exhausted, graduate the survivors to assault infantry ---
	if (_isMortar && {
		_mortarDeployCount >= _maxMortarDeployments || {
			!_mortarAmmoUnlimited && {
				_mortarRoundsFired >= _maxMortarRoundsCfg
			}
		}
	}) exitWith {
		diag_log format ["[A3A Tweaks] %1 has expended its deployments/ammunition (%2/%3 rounds fired). Surviving crew converting to assault infantry.", groupId _group, _mortarRoundsFired, _maxMortarRoundsCfg];
		if (!isNull _staticVeh) then {
			{
				unassignVehicle _x;
				[_x] orderGetIn false;
			} forEach (crew _staticVeh);
			deleteVehicle _staticVeh;
			_staticVeh = objNull;
		};
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

	    // --- Pack up any existing emplacement before relocating ---
	if (!isNull _staticVeh) then {
		{
			unassignVehicle _x;
			[_x] orderGetIn false;
		} forEach (crew _staticVeh);
		deleteVehicle _staticVeh;
		_staticVeh = objNull; sleep 1;
	};
	_cRange = 0;
	_cLOS = 0; _cNoTargets = 0;

	private _curTargetPos = getMarkerPos _targetMarker;
	if (_curTargetPos distance2D [0, 0, 0] < 1) then {
		_curTargetPos = _targetPos;
	};

	private _reached = false;
	private _earlyDeploy = false;

	if (_isMortar && _firstDeployment) then {
		// Assemble right here, right now - no march to a standoff point first.
		for "_i" from (count (waypoints _group) - 1) to 0 step -1 do {
			deleteWaypoint [_group, _i];
		};
		{
			doStop _x;
		} forEach (units _group);
		_reached = true;
	} else {
		([_curTargetPos, !_isFirstApproach] call _fnc_frontlinePos) params ["_biasPos", "_haveBattlePoint"];

		        // Don't push up to standoff distance from the objective until our own assault
		        // squads have actually made contact — otherwise this fires from the very first
		        // tick (defenders are always "near" their own base) and sends support/vehicle
		        // elements right up to the enemy's doorstep alone.
		if (!_haveBattlePoint) then {
			_isFirstApproach = false;
			sleep 10;
			continue;
		};

		private _searchAnchor = _biasPos;
		private _deployPos = [_curTargetPos, _searchAnchor, _idealDist, _searchAnchor, !_isMortar] call _fnc_findPos;

		        // --- 1. move to the support position ---
		for "_i" from (count (waypoints _group) - 1) to 0 step -1 do {
			deleteWaypoint [_group, _i];
		};
		private _wp = _group addWaypoint [_deployPos, 0];
		_wp setWaypointType "MOVE";
		_wp setWaypointCompletionRadius 50;
		[_group, _wp select 1] remoteExec ["A3A_fnc_planning_localSetCurrentWaypoint", groupOwner _group];
		_group setBehaviour "AWARE";
		        // MG teams travel like an assault squad (can fight their way there); mortars stay cautious.
		_group setCombatMode (if (_isMortar) then {
			"YELLOW"
		} else {
			"RED"
		});
		_group setSpeedMode "NORMAL";
		{
			[_x, _deployPos] remoteExec ["A3A_fnc_planning_localDoMove", owner _x];
		} forEach (units _group);

		private _moveTimeout = time + 120;
		while { true } do {
			if (!alive (leader _group) || {
				count (units _group) == 0
			}) exitWith {
				_done = true;
			};
			if ((sidesX getVariable [_targetMarker, sideUnknown]) == teamPlayer) exitWith {
				_done = true;
			};
			if ((leader _group) distance2D _deployPos < 25) exitWith {
				_reached = true;
			};

			if (!_isMortar) then {
				private _curLeaderPos = getPosATL (leader _group);
				private _engageIdx = allUnits findIf {
					alive _x && {
						side _x in [Occupants, Invaders]
					} && {
						_x distance2D _curLeaderPos < _earlyEngageRange
					} && {
						[_curLeaderPos, getPosATL _x] call _fnc_hasLOS
					}
				};
				                // MG teams must be able to set up their emplacement even while pinned/suppressed, 
				                // instead of only reacting to a spotted enemy with clean LOS.
				private _isSuppressed = (getSuppression (leader _group)) > 0.6;
				if (_engageIdx != -1 || {
					_isSuppressed
				}) exitWith {
					_reached = true;
					_earlyDeploy = true;
				};
			};

			if (time > _moveTimeout) exitWith {
				// Timed out trying to physically reach the ideal standoff point - almost always
				                // because the crew is pinned by suppression on the way there. Deploy right where
				                // they are rather than looping back to retry the same approach forever.
				if (!_isMortar) then {
					_reached = true;
					_earlyDeploy = true;
				};
			};
			sleep 2;
		};
		if (_done) exitWith {};
		if (!_reached) then {
			continue;
		};

		if (_earlyDeploy) then {
			{
				doStop _x;
			} forEach (units _group);
			for "_i" from (count (waypoints _group) - 1) to 0 step -1 do {
				deleteWaypoint [_group, _i];
			};
			diag_log format ["[A3A Tweaks] %1 stopping early to deploy - enemy contact during approach.", groupId _group];
		};
	};

	_isFirstApproach = false;

	    // --- 2. Assemble & occupy the emplacement ---
	_staticVeh = createVehicle [_staticClass, getPosATL (leader _group), [], 0, "NONE"];
	[_staticVeh, teamPlayer] call A3A_fnc_AIVEHinit;
	_staticVeh allowCrewInImmobile true;
	_lastDeployTime = time;
	private _gunner = selectRandom (units _group);
	_watcher = ((units _group) - [_gunner]) param [0, objNull];
	[_gunner, _staticVeh] remoteExec ["A3A_fnc_planning_localMoveInGunner", owner _gunner];
	{
		removeBackpackGlobal _x;
	} forEach (units _group);
	_group setBehaviour "COMBAT";
	{
		_x setUnitPos "AUTO";
	} forEach (units _group);

	if (_isMortar) then {
		_mortarDeployCount = _mortarDeployCount + 1;
		_firstDeployment = false;
		diag_log format ["[A3A Tweaks] %1 deployed %2 (deployment %3/%4). Holding until a relocation event fires.", groupId _group, _staticClass, _mortarDeployCount, _maxMortarDeployments];
	} else {
		diag_log format ["[A3A Tweaks] %1 deployed %2 at %3m. Holding until a relocation event fires.", groupId _group, _staticClass, _idealDist];
	};

	    // --- 3. Hold and fight until a relocation event fires ---
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
			diag_log "[A3A Tweaks] Relocating: position threatened.";
		};

		private _liveObjPos = getMarkerPos _targetMarker;
		([_liveObjPos] call _fnc_frontlinePos) params ["_frontPos", "_haveBattlePoint2"];

		if (_haveBattlePoint2) then {
			if (_curPos distance2D _frontPos > _maxDist) then {
				_cRange = _cRange + 1;
			} else {
				_cRange = 0;
			};
			if !([_curPos, _frontPos] call _fnc_hasLOS) then {
				_cLOS = _cLOS + 1;
			} else {
				_cLOS = 0;
			};
		} else {
			_cRange = 0;
			_cLOS = 0;
		};

		        // Mortars only ever consider targets tied to the ACTIVE objective: inside the AO
		        // radius around the objective marker, or actively engaged with/near the advancing
		        // frontline. A stray patrol or roadblock crew 2km away no longer qualifies just
		        // because it's within mortar range - it has to be relevant to this siege.
		        // Hardcoded (no longer lobby-tweakable): 600m mortar area-of-operations radius.
		private _aoRadius = 600;
		private _fnc_isOnObjective = {
			params ["_unit"];
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

		private _mortarCandidates = if (_isMortar) then {
			allUnits select {
				alive _x && {
					side _x in [Occupants, Invaders]
				} && {
					_x distance2D _curPos < _maxDist
				} && {
					[_x] call _fnc_isOnObjective
				}
			};
		} else {
			[]
		};

		private _targetsInRange = if (_isMortar) then {
			count _mortarCandidates
		} else {
			{
				alive _x && {
					side _x in [Occupants, Invaders]
				} && {
					_x distance2D _curPos < _maxDist
				}
			} count allUnits
		};
		if (_targetsInRange == 0 && {
			_haveBattlePoint2
		}) then {
			_cNoTargets = _cNoTargets + 1;
		} else {
			_cNoTargets = 0;
		};

		if (_cRange >= _confirmNeeded && {
			(time - _lastDeployTime) > _minDwellTime
		}) exitWith {
			_relocate = true;
			diag_log "[A3A Tweaks] Relocating: frontline out of effective range.";
		};
		if (_cLOS >= _confirmNeeded && {
			(time - _lastDeployTime) > _minDwellTime
		}) exitWith {
			_relocate = true;
			diag_log "[A3A Tweaks] Relocating: LOS to the battle lost.";
		};
		if (_cNoTargets >= _confirmNeeded && {
			(time - _lastDeployTime) > _minDwellTime
		}) exitWith {
			_relocate = true;
			diag_log "[A3A Tweaks] Relocating: no enemies in engagement range.";
		};

		private _targetsNearAO = if (_isMortar) then {
			_mortarCandidates
		} else {
			allUnits select {
				alive _x && {
					side _x in [Occupants, Invaders]
				} && {
					_x distance2D _liveObjPos < 350
				}
			}
		};

		if (count _targetsNearAO > 0) then {
			if (_isMortar && {
				time - _lastFireTime > _mortarFireCooldown
			} && {
				_mortarAmmoUnlimited || {
					_mortarRoundsFired < _maxMortarRoundsCfg
				}
			}) then {
				// Prune expired target claims made by other mortar teams
				if (isNil "A3A_planning_activeMortarTargets") then {
					A3A_planning_activeMortarTargets = [];
				};
				A3A_planning_activeMortarTargets = A3A_planning_activeMortarTargets select {
					(_x select 1) > time
				};

				                // rank candidates by local clustering - lone stragglers no longer justify a mission
				private _clusterRadius = 60;
				private _rankedTargets = _targetsNearAO apply {
					private _candPos = getPosATL _x;
					[_x, _candPos, ({
						_x distance2D _candPos < _clusterRadius
					} count _targetsNearAO)]
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

					                    // Hardcoded (no longer lobby-tweakable): 40m mortar friendly-fire safety radius.
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
			if (!_isMortar && {
				!isNull _watcher
			}) then {
				private _closest = _targetsNearAO select 0;
				private _cd = 1e9;
				{
					private _d = _x distance2D _curPos;
					if (_d < _cd) then {
						_cd = _d;
						_closest = _x;
					};
				} forEach _targetsNearAO;
				[_watcher, getPosATL _closest] remoteExec ["A3A_fnc_planning_localDoWatch", owner _watcher];
			};
		} else {
			if (!_isMortar && {
				!isNull _watcher
			}) then {
				[_watcher, _liveObjPos] remoteExec ["A3A_fnc_planning_localDoWatch", owner _watcher];
			};
		};

		sleep 10;
	};
	if (_done) exitWith {};
};

if (!isNull _staticVeh && {
	(sidesX getVariable [_targetMarker, sideUnknown]) != teamPlayer
} && {
	!alive (leader _group)
}) then {
	deleteVehicle _staticVeh;
};