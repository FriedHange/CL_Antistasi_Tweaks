/*
    fn_loadState.sqf
    Handles persistent campaign loading for CL Antistasi Tweaks.
    Listens to AU event: CBA_EVENT_SERVER_GAME_LOAD ("A3A_event_serverGameLoad").

    Environment: Server, unscheduled
    Arguments:
        0: _saveData <HASHMAP> - Shared plugin save dictionary provided by Antistasi Ultimate.
*/
params [["_saveData", nil, [createHashMap]]];

if (!isServer) exitWith {};
if (isNil "_saveData" || { !(_saveData isEqualType createHashMap) }) exitWith {
    diag_log "[CL Antistasi Tweaks] Warning: Load event called without valid save HashMap.";
};

private _modData = _saveData getOrDefault ["CL_Antistasi_Tweaks", nil];
if (isNil "_modData" || { !(_modData isEqualType createHashMap) }) exitWith {
    diag_log "[CL Antistasi Tweaks] No previous save data found for CL Antistasi Tweaks.";
};

diag_log "[CL Antistasi Tweaks] Restoring persistent save data...";

// Extract and sanitize discovered markers (strictly strings)
private _loadedMarkers = _modData getOrDefault ["discoveredMarkers", []];
private _sanitizedMarkers = [];

if (_loadedMarkers isEqualType []) then {
    {
        if (_x isEqualType "" && { _x != "" }) then {
            _sanitizedMarkers pushBackUnique _x;
        };
    } forEach _loadedMarkers;
};

// Merge with any markers already registered in missionNamespace
private _currentMarkers = missionNamespace getVariable ["A3A_tweak_discoveredMarkers", []];
if (_currentMarkers isEqualType []) then {
    {
        if (_x isEqualType "" && { _x != "" }) then {
            _sanitizedMarkers pushBackUnique _x;
        };
    } forEach _currentMarkers;
};

A3A_tweak_discoveredMarkers = _sanitizedMarkers;
publicVariable "A3A_tweak_discoveredMarkers";

// Sync discovered zones into native revealedZones so native AU systems recognize them
if (isNil "revealedZones") then { revealedZones = []; };
private _revealedUpdated = false;

{
    private _candidate = _x;
    if ((_candidate find "Dum") == 0) then {
        _candidate = _candidate select [3];
    };
    if (_candidate != "" && { !(_candidate in revealedZones) }) then {
        // Only push if it corresponds to an actual zone in markersX or known military lists
        private _knownZones = (missionNamespace getVariable ["markersX", []])
            + (missionNamespace getVariable ["airportsX", []])
            + (missionNamespace getVariable ["outposts", []])
            + (missionNamespace getVariable ["milbases", []])
            + (missionNamespace getVariable ["resourcesX", []])
            + (missionNamespace getVariable ["factories", []])
            + (missionNamespace getVariable ["seaports", []])
            + (missionNamespace getVariable ["controlsX", []]);

        if (_candidate in _knownZones) then {
            revealedZones pushBackUnique _candidate;
            _revealedUpdated = true;
        };
    };
} forEach _sanitizedMarkers;

if (_revealedUpdated) then {
    publicVariable "revealedZones";
};

diag_log format [
    "[CL Antistasi Tweaks] Persistent state loaded successfully. Restored %1 discovered markers.",
    count _sanitizedMarkers
];
