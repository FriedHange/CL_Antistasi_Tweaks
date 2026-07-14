/*
    fn_buildingComplete.sqf
    Server-side function handling construction/repair completion, with custom chain building radius features.
*/
if (!isServer) exitWith {
    diag_log "[A3A Tweaks] Error: buildingComplete called on client!";
};

params ["_target", ["_finished", true], ["_chainBuild", true]];

// Capture target position before deleting the object
private _targetPos = getPos _target;

// Remove from unbuilt list
if (!isNil "A3A_unbuiltObjects") then {
    A3A_unbuiltObjects deleteAt (A3A_unbuiltObjects find _target);
    publicVariable "A3A_unbuiltObjects";
};

private _buildClass = _target getVariable ["A3A_build_class", ""];
private _buildDir = _target getVariable ["A3A_build_dir", [[0,1,0],[0,0,1]]];
private _buildPos = _target getVariable ["A3A_build_pos", [0,0,0]];
private _buildPrice = _target getVariable ["A3A_build_price", 10];
private _repairObj = _target getVariable ["A3A_build_repairObj", objNull];

deleteVehicle _target; // delete the plank object

private _runCallback = {
    params[["_object", objNull, [objNull]], ["_callbackName", "", [""]], ["_params", [], [[]]]];
    if (isNull _object) exitWith {};
    // Use configOf (same as original) for compatibility with macros like QGVAR
    if (isText(configOf _object >> _callbackName)) then {
        ([_object] + _params) call compile getText(configOf _object >> _callbackName);
    };
};

// Cancel case
if (!_finished) exitWith {
    if (_buildPrice > 0) then {
        [0, _buildPrice] spawn A3A_fnc_resourcesFIA;
    };
};

// Repair case, just call the repair function
if (!isNull _repairObj) exitWith {
    _repairObj call A3A_fnc_repairRuinedBuilding;
    [_repairObj, "A3A_core_onBuildingRepaired"] call _runCallback;
};

// Spawning the building
private _building = createVehicle [_buildClass, [0,0,0], [], 0, "CAN_COLLIDE"];
if (!isNull _building) then {
    _building setPosWorld _buildPos;
    _building setVectorDirAndUp _buildDir;
    _building setVariable ["A3A_building", true, true];            // Used to identify removable buildings

    if (isNil "A3A_buildingsToSave") then { A3A_buildingsToSave = []; };
    A3A_buildingsToSave pushBack _building;
    publicVariable "A3A_buildingsToSave";

    // Fix vanilla bug where _className was checked (which is undefined) instead of _buildClass
    if (!isNil "A3A_faction_reb" && {A3A_faction_reb isEqualType createHashMap}) then {
        if (_buildClass isEqualTo (A3A_faction_reb get "flag")) then {
            _building setFlagTexture (A3A_faction_reb get "flagTexture");
        };
    };

    [_building, "A3A_core_onBuildingCompleted"] call _runCallback;
};

// --- Radius Build (Chain Construction) Tweak ---
if (_finished && {_chainBuild}) then {
    private _radius = missionNamespace getVariable ["A3A_tweak_builderChainRadius", 0];
    if (_radius > 0) then {
        // Find all unbuilt boxes in range (excluding the one just processed)
        private _nearPlanks = (missionNamespace getVariable ["A3A_unbuiltObjects", []]) select {
            !isNull _x && {_x distance _targetPos <= _radius}
        };

        diag_log format ["[A3A Tweaks] Chain building triggered. Radius=%1m. Found %2 items in range.", _radius, count _nearPlanks];

        {
            // Call completion on neighbor, disable recurse chaining to avoid infinite loop
            [_x, true, false] call A3A_fnc_buildingComplete;
        } forEach _nearPlanks;
    };
};
