/*
	fn_planning_cacheVehicles.sqf
	Pre-builds and caches vehicle details and listbox entries based on War Level.
	Prioritizes active rebel template (A3A_faction_reb), then occupant/invader fallback templates, then vanilla fallbacks.
*/

if (isNil "A3A_faction_reb") exitWith {};
private _tier = missionNamespace getVariable ["tierWar", 1];

if (isNil "A3A_planning_cachedVehicles") then { A3A_planning_cachedVehicles = createHashMap; };
if (isNil "A3A_planning_cachedDisplayNames") then { A3A_planning_cachedDisplayNames = createHashMap; };

A3A_planning_cachedVehicles = createHashMap;

// Helper to recursively/iteratively extract valid CfgVehicles classnames from raw template values
private _fnc_extractClasses = {
    params ["_input"];
    private _result = [];
    if (isNil "_input") exitWith { _result };
    
    if (_input isEqualType "") then {
        if (_input != "" && { isClass (configFile >> "CfgVehicles" >> _input) }) then {
            _result pushBack _input;
        };
    } else {
        if (_input isEqualType []) then {
            {
                if (!isNil "_x") then {
                    if (_x isEqualType "") then {
                        if (_x != "" && { isClass (configFile >> "CfgVehicles" >> _x) }) then {
                            _result pushBack _x;
                        };
                    } else {
                        if (_x isEqualType []) then {
                            // Handles weighted tuples like ["classname", 1] or nested arrays
                            if (count _x > 0 && { (_x select 0) isEqualType "" }) then {
                                private _cls = _x select 0;
                                if (_cls != "" && { isClass (configFile >> "CfgVehicles" >> _cls) }) then {
                                    _result pushBack _cls;
                                };
                            };
                        };
                    };
                };
            } forEach _input;
        };
    };
    _result
};

// Priority vehicle resolver:
// 1. Active rebel template (A3A_faction_reb)
// 2. Compatible faction fallbacks (A3A_faction_occ, A3A_faction_inv)
// 3. Vanilla fallback classnames
private _resolveVeh = {
    params ["_keys", "_defaults"];
    private _foundVeh = "";

    // Priority 1: Active Rebel Faction Template
    if (!isNil "A3A_faction_reb" && { A3A_faction_reb isEqualType createHashMap }) then {
        {
            private _rawVal = A3A_faction_reb getOrDefault [_x, []];
            private _validClasses = [_rawVal] call _fnc_extractClasses;
            if (count _validClasses > 0) exitWith {
                _foundVeh = _validClasses select 0;
            };
        } forEach _keys;
    };

    // Priority 2: Compatible Occupant / Invader Faction Fallbacks
    if (_foundVeh == "") then {
        {
            private _facVar = _x;
            private _facMap = missionNamespace getVariable [_facVar, nil];
            if (!isNil "_facMap" && { _facMap isEqualType createHashMap }) then {
                {
                    private _rawVal = _facMap getOrDefault [_x, []];
                    private _validClasses = [_rawVal] call _fnc_extractClasses;
                    if (count _validClasses > 0) exitWith {
                        _foundVeh = _validClasses select 0;
                    };
                } forEach _keys;
            };
            if (_foundVeh != "") exitWith {};
        } forEach ["A3A_faction_occ", "A3A_faction_inv"];
    };

    // Priority 3: Vanilla Fallback Classnames
    if (_foundVeh == "") then {
        {
            if (isClass (configFile >> "CfgVehicles" >> _x)) exitWith { _foundVeh = _x; };
        } forEach _defaults;
    };

    _foundVeh
};

// Keys to check per role (in order of preference)
private _keysLightArmed = ["vehiclesLightArmed", "vehiclesMilitiaLightArmed"];
private _keysAT = ["vehiclesAT", "vehiclesMilitiaAT"];
private _keysAA = ["vehiclesAA"];
private _keysAPC = ["vehiclesIFVs", "vehiclesAPCs", "vehiclesLightAPCs", "vehiclesMilitiaAPCs"];
private _keysTank = ["vehiclesTanks", "vehiclesLightTanks", "vehiclesIFVs"];

