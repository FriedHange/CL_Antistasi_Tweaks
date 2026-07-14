/*
    fn_planning_cacheVehicles.sqf
    Pre-builds and caches rebel vehicle details and listbox entries based on War Level.
    Avoids expensive configFile / isClass scans on every UI update.
*/

if (isNil "A3A_faction_reb") exitWith {};

private _tier = missionNamespace getVariable ["tierWar", 1];

if (isNil "A3A_planning_cachedVehicles") then {
    A3A_planning_cachedVehicles = createHashMap;
};
if (isNil "A3A_planning_cachedTier") then {
    A3A_planning_cachedTier = -1;
};
if (isNil "A3A_planning_cachedDisplayNames") then {
    A3A_planning_cachedDisplayNames = createHashMap;
};

// Return immediately if the cache for the current War Level is already populated
if (_tier isEqualTo A3A_planning_cachedTier && {count A3A_planning_cachedVehicles > 0}) exitWith {};

A3A_planning_cachedTier = _tier;
A3A_planning_cachedVehicles = createHashMap;

private _resolveVeh = {
    params ["_key", "_defaults"];
    private _list = A3A_faction_reb getOrDefault [_key, []];
    if (_key == "vehiclesTanks") then {
        _list = _list + (A3A_faction_reb getOrDefault ["vehiclesIFVs", []]);
    };
    private _veh = "";
    {
        if (!isNil "_x" && {_x != "" && {isClass (configFile >> "CfgVehicles" >> _x)}}) exitWith {
            _veh = _x;
        };
    } forEach _list;
    if (_veh == "") then {
        {
            if (isClass (configFile >> "CfgVehicles" >> _x)) exitWith { _veh = _x; };
        } forEach _defaults;
    };
    _veh
};

// Resolve and cache vehicles for each category
private _truck = ["vehiclesTruck", ["I_G_Van_01_transport_F"]] call _resolveVeh;
private _lightArmed = ["vehiclesLightArmed", ["I_G_Offroad_01_armed_F"]] call _resolveVeh;
private _at = ["vehiclesAT", ["I_G_Offroad_01_AT_F"]] call _resolveVeh;
private _aa = ["vehiclesAA", ["I_G_Van_01_transport_F"]] call _resolveVeh;
private _apc = ["vehiclesAPCs", []] call _resolveVeh;
private _tank = ["vehiclesTanks", []] call _resolveVeh;

A3A_planning_cachedVehicles set ["TRUCK", _truck];
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
    if (_apc != "") then { _menuItems pushBack ["Armored APC", "11"]; };
};
if (_tier >= 6) then {
    if (_tank != "") then { _menuItems pushBack ["Combat Tank", "12"]; };
};

_menuItems pushBack ["Vehicle Crew Squad", "8"];
A3A_planning_cachedVehicles set ["MENU_ITEMS", _menuItems];

diag_log format ["[A3A Ultimate Tweaks Extender] Refreshed Siege Planner vehicle cache for War Level %1.", _tier];
