/*
    fn_planning_init.sqf
    Initializes global variables, states, and background execution loops for the Siege & Attack Planning system.
    Supports target selection, multiple deployment entry points, and recruitment queues.
*/

if (isNil "A3A_planning_initDone") then {
    A3A_planning_initDone = true;

    // Reworked State Variables
    A3A_planning_objective = "";                 // Selected target zone marker
    A3A_planning_entryPoints = [];               // List of active entry point names (e.g. ["Alpha", "Beta"])
    A3A_planning_sharedEntry = true;             // Whether all squads share a single entry point
    A3A_planning_selectedSharedEntry = "Alpha";  // Selected shared entry point name
    A3A_planning_queue = [];                     // Recruitment queue of squads: [_squadType, _idFormat, _special, _money, _hr, _vehType, _displayName, _assignedEntryName]
    A3A_planning_assaultStarted = false;         // Assault state for progressive capture loop compatibility
    A3A_planning_activeGroups = [];              // Track deployed groups for refund/garrison
    A3A_planning_captureTriggered = false;       // Sector capture trigger state
    A3A_planning_secureTimerStart = -1;          // Time.time the AO was first found clear post-capture; -1 = not counting
    A3A_planning_instantGarrisonDone = false;    // Whether the instant garrison registration has run for the current capture
    
    // UI Helpers
    A3A_planning_includeVehicle = true;          // Checkbox state for including vehicles
    A3A_planning_selectedSquadIndex = 0;         // Selected squad type index (0-10)
    A3A_planning_selectedSquadEntry = "Alpha";   // Target entry point for the currently selected squad when not shared
    A3A_planning_selectedStagingToMove = "";     // Currently selected staging point name for movement

    diag_log "[A3A Ultimate Tweaks Extender] Siege Planning system initialized.";

    // Run progressive sector control loop and helper tasks on server
    if (isServer) then {
        [] spawn A3A_fnc_planning_sectorControl;
        
        A3A_fnc_planning_getAssaultAnchor = {
            // Finds the nearest currently-active ASSAULT (plain infantry) group to a target position,
            // and whether it has moved meaningfully from its spawn point yet.
            // Returns [_hasAdvanced, _anchorPos, _anchorDist]. _anchorDist is -1 if there is no
            // infantry group in this siege (e.g. a vehicle/support-only deployment).
            params ["_targetPos"];
            private _anchorPos = [];
            private _anchorDist = -1;
            private _hasAdvanced = false;
            private _bestDist = 1e9;
            if (!isNil "A3A_planning_activeGroups") then {
                {
                    if (!isNull _x && {(_x getVariable ["siege_role", "ASSAULT"]) == "ASSAULT"} && {count (units _x) > 0}) then {
                        private _ldr = leader _x;
                        if (alive _ldr) then {
                            private _curPos = getPosATL _ldr;
                            private _d = _curPos distance2D _targetPos;
                            if (_d < _bestDist) then {
                                _bestDist = _d;
                                _anchorPos = _curPos;
                                _anchorDist = _d;
                                private _spawnPos = _x getVariable ["siege_spawnPos", []];
                                _hasAdvanced = if (count _spawnPos == 3) then {
                                    (_curPos distance2D _spawnPos) > 20
                                } else { true };
                            };
                        };
                    };
                } forEach A3A_planning_activeGroups;
            };
            [_hasAdvanced, _anchorPos, _anchorDist]
        };

        A3A_fnc_planning_serverDeductGarage = {
            params ["_vehicles"];
            {
                private _idx = vehInGarage find _x;
                if (_idx != -1) then {
                    vehInGarage deleteAt _idx;
                };
            } forEach _vehicles;
            publicVariable "vehInGarage";
        };

        A3A_fnc_planning_serverAddGarage = {
            params ["_vehicles"];

            private _vehicleClasses = [];
            {
                private _class = "";
                if (_x isEqualType objNull) then {
                    if (!isNull _x) then {
                        _class = typeOf _x;
                    };
                } else {
                    if (_x isEqualType "") then {
                        _class = _x;
                    };
                };

                if (_class != "") then {
                    _vehicleClasses pushBack _class;
                    vehInGarage pushBack _class;
                } else {
                    diag_log format ["[A3A Planning Warning] Could not recover invalid siege vehicle entry: %1", _x];
                };
            } forEach _vehicles;

            publicVariable "vehInGarage";

            if (_vehicleClasses isEqualTo []) exitWith {
                diag_log "[A3A Planning Warning] No valid siege vehicle classes were available to recover to the garage.";
            };

            if (isNil "HR_GRG_fnc_addVehiclesByClass") exitWith {
                diag_log format ["[A3A Planning Warning] HR Garage function unavailable. Updated vehInGarage only for recovered vehicles: %1", _vehicleClasses];
            };

            private _garageClasses = [];
            private _cfgVehicles = configFile >> "CfgVehicles";
            {
                if (!isClass (_cfgVehicles >> _x)) then {
                    diag_log format ["[A3A Planning Warning] Cannot add recovered vehicle to HR Garage. Invalid class: %1", _x];
                    continue;
                };

                if (!isNil "HR_GRG_fnc_getCatIndex" && {([_x] call HR_GRG_fnc_getCatIndex) < 0}) then {
                    diag_log format ["[A3A Planning Warning] Cannot add recovered vehicle to HR Garage. Unsupported category: %1", _x];
                    continue;
                };

                _garageClasses pushBack _x;
            } forEach _vehicleClasses;

            if (_garageClasses isEqualTo []) exitWith {
                diag_log format ["[A3A Planning Warning] No recovered siege vehicles were accepted by HR Garage validation. Candidates: %1", _vehicleClasses];
            };

            private _added = [_garageClasses, ""] call HR_GRG_fnc_addVehiclesByClass;
            if (_added) then {
                diag_log format ["[A3A Planning] Recovered %1 siege vehicles to HR Garage: %2", count _garageClasses, _garageClasses];
            } else {
                diag_log format ["[A3A Planning Warning] HR Garage rejected recovered siege vehicles: %1", _garageClasses];
            };
        };
    };

};