private _defaultsLightArmed = ["I_G_Offroad_01_armed_F", "B_G_Offroad_01_armed_F", "O_G_Offroad_01_armed_F"];
private _defaultsAT = ["I_G_Offroad_01_AT_F", "B_G_Offroad_01_AT_F", "O_G_Offroad_01_AT_F"];
private _defaultsAA = ["I_LT_01_AA_F", "B_APC_Tracked_01_AA_F", "O_APC_Tracked_02_AA_F", "I_E_Truck_02_AA_F"];
private _defaultsAPC = [
    "CUP_B_BMP2_CDF", "rhs_bmp2_cdf", "CUP_B_BTR80A_CDF", "rhs_btr80a_cdf", "CUP_B_BTR80_CDF", "rhs_btr80_cdf",
    "CUP_I_BMP2_NAPA", "CUP_I_BTR60_NAPA", "I_APC_tracked_03_cannon_F", "O_APC_Tracked_02_cannon_F", "B_APC_Wheeled_01_cannon_F", "O_APC_Wheeled_02_rcws_v2_F",
    "CUP_B_T55_CDF", "CUP_I_T55_NAPA", "rhs_sprut_vdv", "rhs_bmd4", "rhs_bmd2", "B_AFV_Wheeled_01_cannon_F", "I_LT_01_cannon_F", "I_LT_01_AT_F"
];
private _defaultsTank = [
    "CUP_B_T72_CDF", "rhs_t72ba_tv", "CUP_I_T72_NAPA", "rhs_t72bc_tv", "CUP_B_M1A1SA_TUSK_Woodland_US_Army", "rhs_t90a_tv", "rhs_t80", 
    "I_MBT_03_cannon_F", "O_MBT_02_cannon_F", "B_MBT_01_cannon_F", "B_AFV_Wheeled_01_up_cannon_F"
];

// Resolve vehicle classnames for each role
private _lightArmed = [_keysLightArmed, _defaultsLightArmed] call _resolveVeh;
private _at = [_keysAT, _defaultsAT] call _resolveVeh;
private _aa = [_keysAA, _defaultsAA] call _resolveVeh;
private _apc = [_keysAPC, _defaultsAPC] call _resolveVeh;
private _tank = [_keysTank, _defaultsTank] call _resolveVeh;

A3A_planning_cachedVehicles set ["LIGHT_ARMED", _lightArmed];
A3A_planning_cachedVehicles set ["AT", _at];
A3A_planning_cachedVehicles set ["AA", _aa];
A3A_planning_cachedVehicles set ["APC", _apc];
A3A_planning_cachedVehicles set ["TANK", _tank];

// Pre-build available squad listbox options
private _menuItems = [
    ["Infantry Squad", "0"],
    ["Infantry Team", "1"],
    ["AT Team", "2"],
    ["AA Team", "13"],
    ["Sniper Team", "3"],
    ["MG Team", "4"],
    ["Mortar Team", "5"]
];

if (_tier >= 1) then {
    if (_lightArmed != "") then { _menuItems pushBack ["Armed Technical (MG)", "6"]; };
    if (_at != "") then { _menuItems pushBack ["AT Technical (SPG/AT)", "7"]; };
};

if (_tier >= 3) then {
    if (_aa != "") then { _menuItems pushBack ["Anti-Air Vehicle", "9"]; };
};

if (_tier >= 6) then {
    if (_apc != "") then { _menuItems pushBack ["Armored APC", "11"]; };
};

if (_tier >= 8) then {
    if (_tank != "") then { _menuItems pushBack ["Combat Tank", "12"]; };
};

A3A_planning_cachedVehicles set ["MENU_ITEMS", _menuItems];

diag_log format ["[A3A Ultimate Tweaks Extender] Siege Planner vehicle cache ready. WL %1 menu items: %2",
	_tier, (_menuItems apply {
		_x select 0
	})];