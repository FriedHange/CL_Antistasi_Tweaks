/*
    fn_saveState.sqf
    Handles persistent campaign saving for CL Antistasi Tweaks.
    Listens to AU event: CBA_EVENT_SERVER_GAME_SAVE ("A3A_event_serverGameSave").

    Environment: Server, unscheduled
    Arguments:
        0: _saveData <HASHMAP> - Shared plugin save dictionary provided by Antistasi Ultimate.

    JSON Serialization Standard:
        - No SIDE data types (convert to SCALAR if ever stored).
        - No OBJECT references (use classnames or string identifiers).
        - HashMap keys MUST be STRINGs.
*/
params [["_saveData", nil, [createHashMap]]];

if (!isServer) exitWith {};
if (isNil "_saveData" || { !(_saveData isEqualType createHashMap) }) exitWith {
    diag_log "[CL Antistasi Tweaks] Error: Save event called without valid save HashMap.";
};

diag_log "[CL Antistasi Tweaks] Collecting persistent save data...";

// Filter discovered markers to ensure strictly valid strings (JSON safe)
private _rawMarkers = missionNamespace getVariable ["A3A_tweak_discoveredMarkers", []];
private _cleanMarkers = [];

if (_rawMarkers isEqualType []) then {
    {
        if (_x isEqualType "" && { _x != "" }) then {
            _cleanMarkers pushBackUnique _x;
        };
    } forEach _rawMarkers;
};

// Assemble mod dictionary
private _modData = createHashMapFromArray [
    ["discoveredMarkers", _cleanMarkers]
];

// Write into the root plugin save map under our unique tagged key
_saveData set ["CL_Antistasi_Tweaks", _modData];

diag_log format [
    "[CL Antistasi Tweaks] Persistent state saved successfully. Discovered markers count: %1.",
    count _cleanMarkers
];
