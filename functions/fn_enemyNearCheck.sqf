/*
    Overridden A3A_fnc_enemyNearCheck
    Supports custom fast travel / garage enemy check distance tweak.
*/
params [
    "_unitPos",
    ["_distance", missionNamespace getVariable ["enemyNearDistance", 150]]
];

if (isNil "_unitPos") exitWith { false };

// If caller did not provide a custom search distance, and we have our tweak enabled, use it
if (count _this < 2) then {
    private _customDistance = missionNamespace getVariable ["A3A_tweak_fastTravelEnemyDistance", -1];
    if (_customDistance >= 0) then {
        _distance = _customDistance;
    };
};

private _nearEnemies = ((units Occupants + units Invaders) inAreaArray [
    _unitPos, _distance, _distance]) select { behaviour _x isEqualTo "COMBAT" && {_x call A3A_fnc_canFight} };

(_nearEnemies isNotEqualTo [])
