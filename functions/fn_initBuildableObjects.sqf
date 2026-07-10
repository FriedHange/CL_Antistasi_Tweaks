/*
    fn_initBuildableObjects.sqf
    Wrapper function to append new buildable trenches, trees, houses, and decorations to the RTS/Construction Crate build list.
*/
diag_log "[A3A Ultimate Tweaks Extender] initBuildableObjects wrapper starting...";

// Call original function to populate A3A_buildableObjects
private _result = call A3A_fnc_initBuildableObjects_original;

// 1. Add trenches to existing Bunkers category
private _bunkersCategoryKey = "$STR_antistasi_dialogs_construction_menu_category_bunkers";
private _found = false;
private _trenches = [
    ["Land_Trench_01_grass_F", 300],
    ["Land_Trench_01_forest_F", 300],
    ["Land_Trench_01_sand_F", 300],
    ["Land_Trench_01_mud_F", 300]
] select { isClass (configFile >> "CfgVehicles" >> (_x select 0)) };

{
    if (_x select 0 == _bunkersCategoryKey) exitWith {
        private _items = _x select 2;
        _items append _trenches;
        _found = true;
        diag_log "[A3A Ultimate Tweaks Extender] Added trenches to existing Bunkers category.";
    };
} forEach A3A_buildableObjects;

if (!_found && {count _trenches > 0}) then {
    A3A_buildableObjects pushBack [
        _bunkersCategoryKey,
        "\A3\EditorPreviews_F\Data\CfgVehicles\Land_BagBunker_Large_F.jpg",
        _trenches
    ];
    diag_log "[A3A Ultimate Tweaks Extender] Created new Bunkers category for trenches.";
};

// Helper function to safely filter and append custom categories
private _fnc_filterAndAddCategory = {
    params ["_categoryName", "_previewPath", "_items"];
    private _validItems = _items select { isClass (configFile >> "CfgVehicles" >> (_x select 0)) };
    if (count _validItems > 0) then {
        A3A_buildableObjects pushBack [_categoryName, _previewPath, _validItems];
        diag_log format ["[A3A Ultimate Tweaks Extender] Added category %1 with %2 items.", _categoryName, count _validItems];
    };
};

// 2. Add Trees & Vegetation Category
[
    "Trees & Vegetation",
    "\A3\EditorPreviews_F\Data\CfgVehicles\Land_ClutterCutter_medium_F.jpg",
    [
        ["t_PinusS1s_F", 100],
        ["t_PinusS2s_F", 100],
        ["t_FicusB1s_F", 100],
        ["t_FagusS2s_F", 100],
        ["t_PopulusN3s_F", 80],
        ["t_Cocos_tall_F", 90],
        ["t_Banana_F", 60],
        ["t_Inocarpus_F", 120],
        ["b_FicusC2d_F", 40]
    ]
] call _fnc_filterAndAddCategory;

// 3. Add Houses & Sheds Category
[
    "Houses & Sheds",
    "\A3\EditorPreviews_F\Data\CfgVehicles\Land_Cargo_House_V1_F.jpg",
    [
        ["Land_House_Small_01_F", 2000],
        ["Land_House_Big_01_F", 3500],
        ["Land_Shed_Big_F", 800],
        ["Land_Shed_Small_F", 400],
        ["Land_Slum_House01_F", 600],
        ["Land_Slum_House02_F", 600],
        ["Land_WoodenShack_01_F", 500]
    ]
] call _fnc_filterAndAddCategory;

// 4. Add Base Decorations Category
[
    "Base Decorations",
    "\a3\editorpreviews_f\Data\CfgVehicles\Land_CampingChair_V1_F.jpg",
    [
        ["CamoNet_BLUFOR_open_F", 250],
        ["CamoNet_BLUFOR_F", 150],
        ["Land_Portable_generator_F", 300],
        ["Land_MetalCase_01_large_F", 200],
        ["Land_CncWall4_F", 120],
        ["Land_CncWall1_F", 80],
        ["Land_New_WiredFence_10m_F", 50],
        ["Land_New_WiredFence_5m_F", 30],
        ["Land_CampingTable_F", 40],
        ["Land_CampingChair_V1_F", 15],
        ["Land_Camping_Light_F", 30]
    ]
] call _fnc_filterAndAddCategory;

diag_log "[A3A Ultimate Tweaks Extender] initBuildableObjects wrapper completed.";
A3A_buildableObjects;