// Client-side native stacked event handler for map clicks
A3A_fnc_planning_onMapClick = {
    params ["_pos"];
    
    private _display = findDisplay 60000;
    if (isNull _display) exitWith {};

    diag_log format ["[A3A Planning MapClick] Clicked at pos: %1, MapMode: %2", _pos, A3A_planning_mapMode];


    if (!isNil "A3A_planning_mapMode" && {A3A_planning_mapMode != ""}) then {
        if (A3A_planning_mapMode == "TARGET") then {
            private _validTargets = outposts + airportsX + resourcesX + factories + seaports + milbases;
            private _marker = [_validTargets, _pos] call BIS_fnc_nearestPosition;
            if (getMarkerPos _marker distance2D _pos < 800) then {
                private _side = sidesX getVariable [_marker, sideUnknown];
                if (_side == Occupants || _side == Invaders) then {
                    A3A_planning_objective = _marker;
                    private _name = markerText ("Dum" + _marker);
                    if (_name == "") then { _name = _marker; };
                    ["Target Selected", format ["Objective set to %1.", _name], false] call A3A_fnc_planning_showNotification;
                    A3A_planning_mapMode = ""; // Clear mode
                    
                    // Remove stacked handler
                    ["A3A_planning_mapClick", "onMapSingleClick"] call BIS_fnc_removeStackedEventHandler;
                    
                    [_display] call A3A_fnc_planning_ui;
                } else {
                    ["Target Selection Failed", "You must select an enemy-controlled outpost, roadblock, or base.", true] call A3A_fnc_planning_showNotification;
                };
            } else {
                ["Target Selection Failed", "No enemy objective close to click location.", true] call A3A_fnc_planning_showNotification;
            };
        };
        
        if (A3A_planning_mapMode in ["STAGING", "STAGING_ADD", "STAGING_MOVE", "STAGING_DELETE"]) then {
            // Deselect High Command groups to prevent issuing accidental orders or selection conflicts
            player hcSelectGroup [];

            if (A3A_planning_mapMode == "STAGING_DELETE") exitWith {
                private _nearestMarker = "";
                private _nearestDist = 250;
                {
                    private _mName = "A3A_planning_entry_" + _x;
                    if (_mName in allMapMarkers) then {
                        private _dist = getMarkerPos _mName distance2D _pos;
                        if (_dist < _nearestDist) then {
                            _nearestDist = _dist;
                            _nearestMarker = _x;
                        };
                    };
                } forEach A3A_planning_entryPoints;

                if (_nearestMarker != "") then {
                    private _mName = "A3A_planning_entry_" + _nearestMarker;
                    deleteMarkerLocal _mName;

                    A3A_planning_entryPoints = A3A_planning_entryPoints - [_nearestMarker];

                    private _cleanedQueue = [];
                    {
                        if ((_x select 7) != _nearestMarker) then {
                            _cleanedQueue pushBack _x;
                        };
                    } forEach A3A_planning_queue;
                    A3A_planning_queue = _cleanedQueue;

                    ["Staging Removed", format ["Removed staging point %1 and cleared any queued squads assigned to it.", _nearestMarker], false] call A3A_fnc_planning_showNotification;
                    A3A_planning_mapMode = "";

                    ["A3A_planning_mapClick", "onMapSingleClick"] call BIS_fnc_removeStackedEventHandler;
                    onMapSingleClick "";

                    [_display] call A3A_fnc_planning_ui;
                } else {
                    ["Selection Failed", "No staging point found within 250m of click.", true] call A3A_fnc_planning_showNotification;
                };
            };

            private _nearEnemy = false;
            private _nearMarkerName = "";
            {
                private _side = sidesX getVariable [_x, sideUnknown];
                if (_side == Occupants || _side == Invaders) then {
                    if (getMarkerPos _x distance2D _pos < 500) exitWith {
                        _nearEnemy = true;
                        _nearMarkerName = markerText ("Dum" + _x);
                        if (_nearMarkerName == "") then { _nearMarkerName = _x; };
                    };
                };
            } forEach (outposts + airportsX + resourcesX + factories + seaports + milbases);

            if (_nearEnemy) exitWith {
                ["Placement Blocked", format ["You cannot set a staging area within 500m of enemy territory (%1).", _nearMarkerName], true] call A3A_fnc_planning_showNotification;
            };

            if (A3A_planning_mapMode == "STAGING_ADD") then {
                private _allNames = ["Alpha", "Beta", "Gamma", "Delta"];
                private _nextName = "";
                {
                    if !(_x in A3A_planning_entryPoints) exitWith { _nextName = _x; };
                } forEach _allNames;

                if (_nextName != "") then {
                    A3A_planning_entryPoints pushBack _nextName;
                    private _mName = "A3A_planning_entry_" + _nextName;
                    private _m = createMarkerLocal [_mName, _pos];
                    _m setMarkerTypeLocal "mil_start";
                    _m setMarkerColorLocal "ColorGreen";
                    _m setMarkerTextLocal ("Staging: " + _nextName);
                    ["Staging Area Added", format ["Staging point %1 registered.", _nextName], false] call A3A_fnc_planning_showNotification;
                } else {
                    ["Limit Reached", "You can have a maximum of 4 staging markers. Use Move Staging mode to relocate one.", true] call A3A_fnc_planning_showNotification;
                };
            };

            if (A3A_planning_mapMode == "STAGING_MOVE") then {
                if (isNil "A3A_planning_selectedStagingToMove") then { A3A_planning_selectedStagingToMove = ""; };

                if (A3A_planning_selectedStagingToMove == "") then {
                    // Step 1: Select marker to move. Check within 250m radius.
                    private _nearestMarker = "";
                    private _nearestDist = 250;
                    {
                        private _mName = "A3A_planning_entry_" + _x;
                        if (_mName in allMapMarkers) then {
                            private _dist = getMarkerPos _mName distance2D _pos;
                            if (_dist < _nearestDist) then {
                                _nearestDist = _dist;
                                _nearestMarker = _x;
                            };
                        };
                    } forEach A3A_planning_entryPoints;

                    if (_nearestMarker != "") then {
                        A3A_planning_selectedStagingToMove = _nearestMarker;
                        ("A3A_planning_entry_" + _nearestMarker) setMarkerColorLocal "ColorYellow";
                        ["Staging Selected", format ["Selected staging point %1. Click anywhere on the map to move it.", _nearestMarker], false] call A3A_fnc_planning_showNotification;
                    } else {
                        ["Selection Failed", "No staging point found within 250m of click.", true] call A3A_fnc_planning_showNotification;
                    };
                } else {
                    // Step 2: Reposition the selected marker.
                    private _mName = "A3A_planning_entry_" + A3A_planning_selectedStagingToMove;
                    if (_mName in allMapMarkers) then {
                        _mName setMarkerPos _pos;
                        _mName setMarkerColorLocal "ColorGreen";
                        ["Staging Area Moved", format ["Moved %1 to new location.", A3A_planning_selectedStagingToMove], false] call A3A_fnc_planning_showNotification;
                    };
                    A3A_planning_selectedStagingToMove = "";
                };
            };

            // Legacy STAGING mode (for compatibility or fallback)
            if (A3A_planning_mapMode == "STAGING") then {
                private _moved = false;
                {
                    private _mName = "A3A_planning_entry_" + _x;
                    if (getMarkerPos _mName distance2D _pos < 250) exitWith {
                        _mName setMarkerPos _pos;
                        _moved = true;
                        ["Staging Area Moved", format ["Moved %1 to new location.", _x], false] call A3A_fnc_planning_showNotification;
                    };
                } forEach A3A_planning_entryPoints;

                if (!_moved) then {
                    private _allNames = ["Alpha", "Beta", "Gamma", "Delta"];
                    private _nextName = "";
                    {
                        if !(_x in A3A_planning_entryPoints) exitWith { _nextName = _x; };
                    } forEach _allNames;

                    if (_nextName != "") then {
                        A3A_planning_entryPoints pushBack _nextName;
                        private _mName = "A3A_planning_entry_" + _nextName;
                        private _m = createMarkerLocal [_mName, _pos];
                        _m setMarkerTypeLocal "mil_start";
                        _m setMarkerColorLocal "ColorGreen";
                        _m setMarkerTextLocal ("Staging: " + _nextName);
                        ["Staging Area Added", format ["Staging point %1 registered.", _nextName], false] call A3A_fnc_planning_showNotification;
                    } else {
                        ["Limit Reached", "You can have a maximum of 4 staging markers. Click near one to move it.", true] call A3A_fnc_planning_showNotification;
                    };
                };
            };
            [_display] call A3A_fnc_planning_ui;
        };
    };
};
