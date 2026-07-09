/*
    fn_postInit.sqf
    Initialize the Antistasi Ultimate Tweaks Extender.
    Overrides core functions with customized versions.
*/
diag_log "[A3A Ultimate Tweaks Extender] Initializing overrides...";

// Override functions
A3A_fnc_selfRevive = compile preprocessFileLineNumbers "\x\A3A\addons\tweaks\functions\fn_selfRevive.sqf";
A3A_fnc_isWithinMarkerArea = compile preprocessFileLineNumbers "\x\A3A\addons\tweaks\functions\fn_isWithinMarkerArea.sqf";
A3A_fnc_enemyNearCheck = compile preprocessFileLineNumbers "\x\A3A\addons\tweaks\functions\fn_enemyNearCheck.sqf";

diag_log "[A3A Ultimate Tweaks Extender] Overrides successfully applied.";
