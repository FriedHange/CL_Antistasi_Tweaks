/*
    fn_postInit.sqf
    Initialize the Antistasi Ultimate Tweaks Extender.
    Overrides core functions with customized versions.
*/
diag_log "[A3A Ultimate Tweaks Extender] Initializing overrides...";

// Override self-revive and marker area functions
A3A_fnc_selfRevive = compile preprocessFileLineNumbers "\CL_Antistasi_Tweaks\functions\fn_selfRevive.sqf";
A3A_fnc_isWithinMarkerArea = compile preprocessFileLineNumbers "\CL_Antistasi_Tweaks\functions\fn_isWithinMarkerArea.sqf";

// Override builder placing objects function to support auto-building.
// A3A_fnc_placeBuilderObjects is freshly compiled by CfgFunctions at every mission start,
// so we always capture the real original here at postInit time.
A3A_fnc_placeBuilderObjects_original = A3A_fnc_placeBuilderObjects;
A3A_fnc_placeBuilderObjects = compile preprocessFileLineNumbers "\CL_Antistasi_Tweaks\functions\fn_placeBuilderObjects.sqf";

// Compile the helper builder UI resizer globally
A3A_fnc_builderUIResize = compile preprocessFileLineNumbers "\CL_Antistasi_Tweaks\functions\fn_builderUIResize.sqf";

// Override team leader placer dialog to inject expand/collapse button.
A3A_fnc_teamLeaderRTSPlacerDialog_original = A3A_fnc_teamLeaderRTSPlacerDialog;
A3A_fnc_teamLeaderRTSPlacerDialog = compile preprocessFileLineNumbers "\CL_Antistasi_Tweaks\functions\fn_teamLeaderRTSPlacerDialog.sqf";
A3A_fnc_teamLeaderRTSPlacerDialog_toggleHeight = compile preprocessFileLineNumbers "\CL_Antistasi_Tweaks\functions\fn_teamLeaderRTSPlacerDialog_toggleHeight.sqf";

// Override Petros mission requests, resourcecheck, and fast travel
A3A_fnc_missionRequest_original = A3A_fnc_missionRequest;
A3A_fnc_missionRequest = compile preprocessFileLineNumbers "\CL_Antistasi_Tweaks\functions\fn_missionRequest.sqf";
A3A_fnc_resourcecheck = compile preprocessFileLineNumbers "\CL_Antistasi_Tweaks\functions\fn_resourcecheck.sqf";
A3A_fnc_fastTravelRadio = compile preprocessFileLineNumbers "\CL_Antistasi_Tweaks\functions\fn_fastTravelRadio.sqf";

// Override builder actions and builder complete handlers
A3A_fnc_addBuildingActions = compile preprocessFileLineNumbers "\CL_Antistasi_Tweaks\functions\fn_addBuildingActions.sqf";
A3A_fnc_buildingComplete = compile preprocessFileLineNumbers "\CL_Antistasi_Tweaks\functions\fn_buildingComplete.sqf";

// Sync lobby parameters from server to all clients
if (isServer) then {
    diag_log "[A3A Ultimate Tweaks Extender] Loading and broadcasting lobby parameters...";
    {
        _x params ["_paramName", "_defaultValue"];
        private _val = [_paramName, _defaultValue] call BIS_fnc_getParamValue;
        missionNamespace setVariable [_paramName, _val, true];
        diag_log format ["[A3A Ultimate Tweaks Extender] Synced parameter: %1 = %2", _paramName, _val];
    } forEach [
        ["A3A_tweak_autoBuild", 1],
        ["A3A_selfReviveTweak_NoKit", 0],
        ["A3A_selfReviveTweak_Cooldown", 300],
        ["A3A_selfReviveTweak_Damage", 50],
        ["A3A_tweak_saveRadiusHQ", 50],
        ["A3A_tweak_saveRadiusBuffer", 0],
        ["A3A_tweak_missionCooldown", 0],
        ["A3A_tweak_randomMissionChanceMultiplier", 1],
        ["A3A_tweak_fastTravelSpeedMultiplier", 1],
        ["A3A_tweak_builderChainRadius", 0],
        ["A3A_tweak_discoveryReveal", 1],
        ["A3A_tweak_discoveryDistance", 200]
    ];
};

// Client-side loop to reveal hidden enemy zones when player gets near
if (hasInterface) then {
    [] spawn {
        scriptName "A3A_Ultimate_Tweaks_MarkerRevealLoop";
        waitUntil { !isNil "markersX" && { !isNil "hideEnemyMarkers" } };
        if !(hideEnemyMarkers) exitWith {};

        // Queue system variables
        A3A_tweak_discoveryQueue = [];
        A3A_tweak_discoveryRunning = false;

        private _fnc_processQueue = {
            if (A3A_tweak_discoveryRunning) exitWith {};
            A3A_tweak_discoveryRunning = true;
            [] spawn {
                while { count A3A_tweak_discoveryQueue > 0 } do {
                    private _placeName = A3A_tweak_discoveryQueue deleteAt 0;
                    private _msg = format [
                        "<t size='1.3' color='#84B062' font='PuristaBold' align='center'>LOCATION DISCOVERED</t><br/><t size='1.7' color='#E3DCBE' font='PuristaMedium' align='center'>%1</t>",
                        _placeName
                    ];
                    // Display text at center-top of screen (y = -0.20), duration 5s, fade-in/out 0.2s
                    [_msg, -1, -0.20, 5, 0.2, 0, 9700] spawn BIS_fnc_dynamicText;
                    sleep 5.45; // 0.2s fade-in + 5s duration + 0.2s fade-out + 0.05s buffer
                };
                A3A_tweak_discoveryRunning = false;
            };
        };

        while { true } do {
            sleep 5;
            // Check if feature is enabled via lobby parameters
            private _enabled = missionNamespace getVariable ["A3A_tweak_discoveryReveal", 1];
            if (_enabled isEqualTo 0) then { continue };

            if (!alive player) then { continue };
            private _playerPos = getPos player;
            private _revealDist = missionNamespace getVariable ["A3A_tweak_discoveryDistance", 200];

            {
                private _dumMarker = "Dum" + _x;
                if (markerAlpha _dumMarker == 0) then {
                    private _markerPos = getMarkerPos _x;
                    if (_playerPos distance2D _markerPos < _revealDist) then {
                        _dumMarker setMarkerAlpha 1;
                        A3A_tweak_discoveryQueue pushBack (markerText _dumMarker);
                        [] call _fnc_processQueue;
                    };
                };
            } forEach markersX;
        };
    };
};

// Overrides applied
diag_log "[A3A Ultimate Tweaks Extender] Overrides applied.";
