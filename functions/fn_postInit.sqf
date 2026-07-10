/*
    fn_postInit.sqf
    Initialize the Antistasi Ultimate Tweaks Extender.
    Overrides core functions with customized versions.
*/
diag_log "[A3A Ultimate Tweaks Extender] Initializing overrides...";

// Override functions
A3A_fnc_selfRevive = compile preprocessFileLineNumbers "\CL_Antistasi_Tweaks\functions\fn_selfRevive.sqf";
A3A_fnc_isWithinMarkerArea = compile preprocessFileLineNumbers "\CL_Antistasi_Tweaks\functions\fn_isWithinMarkerArea.sqf";

// Override buildable objects initialization to inject new trenches
A3A_fnc_initBuildableObjects_original = A3A_fnc_initBuildableObjects;
A3A_fnc_initBuildableObjects = compile preprocessFileLineNumbers "\CL_Antistasi_Tweaks\functions\fn_initBuildableObjects.sqf";

// Override builder placing objects function to support auto-building
A3A_fnc_placeBuilderObjects_original = A3A_fnc_placeBuilderObjects;
A3A_fnc_placeBuilderObjects = compile preprocessFileLineNumbers "\CL_Antistasi_Tweaks\functions\fn_placeBuilderObjects.sqf";

diag_log "[A3A Ultimate Tweaks Extender] Overrides successfully applied.";
