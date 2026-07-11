/*
    fn_placeBuilderObjects.sqf
    Custom placement handler to support instant building.
*/
diag_log "[A3A Ultimate Tweaks Extender] placeBuilderObjects custom starting...";

params [["_objects",[],[[]]]];

// Global debug broadcast to verify function execution and parameter state
[format ["[A3A Tweaks Debug] Server received placeBuilderObjects. Items: %1, AutoBuild Parameter: %2", count _objects, missionNamespace getVariable ["A3A_tweak_autoBuild", 0]]] remoteExec ["systemChat", 0];

private _autoBuildVal = missionNamespace getVariable ["A3A_tweak_autoBuild", 1]; // Default to 1 (Enabled) if nil
private _autoBuild = (_autoBuildVal isEqualTo 1) || {(_autoBuildVal isEqualType true) && {_autoBuildVal}};

if (!_autoBuild) exitWith {
    diag_log "[A3A Ultimate Tweaks Extender] AutoBuild disabled, running original placeBuilderObjects...";
    if (isNil "A3A_fnc_placeBuilderObjects_original") then {
        A3A_fnc_placeBuilderObjects_original = compile preprocessFileLineNumbers "\A3A\core\functions\Builder\fn_placeBuilderObjects.sqf";
    };
    [_objects] call A3A_fnc_placeBuilderObjects_original;
};

// Send start status to all clients
[format ["[A3A Tweaks] Auto-Build triggered: Constructing %1 items...", count _objects]] remoteExec ["systemChat", 0];

private _runCallback = {
    params[["_object", objNull, [objNull]], ["_callbackName", "", [""]], ["_params", [], [[]]]];
    if (isNull _object) exitWith {};
    if (isText(configFile >> "CfgVehicles" >> typeOf _object >> _callbackName)) then {
        ([_object] + _params) call compile getText(configFile >> "CfgVehicles" >> typeOf _object >> _callbackName);
    };
};

{
    private _idx = _forEachIndex;
    try {
        _x params ["_className", "_repairObj", "_position", "_direction", "_price"];
        
        [format ["[A3A Tweaks] Processing item %1 of %2: %3", _idx + 1, count _objects, _className]] remoteExec ["systemChat", 0];

        if (isNull _repairObj) then {
            // Construction case - instantly build it
            // Safeguard: Spawn directly at the target position to prevent drowning/exploding at ocean map origin [0,0,0]
            private _spawnPos = if (!isNil "_position" && {_position isEqualType []}) then { _position } else { [0,0,0] };
            private _building = createVehicle [_className, _spawnPos, [], 0, "CAN_COLLIDE"];
            
            if (isNull _building) then {
                [format ["[A3A Tweaks] ERROR: Failed to create global object for %1", _className]] remoteExec ["systemChat", 0];
            } else {
                if (!isNil "_position" && {!isNil "_direction" && {_position isEqualType [] && {_direction isEqualType []}}}) then {
                    _building setPosWorld _position;
                    _building setVectorDirAndUp _direction;
                } else {
                    diag_log format ["[A3A Tweaks] WARNING: Position/Direction is nil or invalid for %1", _className];
                };
                
                _building setVariable ["A3A_building", true, true];

                // Apply flag textures if it is a flag
                if (!isNil "A3A_faction_reb" && {A3A_faction_reb isEqualType createHashMap}) then {
                    if (_className isEqualTo (A3A_faction_reb get "flag")) then {
                        _building setFlagTexture (A3A_faction_reb get "flagTexture");
                    };
                };

                if (isNil "A3A_buildingsToSave") then { A3A_buildingsToSave = []; };
                A3A_buildingsToSave pushBack _building;
                
                [_building, "A3A_core_onBuildingCompleted"] call _runCallback;
                
                [format ["[A3A Tweaks] Success: Instantly constructed %1", _className]] remoteExec ["systemChat", 0];
            };
        } else {
            // Repair case - instantly repair it
            _repairObj call A3A_fnc_repairRuinedBuilding;
            [_repairObj, "A3A_core_onBuildingRepaired"] call _runCallback;
            [format ["[A3A Tweaks] Success: Repaired %1", typeOf _repairObj]] remoteExec ["systemChat", 0];
        };
    } catch {
        [format ["[A3A Tweaks] EXCEPTION: %1", _exception]] remoteExec ["systemChat", 0];
        diag_log format ["[A3A Ultimate Tweaks Extender] CRITICAL: Exception in placeBuilderObjects: %1", _exception];
    };
} forEach _objects;

if (!isNil "A3A_buildingsToSave") then {
    publicVariable "A3A_buildingsToSave";
};

[format ["[A3A Tweaks] Auto-Build completed."]] remoteExec ["systemChat", 0];
