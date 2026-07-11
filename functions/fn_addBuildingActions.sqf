/*
    fn_addBuildingActions.sqf
    Client-side override to add actions for building and cancelling construction.
*/
params ["_plankObject", "_holdTime"];

private _dist = 8; // Reverted back to default vanilla distance

[
    _plankObject,
    "Build",
    "a3\ui_f\data\igui\cfg\actions\repair_ca.paa",
    "a3\ui_f\data\igui\cfg\actions\repair_ca.paa",
    "isNull objectParent player && {player call A3A_fnc_isEngineer && {(player distance _target < 8)}}",
    "[player] call A3A_fnc_canFight and (player distance _target < 10)",
    {},
    {},
    {
        [_this#0, true] remoteExecCall ["A3A_fnc_buildingComplete", 2];
    },
    {},
    [],
    _holdTime
] call BIS_fnc_holdActionAdd;

_plankObject addAction ["Cancel",
    {
        [_this#0, false] remoteExecCall ["A3A_fnc_buildingComplete", 2];
    },
    nil,
    1.5,
    true,
    true,
    "",
    "player call A3A_fnc_isEngineer",
    _dist
];
