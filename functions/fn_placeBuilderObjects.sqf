/*
    fn_placeBuilderObjects.sqf
    Custom placement handler to support instant building.
*/
diag_log "[A3A Ultimate Tweaks Extender] placeBuilderObjects custom starting...";

params [["_objects",[],[[]]]];

private _autoBuild = (missionNamespace getVariable ["A3A_tweak_autoBuild", 0]) isEqualTo 1;

if (!_autoBuild) exitWith {
    diag_log "[A3A Ultimate Tweaks Extender] AutoBuild disabled, running original placeBuilderObjects...";
    _objects call A3A_fnc_placeBuilderObjects_original;
};

diag_log "[A3A Ultimate Tweaks Extender] AutoBuild enabled! Constructing placed objects instantly...";

private _runCallback = {
    params[["_object", objNull, [objNull]], ["_callbackName", "", [""]], ["_params", [], [[]]]];
    if (isNull _object) exitWith {};
    if (isText(configOf _object >> _callbackName)) then {
        ([_object] + _params) call compile getText(configOf _object >> _callbackName);
    };
};

{
    _x params ["_className", "_repairObj", "_position", "_direction", "_price"];

    if (isNull _repairObj) then {
        // Construction case - instantly build it
        private _building = createVehicle [_className, [0,0,0], [], 0, "CAN_COLLIDE"];
        _building setPosWorld _position;
        _building setVectorDirAndUp _direction;
        _building setVariable ["A3A_building", true, true];

        // Apply flag textures if it is a flag
        if (_className isEqualTo (A3A_faction_reb get "flag")) then {
            _building setFlagTexture (A3A_faction_reb get "flagTexture");
        };

        A3A_buildingsToSave pushBack _building;
        
        [_building, "A3A_core_onBuildingCompleted"] call _runCallback;
        diag_log format ["[A3A Ultimate Tweaks Extender] Instantly built %1 at %2", _className, _position];
    } else {
        // Repair case - instantly repair it
        _repairObj call A3A_fnc_repairRuinedBuilding;
        [_repairObj, "A3A_core_onBuildingRepaired"] call _runCallback;
        diag_log format ["[A3A Ultimate Tweaks Extender] Instantly repaired %1", typeOf _repairObj];
    };
} forEach _objects;

publicVariable "A3A_buildingsToSave";

diag_log "[A3A Ultimate Tweaks Extender] AutoBuild construction processing completed.";
