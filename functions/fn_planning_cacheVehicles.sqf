/*
	    fn_planning_cacheVehicles.sqf
	    Pre-builds and caches rebel vehicle details and listbox entries based on War Level.
	    Avoids expensive configFile / isClass scans on every UI update.
	
	    NOTE: The short-circuit "return if already cached for this WL" guard was intentionally
	    removed. The cache is cheap to build and must respond immediately when tierWar changes
	    mid-campaign (e.g. WL 1 → WL 6). A frozen cache from an earlier WL caused vehicles
	    unlocked at WL 3 and WL 6 to never appear in the recruitment menu.
*/

if (isNil "A3A_faction_reb") exitWith {};
private _tier = missionNamespace getVariable ["tierWar", 1];

if (isNil "A3A_planning_cachedVehicles") then { A3A_planning_cachedVehicles = createHashMap; };
if (isNil "A3A_planning_cachedDisplayNames") then { A3A_planning_cachedDisplayNames = createHashMap; };

// Always rebuild the cache so WL changes are immediately reflected.
A3A_planning_cachedVehicles = createHashMap;

private _resolveVeh = {
    params ["_key", "_defaults"];
    private _list = A3A_faction_reb getOrDefault [_key, []];
    if (_key == "vehiclesTanks") then { _list = _list + (A3A_faction_reb getOrDefault ["vehiclesIFVs", []]); };
    private _veh = "";
    {
        if (!isNil "_x" && { _x != "" && { isClass (configFile >> "CfgVehicles" >> _x) } }) exitWith { _veh = _x; };
    } forEach _list;
    if (_veh == "") then {
        {
            if (isClass (configFile >> "CfgVehicles" >> _x)) exitWith { _veh = _x; };
        } forEach _defaults;
    };
    _veh
};

// Resolve and cache vehicles for each category
private _lightArmed = ["vehiclesLightArmed", ["I_G_Offroad_01_armed_F", "B_G_Offroad_01_armed_F", "O_G_Offroad_01_armed_F"]] call _resolveVeh;
private _at = ["vehiclesAT", ["I_G_Offroad_01_AT_F", "B_G_Offroad_01_AT_F", "O_G_Offroad_01_AT_F"]] call _resolveVeh;
private _aa = ["vehiclesAA", ["I_LT_01_AA_F", "B_APC_Tracked_01_AA_F", "O_APC_Tracked_02_AA_F", "I_E_Truck_02_AA_F"]] call _resolveVeh;
private _apcDefaults = [
    "CUP_B_BMP2_CDF", "rhs_bmp2_cdf", "CUP_B_BTR80A_CDF", "rhs_btr80a_cdf", "CUP_B_BTR80_CDF", "rhs_btr80_cdf",
    "CUP_I_BMP2_NAPA", "CUP_I_BTR60_NAPA", "I_APC_tracked_03_cannon_F", "O_APC_Tracked_02_cannon_F", "B_APC_Wheeled_01_cannon_F", "O_APC_Wheeled_02_rcws_v2_F",
    "CUP_B_T55_CDF", "CUP_I_T55_NAPA", "rhs_sprut_vdv", "rhs_bmd4", "rhs_bmd2", "B_AFV_Wheeled_01_cannon_F", "I_LT_01_cannon_F", "I_LT_01_AT_F"
];

private _tankDefaults = [
    "CUP_B_T72_CDF", "rhs_t72ba_tv", "CUP_I_T72_NAPA", "rhs_t72bc_tv", "CUP_B_M1A1SA_TUSK_Woodland_US_Army", "rhs_t90a_tv", "rhs_t80", 
    "I_MBT_03_cannon_F", "O_MBT_02_cannon_F", "B_MBT_01_cannon_F", "B_AFV_Wheeled_01_up_cannon_F"
];

private _apc = ["vehiclesAPCs", _apcDefaults] call _resolveVeh;
private _tank = ["vehiclesTanks", _tankDefaults] call _resolveVeh;

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

// WL 6+: medium armor (IFVs, APCs, Light Tanks)
if (_tier >= 6) then {
    if (_apc != "") then { _menuItems pushBack ["Armored APC", "11"]; };
};

// WL 8+: heavy armor (MBTs)
if (_tier >= 8) then {
    if (_tank != "") then { _menuItems pushBack ["Combat Tank", "12"]; };
};

A3A_planning_cachedVehicles set ["MENU_ITEMS", _menuItems];

diag_log format ["[A3A Ultimate Tweaks Extender] Siege Planner vehicle cache ready. WL %1 menu items: %2",
	_tier, (_menuItems apply {
		_x select 0
	})];