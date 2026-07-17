/*
    fn_planning_execute.sqf
    Handles the execution phase of the Siege Planning Rework with simulated travel delay.
    Runs on the server. Validates deployment squads against active mod configs, deducts resource
    costs for valid squads only, calculates travel times, and triggers spawning/support loops.
*/

disableSerialization;
params [
    ["_mode", "", [""]],
    ["_params", [], [[]]]
];

if (_mode == "DEPLOY") then {
    _params params [
        ["_totalMoney", 0, [0]],
        ["_totalHR", 0, [0]],
        ["_clientOwnerID", 0, [0]],
        ["_addHC", true, [true]],
        ["_queue", [], [[]]],
        ["_autoCapture", true, [true]],
        ["_entryPositions", [], [[]]],
        ["_objective", "", [""]]
    ];
    
    private _hqPos = getMarkerPos "respawn_west";
    if (_hqPos isEqualTo [0,0,0]) then { _hqPos = getMarkerPos "respawn_civilian"; };
    if (_hqPos isEqualTo [0,0,0]) then { _hqPos = getPos petros; };

    A3A_planning_objective = _objective;
    publicVariable "A3A_planning_objective";

    A3A_planning_autoCapture = _autoCapture;
    publicVariable "A3A_planning_autoCapture";
    
    // Reset active siege groups
    A3A_planning_activeGroups = [];
    publicVariable "A3A_planning_activeGroups";
    A3A_planning_captureTriggered = false;
    publicVariable "A3A_planning_captureTriggered";
    A3A_planning_secureTimerStart = -1;
    publicVariable "A3A_planning_secureTimerStart";
    A3A_planning_instantGarrisonDone = false;
    publicVariable "A3A_planning_instantGarrisonDone";
    diag_log "[A3A DEBUG] Stage 0: init vars OK";

    // --- DEFENSIVE VALIDATION & FALLBACK SYSTEM ---
    private _fallbackQueue = [];
    private _failedSquads = [];

    {
        _x params ["_unitTypes", "_idFormat", "_special", "_costMoney", "_costHR", "_vehType", "_displayName", "_entryName"];
        
        private _squadFailed = false;
        // Faction-agnostic: don't pre-validate unit identifiers against CfgVehicles here.
        // Entries may be plain classnames OR faction-specific loadout identifiers (e.g. custom
        // loadout systems used by non-vanilla factions like Syndikat) - A3A_fnc_spawnGroup
        // already knows how to resolve whatever format the active faction uses, so we trust it
        // as the primary spawn path. Raw classnames are only strictly required by the manual
        // createUnit fallback further down, and THAT is where we validate/substitute if needed.
        private _validatedUnits = +_unitTypes;

        // 2. Validate and replace vehicle type (if specified)
        private _validatedVeh = _vehType;
        if (_vehType != "") then {
            if (!isClass (configFile >> "CfgVehicles" >> _vehType)) then {
                diag_log format ["[A3A Ultimate Tweaks Extender] Spawning vehicle class '%1' is invalid.", _vehType];
                _squadFailed = true;
                
                if (_special == "VehicleSquad") then {
                    _validatedVeh = "I_G_Offroad_01_AT_F"; // Vanilla light AT vehicle
                    diag_log "[A3A Ultimate Tweaks Extender] Falling back AT Car vehicle to 'I_G_Offroad_01_AT_F'.";
                } else {
                    if (_special == "BuildAA") then {
                        _validatedVeh = "I_G_Van_01_transport_F"; // Vanilla Truck
                        diag_log "[A3A Ultimate Tweaks Extender] Falling back AA Truck vehicle to 'I_G_Van_01_transport_F'.";
                    } else {
                        _validatedVeh = "I_G_Offroad_01_armed_F"; // Default armed MRAP/car
                        diag_log "[A3A Ultimate Tweaks Extender] Falling back custom vehicle to 'I_G_Offroad_01_armed_F'.";
                    };
                };
            };
        };

        // 3. Log HMG/Mortar static configuration issues (actual assembly fallbacks are resolved dynamically in supportAI)
        if (_special in ["MG", "MG_FALLBACK"]) then {
            private _staticMG = (A3A_faction_reb getOrDefault ["staticMGs", [""]]) # 0;
            if (isNil "_staticMG" || {_staticMG == "" || {!isClass (configFile >> "CfgVehicles" >> _staticMG)}}) then {
                diag_log "[A3A Ultimate Tweaks Extender] Faction staticMGs config is invalid; fallback HMG will be assembled.";
                _squadFailed = true;
            };
        };
        if (_special in ["Mortar", "Mortar_FALLBACK"]) then {
            private _staticMortar = (A3A_faction_reb getOrDefault ["staticMortars", [""]]) # 0;
            if (isNil "_staticMortar" || {_staticMortar == "" || {!isClass (configFile >> "CfgVehicles" >> _staticMortar)}}) then {
                diag_log "[A3A Ultimate Tweaks Extender] Faction staticMortars config is invalid; fallback Mortar will be assembled.";
                _squadFailed = true;
            };
        };

        if (_squadFailed) then {
            _failedSquads pushBack _displayName;
        };

        _fallbackQueue pushBack [_validatedUnits, _idFormat, _special, _costMoney, _costHR, _validatedVeh, _displayName, _entryName];
    } forEach _queue;
    diag_log format ["[A3A DEBUG] Stage 1: fallback validation OK, fallbackQueue count=%1", count _fallbackQueue];

    // Log fallback conversions to RPT only (no UI warning)
    if (count _failedSquads > 0) then {
        private _failedNames = "";
        {
            if (_forEachIndex > 0) then { _failedNames = _failedNames + ", "; };
            _failedNames = _failedNames + _x;
        } forEach _failedSquads;
        diag_log format ["[A3A Planning Warning] Custom assets missing/invalid for squads: %1. Spawning vanilla fallbacks.", _failedNames];
    };

    private _allocatedPositions = createHashMap;
    private _idCounters = createHashMap;
    private _validatedQueue = [];

    {
        _x params ["_unitTypes", "_idFormat", "_special", "_costMoney", "_costHR", "_vehType", "_displayName", "_entryName"];

        private _entryPos = [0,0,0];
        {
            _x params ["_name", "_pos"];
            if (_name == _entryName) exitWith { _entryPos = _pos; };
        } forEach _entryPositions;

        if (_entryPos isEqualTo [0,0,0]) then {
            private _markerName = "A3A_planning_entry_" + _entryName;
            _entryPos = getMarkerPos _markerName;
        };
        if (_entryPos isEqualTo [0,0,0]) then { _entryPos = _hqPos; };

        // Retrieve already allocated positions for this entry point
        private _alreadyAllocated = _allocatedPositions getOrDefault [_entryName, []];

        private _spawnPos = [];
        private _minDist = if (_vehType != "") then { 30 } else { 20 };
        private _searchRadius = 15;
        private _found = false;

        // Attempt to find a safe position that doesn't overlap
        for "_attempts" from 1 to 10 do {
            private _cand = [_entryPos, 0, _searchRadius, 4, 0, 0.7, 0] call BIS_fnc_findSafePos;
            if (count _cand == 2) then { _cand pushBack 0; };
            
            if (count _cand == 3) then {
                // Check distance against all already allocated positions
                private _tooClose = false;
                {
                    if (_cand distance2D _x < _minDist) exitWith { _tooClose = true; };
                } forEach _alreadyAllocated;

                if (!_tooClose) exitWith {
                    _spawnPos = _cand;
                    _found = true;
                };
            };
            _searchRadius = _searchRadius + 15; // Expand search area
        };

        // Fallback if no safe position found
        if (!_found) then {
            _spawnPos = [_entryPos, 5, 60, 2, 0, 0.7, 0] call BIS_fnc_findSafePos;
            if (count _spawnPos == 2) then { _spawnPos pushBack 0; };
            if (count _spawnPos < 3) then { _spawnPos = _entryPos; };
        };

        // Record the allocated position
        _alreadyAllocated pushBack _spawnPos;
        _allocatedPositions set [_entryName, _alreadyAllocated];

        // Build a unique, complete group name (e.g. "Squd-1", "Mortar-2")
        private _counter = (_idCounters getOrDefault [_idFormat, 0]) + 1;
        _idCounters set [_idFormat, _counter];
        private _groupName = _idFormat + str _counter;

        // Push squad with its pre-allocated spawn position to the deployment queue
        _validatedQueue pushBack [_unitTypes, _groupName, _special, _costMoney, _costHR, _vehType, _displayName, _entryName, _spawnPos];
    } forEach _fallbackQueue;
    diag_log format ["[A3A DEBUG] Stage 2: position allocation OK, validatedQueue count=%1", count _validatedQueue];

    // Calculate total cost (using the validated queue)
    private _deductMoney = 0;
    private _deductHR = 0;
    {
        _deductMoney = _deductMoney + (_x select 3);
        _deductHR = _deductHR + (_x select 4);
    } forEach _validatedQueue;

    // Deduct resources
    [-_deductHR, -_deductMoney] call A3A_fnc_resourcesFIA;
    diag_log "[A3A DEBUG] Stage 3: resource deduction OK";

    // Deduct selected garage vehicles from the HQ garage
    private _garageVehiclesToDeduct = [];
    {
        _x params ["_type", "_id", "_special", "_costMoney", "_costHR", "_veh", "_name", "_entry"];
        if (_special == "GarageCrew" && {_veh != ""}) then {
            _garageVehiclesToDeduct pushBack _veh;
        };
    } forEach _validatedQueue;

    if (count _garageVehiclesToDeduct > 0) then {
        [_garageVehiclesToDeduct] call A3A_fnc_planning_serverDeductGarage;
    };
    diag_log "[A3A DEBUG] Stage 4: garage deduction OK";

    private _spawnSquadDirect = {
        params ["_unitTypes", "_idFormat", "_special", "_vehType", "_spawnPos", "_targetPos", "_addHC", "_clientOwnerID"];
        diag_log format ["[A3A DEBUG] spawnSquadDirect invoked for %1", _idFormat];

        // Declared locally so it's always in scope no matter which call stack
        // _spawnSquadDirect ends up executing on (spawn does NOT inherit private
        // variables from the scope it was written in, only from explicit params).
        private _fnc_ensureThreadStarted = {
            params ["_startCode", "_label"];
            private _attempt = 0;
            private _maxAttempts = 3;
            private _started = false;
            while {!_started && {_attempt < _maxAttempts}} do {
                _attempt = _attempt + 1;
                private _handle = call _startCode;
                sleep 0.3;
                if (!isNull _handle && {!scriptDone _handle}) then {
                    _started = true;
                } else {
                    diag_log format ["[A3A Planning Warning] Support AI thread '%1' failed to start (attempt %2/%3). Retrying...", _label, _attempt, _maxAttempts];
                };
            };
            if (!_started) then {
                diag_log format ["[A3A Planning Error] Support AI thread '%1' failed to start after %2 attempts. Group left on its HOLD waypoint (will not assault).", _label, _maxAttempts];
            };
            _started
        };

        private _group = groupNull;
        private _vehicle = objNull;

        // --- STAGE 1: Creation only. Nothing here decides waypoints/behavior. ---
        try {
            if (_vehType != "" && {isClass (configFile >> "CfgVehicles" >> _vehType)}) then {
                diag_log format ["[A3A Planning] Spawning vehicle %1 at %2...", _vehType, _spawnPos];
                _vehicle = createVehicle [_vehType, _spawnPos, [], 10, "NONE"];
                if (!isNull _vehicle) then {
                    [_vehicle, teamPlayer] call A3A_fnc_AIVEHinit;
                } else {
                    diag_log format ["[A3A Planning Error] Failed to create vehicle %1 at %2.", _vehType, _spawnPos];
                };
            };

            diag_log format ["[A3A Planning] Spawning squad group %1 units: %2...", _idFormat, _unitTypes];
            _group = [_spawnPos, teamPlayer, _unitTypes, true] call A3A_fnc_spawnGroup;
            if (isNull _group) then {
                diag_log "[A3A Planning Warning] A3A_fnc_spawnGroup returned groupNull. Attempting manual group creation...";
                _group = createGroup teamPlayer;
                if (!isNull _group) then {
                    {
                        private _spawnUnitType = _x;
                        if (isNil "_spawnUnitType" || {_spawnUnitType == "" || {!isClass (configFile >> "CfgVehicles" >> _spawnUnitType)}}) then {
                            diag_log format ["[A3A Planning Warning] Manual fallback: unit identifier '%1' isn't a raw createUnit-compatible classname. Falling back to 'I_G_Soldier_F'.", _spawnUnitType];
                            _spawnUnitType = "I_G_Soldier_F";
                        };
                        private _unit = _group createUnit [_spawnUnitType, _spawnPos, [], 10, "NONE"];
                        if (!isNull _unit) then {
                            [_unit] call A3A_fnc_FIAinit;
                        } else {
                            diag_log format ["[A3A Planning Error] Manual createUnit failed for unit class %1.", _spawnUnitType];
                        };
                    } forEach _unitTypes;
                };
            };

            if (!isNull _group) then {
                private _timeout = time + 10;
                waitUntil {sleep 0.1; ({alive _x} count (units _group) == count _unitTypes) || {time > _timeout}};
                _group setGroupIdGlobal [_idFormat];
                { [_x] call A3A_fnc_FIAinit } forEach (units _group);
            };
        } catch {
            diag_log format ["[A3A Planning Exception] Group/vehicle creation failed for squad: %1. Error: %2", _idFormat, _exception];
        };

        if (isNull _group || {count (units _group) == 0}) exitWith {
            diag_log "[A3A Planning Error] Both spawnGroup and manual fallback failed to produce any active group.";
            groupNull
        };

        // --- STAGE 2: Classify and lock in waypoint/behavior FIRST, before any risky
        // crew-assignment code runs. This is the only place a support role is decided,
        // and it happens unconditionally as soon as the group exists - a later failure
        // in crew assignment (Stage 3) can no longer suppress it or leave the group
        // defaulting to assault behavior. ---
        private _roleTag = switch (_special) do {
            case "MG";
            case "MG_FALLBACK": { "MG" };
            case "Mortar";
            case "Mortar_FALLBACK": { "MORTAR" };
            case "VehicleSquad";
            case "BuildAA": { "VEHICLE" };
            case "GarageCrew": { "CREW" };
            default { "ASSAULT" };
        };
        _group setVariable ["siege_role", _roleTag, true];
        _group setVariable ["siege_spawnPos", _spawnPos, true];

        private _isSupportElement = _special in ["MG", "Mortar", "MG_FALLBACK", "Mortar_FALLBACK", "VehicleSquad"];

        if (_isSupportElement) then {
            private _wp = _group addWaypoint [_spawnPos, 0];
            _wp setWaypointType "HOLD";
            _group setBehaviour "AWARE";
            _group setCombatMode "YELLOW";
            _group setSpeedMode "NORMAL";
        } else {
            private _wp = _group addWaypoint [_targetPos, 0];
            _wp setWaypointType "SAD";
            _group setBehaviour "AWARE";
            _group setCombatMode "RED";
            _group setSpeedMode "NORMAL";
        };

        // --- STAGE 3: Crew assignment / vehicle mounting. Isolated in its own
        // try/catch so a failure here (moveInDriver/moveInGunner/fullCrew races,
        // bad indexing, etc.) can NEVER roll back or skip the waypoint/behavior
        // already committed in Stage 2 above. ---
        try {
            // MG and Mortar weapon bag override system (only for fallback squads)
            if (_special in ["MG_FALLBACK", "Mortar_FALLBACK"]) then {
                [_group, _special] spawn {
                    params ["_group", "_special"];
                    private _units = [];
                    private _tries = 0;
                    while {_tries < 10} do {
                        if (isNull _group) exitWith {};
                        _units = (units _group) select { alive _x };
                        if (count _units >= 2) exitWith {};
                        sleep 0.5;
                        _tries = _tries + 1;
                    };
                    if (isNull _group) exitWith {};
                    if (count _units < 2) exitWith {
                        diag_log format ["[A3A Planning Error] %1 squad %2 never reached 2 alive units for weapon-bag assignment (found %3 after retries). Squad failed to spawn correctly.", _special, groupID _group, count _units];
                    };

                    private _sidePrefix = if (teamPlayer == west) then { "B" } else { if (teamPlayer == east) then { "O" } else { "I" } };
                    
                    private _mgWeaponBag = _sidePrefix + "_HMG_01_weapon_F";
                    private _mgSupportBag = _sidePrefix + "_HMG_01_support_F";
                    if (!isClass (configFile >> "CfgVehicles" >> _mgWeaponBag)) then {
                        _mgWeaponBag = "I_HMG_01_weapon_F";
                        _mgSupportBag = "I_HMG_01_support_F";
                    };

                    private _mortarWeaponBag = _sidePrefix + "_Mortar_01_weapon_F";
                    private _mortarSupportBag = _sidePrefix + "_Mortar_01_support_F";
                    if (!isClass (configFile >> "CfgVehicles" >> _mortarWeaponBag)) then {
                        _mortarWeaponBag = "I_Mortar_01_weapon_F";
                        _mortarSupportBag = "I_Mortar_01_support_F";
                    };

                    private _unit1 = _units # 0;
                    private _unit2 = _units # 1;

                    removeBackpackGlobal _unit1;
                    removeBackpackGlobal _unit2;

                    if (_special == "MG_FALLBACK") then {
                        _unit1 addBackpackGlobal _mgWeaponBag;
                        _unit2 addBackpackGlobal _mgSupportBag;
                    };
                    if (_special == "Mortar_FALLBACK") then {
                        _unit1 addBackpackGlobal _mortarWeaponBag;
                        _unit2 addBackpackGlobal _mortarSupportBag;
                    };
                    diag_log format ["[A3A Ultimate Tweaks Extender] Equipped group %1 with %2 deployment bags.", groupID _group, _special];
                };
            };

            // Spread out the units immediately if they are on foot to prevent drone wipes
            if (isNull _vehicle) then {
                {
                    if (_forEachIndex > 0) then {
                        private _offsetPos = [_spawnPos, 4, 25, 2, 0, 0.7, 0] call BIS_fnc_findSafePos;
                        if (count _offsetPos == 2) then {
                            _x setPos _offsetPos;
                        };
                    };
                } forEach (units _group);
                _group setFormation "LINE";
            };

            // Assign group to player's High Command if requested
            if (_addHC && {_clientOwnerID > 0} && {_roleTag in ["ASSAULT", "CREW"]}) then {
                [_group] remoteExec ["A3A_fnc_planning_localAddHC", _clientOwnerID];
            };

            private _countUnits = count (units _group) - 1;

            private _initVeh = {
                if (isNull _vehicle) exitWith {};
                _group addVehicle _vehicle;
                _vehicle setVariable ["owner", _group, true];
                driver _vehicle action ["engineOn", _vehicle];
                { if (vehicle _x == _x) then { _x moveInAny _vehicle } } forEach units _group;
            };

            private _initInfVeh = {
                if (isNull _vehicle) exitWith {};
                leader _group moveInDriver _vehicle;
                if (count (units _group) > 1 && {fullCrew [_vehicle, "gunner", true] isNotEqualTo []}) then {
                    (units _group # 1) moveInGunner _vehicle;
                };
                call _initVeh;
            };

            switch _special do {
                case "GarageCrew": {
                    call _initVeh;
                    _vehicle allowCrewInImmobile true;
                };

                case "BuildAA": {
                    private _staticList = (attachedObjects _vehicle) select {typeOf _x in (A3A_faction_reb get "staticAA")};
                    if (count _staticList > 0) then {
                        private _static = _staticList # 0;
                        if (_countUnits >= 1) then {
                            (units _group # (_countUnits - 1)) moveInDriver _vehicle;
                            (units _group # _countUnits) moveInGunner _static;
                        };
                    };
                    call _initVeh;
                    _vehicle allowCrewInImmobile true;
                };
                case "VehicleSquad": {
                    if (_countUnits >= 1) then {
                        (units _group # (_countUnits - 1)) moveInDriver _vehicle;
                        (units _group # _countUnits) moveInGunner _vehicle;
                    };
                    call _initVeh;
                    _vehicle allowCrewInImmobile true;
                };
                default {
                    call _initInfVeh;
                };
            };
        } catch {
            diag_log format ["[A3A Planning Exception] Crew assignment failed for squad: %1 (role: %2). Error: %3. Waypoint/behavior already committed in Stage 2, so this squad will still hold/support correctly - it may just be missing its vehicle seat.", _idFormat, _roleTag, _exception];
        };

        // --- STAGE 4: Dispatch the support-AI thread, with verified retry. ---
        if (_special in ["MG", "Mortar", "MG_FALLBACK", "Mortar_FALLBACK"]) then {
            [
                { [_group, _special, A3A_planning_objective, _targetPos] spawn A3A_fnc_planning_supportAI },
                _idFormat
            ] call _fnc_ensureThreadStarted;
        } else {
            if (_special == "VehicleSquad") then {
                if (!isNull _vehicle) then {
                    [
                        { [_group, _vehicle, A3A_planning_objective, _targetPos] spawn A3A_fnc_planning_vehicleOverwatch },
                        _idFormat
                    ] call _fnc_ensureThreadStarted;
                } else {
                    diag_log format ["[A3A Planning Error] VehicleSquad %1 has no valid vehicle - holding crew defensively on its HOLD waypoint instead of assaulting.", _idFormat];
                };
            };
        };

        _group
    };
    diag_log "[A3A DEBUG] Stage 5: spawnSquadDirect compiled OK";

    private _targetPos = getMarkerPos A3A_planning_objective;
    diag_log format ["[A3A DEBUG] Stage 6: entering dispatch loop, targetPos=%1", _targetPos];

    // Hardcoded (no longer lobby-tweakable): 8s delay before dispatching the assault.
    private _initDelay = 8;

    [_validatedQueue, _entryPositions, _hqPos, _targetPos, _spawnSquadDirect, _addHC, _clientOwnerID, _initDelay] spawn {
        params ["_validatedQueue", "_entryPositions", "_hqPos", "_targetPos", "_spawnSquadDirect", "_addHC", "_clientOwnerID", "_initDelay"];

        if (_initDelay > 0) then {
            diag_log format ["[A3A Planning] Waiting %1s for the objective's defenses to finish initializing before dispatching the assault...", _initDelay];
            sleep _initDelay;
        };

        // 2. Spawn travel watches for each queued squad (valid squads only)
        {
            _x params ["_unitTypes", "_idFormat", "_special", "_costMoney", "_costHR", "_vehType", "_displayName", "_entryName", "_spawnPos"];
            
            private _entryPos = [0,0,0];
            {
                _x params ["_name", "_pos"];
                if (_name == _entryName) exitWith { _entryPos = _pos; };
            } forEach _entryPositions;

            if (_entryPos isEqualTo [0,0,0]) then {
                private _markerName = "A3A_planning_entry_" + _entryName;
                _entryPos = getMarkerPos _markerName;
            };
            if (_entryPos isEqualTo [0,0,0]) then { _entryPos = _hqPos; };

            // Calculate travel delay based on road speed ~14 m/s (50 km/h)
            private _distance = round (_hqPos distance2D _entryPos);
            private _travelTime = round (_distance / 14);
            
            // Apply configurable travel time multiplier
            private _travelMult = missionNamespace getVariable ["A3A_tweak_siegeTravelTimeMultiplier", 1.0];
            _travelTime = round (_travelTime * _travelMult);
            
            if (_travelMult == 0) then {
                _travelTime = 0; // Instant
            } else {
                _travelTime = (_travelTime max 5) min 300; // Bound between 5s and 5 minutes
            };

            // Spawn a thread to track travel simulation
            [_unitTypes, _idFormat, _special, _vehType, _entryPos, _targetPos, _travelTime, _displayName, _entryName, _spawnSquadDirect, _distance, _costMoney, _costHR, _spawnPos, _addHC, _clientOwnerID] spawn {
                params ["_unitTypes", "_idFormat", "_special", "_vehType", "_entryPos", "_targetPos", "_travelTime", "_displayName", "_entryName", "_spawnSquadDirect", "_distance", "_costMoney", "_costHR", "_spawnPos", "_addHC", "_clientOwnerID"];

                if (_travelTime > 0) then {
                    // Radio departure report
                    [format ["%1 attack group departing HQ for Staging Area %2. Distance: %3m | ETA: %4 seconds.", _displayName, _entryName, _distance, _travelTime]] remoteExec ["A3A_fnc_planning_localSideChat", 0];
                    
                    // Wait for half the travel duration
                    private _halfTime = round (_travelTime / 2);
                    sleep _halfTime;

                    // Radio progress report halfway
                    [format ["%1 attack group is halfway to Staging Area %2.", _displayName, _entryName]] remoteExec ["A3A_fnc_planning_localSideChat", 0];
                    sleep (_travelTime - _halfTime);
                };

                // Spawn the group safely at pre-allocated position
                private _group = [_unitTypes, _idFormat, _special, _vehType, _spawnPos, _targetPos, _addHC, _clientOwnerID] call _spawnSquadDirect;
                
                if (!isNull _group) then {
                    // Set tracking variables on group
                    _group setVariable ["siege_costMoney", _costMoney, true];
                    _group setVariable ["siege_costHR", _costHR, true];
                    _group setVariable ["siege_originalCount", count (units _group), true];

                    // Track active group for garrison/refund
                    A3A_planning_activeGroups pushBack _group;
                    publicVariable "A3A_planning_activeGroups";

                    // Radio arrival report
                    [format ["%1 reports arrival at Staging Area %2! Dismounting and commencing assault.", groupID _group, _entryName]] remoteExec ["A3A_fnc_planning_localSideChat", 0];
                };
            };
        } forEach _validatedQueue;
        diag_log "[A3A DEBUG] Stage 7: dispatch loop completed";
    };

    A3A_planning_assaultStarted = true;
    publicVariable "A3A_planning_objective";
    publicVariable "A3A_planning_assaultStarted";
};
