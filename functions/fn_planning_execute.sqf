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

    // --- DEFENSIVE VALIDATION & FALLBACK SYSTEM ---
    private _fallbackQueue = [];
    private _failedSquads = [];

    {
        _x params ["_unitTypes", "_idFormat", "_special", "_costMoney", "_costHR", "_vehType", "_displayName", "_entryName"];
        
        private _squadFailed = false;
        private _validatedUnits = [];

        // 1. Validate and replace unit classnames
        {
            if (isNil "_x" || {_x == "" || {!isClass (configFile >> "CfgVehicles" >> _x)}}) then {
                diag_log format ["[A3A Ultimate Tweaks Extender] Spawning unit class '%1' is invalid. Falling back to 'I_G_Soldier_F'.", _x];
                _validatedUnits pushBack "I_G_Soldier_F";
                _squadFailed = true;
            } else {
                _validatedUnits pushBack _x;
            };
        } forEach _unitTypes;

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

    // Log fallback conversions to RPT only (no UI warning)
    if (count _failedSquads > 0) then {
        private _failedNames = "";
        {
            if (_forEachIndex > 0) then { _failedNames = _failedNames + ", "; };
            _failedNames = _failedNames + _x;
        } forEach _failedSquads;
        diag_log format ["[A3A Planning Warning] Custom assets missing/invalid for squads: %1. Spawning vanilla fallbacks.", _failedNames];
    };

    // --- SQUAD DEPLOYMENT SPACING SYSTEM (PRE-CALCULATE UNIQUE POSITIONS) ---
    private _allocatedPositions = createHashMap;
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

        // Push squad with its pre-allocated spawn position to the deployment queue
        _validatedQueue pushBack [_unitTypes, _idFormat, _special, _costMoney, _costHR, _vehType, _displayName, _entryName, _spawnPos];
    } forEach _fallbackQueue;

    // Calculate total cost (using the validated queue)
    private _deductMoney = 0;
    private _deductHR = 0;
    {
        _deductMoney = _deductMoney + (_x select 3);
        _deductHR = _deductHR + (_x select 4);
    } forEach _validatedQueue;

    // Deduct resources
    [-_deductHR, -_deductMoney] call A3A_fnc_resourcesFIA;

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

    // Spawning logic function
    private _spawnSquadDirect = {
        params ["_unitTypes", "_idFormat", "_special", "_vehType", "_spawnPos", "_targetPos"];

        private _group = groupNull;
        private _vehicle = objNull;

        try {
            // Create vehicle if specified
            if (_vehType != "" && {isClass (configFile >> "CfgVehicles" >> _vehType)}) then {
                diag_log format ["[A3A Planning] Spawning vehicle %1 at %2...", _vehType, _spawnPos];
                _vehicle = createVehicle [_vehType, _spawnPos, [], 10, "NONE"];
                if (!isNull _vehicle) then {
                    [_vehicle, teamPlayer] call A3A_fnc_AIVEHinit;
                } else {
                    diag_log format ["[A3A Planning Error] Failed to create vehicle %1 at %2.", _vehType, _spawnPos];
                };
            };

            // Create the squad group
            diag_log format ["[A3A Planning] Spawning squad group %1 units: %2...", _idFormat, _unitTypes];
            _group = [_spawnPos, teamPlayer, _unitTypes, true] call A3A_fnc_spawnGroup;
            if (isNull _group) then {
                diag_log "[A3A Planning Warning] A3A_fnc_spawnGroup returned groupNull. Attempting manual group creation...";
                _group = createGroup teamPlayer;
                if (!isNull _group) then {
                    {
                        private _unit = _group createUnit [_x, _spawnPos, [], 10, "NONE"];
                        if (!isNull _unit) then {
                            [_unit] call A3A_fnc_FIAinit;
                        } else {
                            diag_log format ["[A3A Planning Error] Manual createUnit failed for unit class %1.", _x];
                        };
                    } forEach _unitTypes;
                };
            };

            if (isNull _group || {count (units _group) == 0}) exitWith {
                diag_log "[A3A Planning Error] Both spawnGroup and manual fallback failed to produce any active group.";
                groupNull
            };

            private _timeout = time + 10;
            waitUntil {sleep 0.1; ({alive _x} count (units _group) == count _unitTypes) || {time > _timeout}};

            private _grpIdName = _idFormat + str ({side (leader _x) == teamPlayer} count allGroups);
            _group setGroupIdGlobal [_grpIdName];

            // Initialize units
            { [_x] call A3A_fnc_FIAinit } forEach (units _group);

            // MG and Mortar weapon bag override system (only for fallback squads)
            if (_special in ["MG_FALLBACK", "Mortar_FALLBACK"]) then {
                [_group, _special] spawn {
                    params ["_group", "_special"];
                    sleep 2;
                    if (isNull _group) exitWith {};
                    private _units = (units _group) select { alive _x };
                    if (count _units >= 2) then {
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
            if (_addHC && {_clientOwnerID > 0}) then {
                [_group] remoteExec ["A3A_fnc_planning_localAddHC", _clientOwnerID];
            };

            // Specific vehicle and squad role configurations
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

            // Tactical Instruction: assign the appropriate post-arrival behavior for this squad type
            if (_special in ["MG", "Mortar", "MG_FALLBACK", "Mortar_FALLBACK"]) then {
                // Emplacement teams: move to a support position, assemble, and provide suppressive/indirect fire
                [_group, _special, A3A_planning_objective, _targetPos] spawn A3A_fnc_planning_supportAI;
            } else {
                if (_special == "VehicleSquad" && {!isNull _vehicle} && {count (weapons _vehicle) > 0}) then {
                    // Armed vehicles (Technicals, AA, APCs, Tanks): hold at a stand-off distance
                    // and engage from range instead of assaulting straight into the objective
                    [_group, _vehicle, A3A_planning_objective, _targetPos] spawn A3A_fnc_planning_vehicleOverwatch;
                } else {
                    private _wp = _group addWaypoint [_targetPos, 0];
                    _wp setWaypointType "SAD";
                    _group setBehaviour "AWARE";
                    _group setCombatMode "RED";
                    _group setSpeedMode "NORMAL";
                };
            };

        } catch {
            diag_log format ["[A3A Planning Exception] Spawning failed for squad: %1. Error: %2", _idFormat, _exception];
        };

        _group
    };

    private _targetPos = getMarkerPos A3A_planning_objective;
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
        [_unitTypes, _idFormat, _special, _vehType, _entryPos, _targetPos, _travelTime, _displayName, _entryName, _spawnSquadDirect, _distance, _costMoney, _costHR, _spawnPos] spawn {
            params ["_unitTypes", "_idFormat", "_special", "_vehType", "_entryPos", "_targetPos", "_travelTime", "_displayName", "_entryName", "_spawnSquadDirect", "_distance", "_costMoney", "_costHR", "_spawnPos"];

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
            private _group = [_unitTypes, _idFormat, _special, _vehType, _spawnPos, _targetPos] call _spawnSquadDirect;
            
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

    A3A_planning_assaultStarted = true;
    publicVariable "A3A_planning_objective";
    publicVariable "A3A_planning_assaultStarted";
};
