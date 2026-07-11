/*
    Overridden A3A_fnc_selfRevive
    Allows reviving without FAK, customized cooldown, and custom post-heal damage.
*/
if !(player getVariable ["incapacitated", false]) exitWith {};

private _hintTitle = localize "STR_A3A_selfRevive_title";

// Read kit requirement tweak
private _noKitRequired = missionNamespace getVariable ["A3A_selfReviveTweak_NoKit", false];
private _hasFAKs = [];

if (!_noKitRequired) then {
    private _rebKits = [];
    if (!isNil "A3A_faction_reb" && {A3A_faction_reb isEqualType createHashMap}) then {
        _rebKits = A3A_faction_reb getOrDefault ["firstAidKits", []];
    };
    private _firstAidKits = ["FirstAidKit"] + _rebKits;
    _hasFAKs = _firstAidKits arrayIntersect items player;
    
    if (_hasFAKs isEqualTo []) exitWith {
        [_hintTitle, localize "STR_A3A_selfRevive_noFAK"] call A3A_fnc_customHint;
    };
};

// Check cooldown
if (time < player getVariable ["A3A_selfReviveTimeout", -1]) exitWith {
    [_hintTitle, localize "STR_A3A_selfRevive_recent"] call A3A_fnc_customHint;
};

// Perform revive
player setVariable ["incapacitated", false, true];

// Read custom post-heal damage (defaults to 50% if not defined)
private _damagePct = missionNamespace getVariable ["A3A_selfReviveTweak_Damage", 50];
player setDamage (_damagePct / 100);

// Remove FAK if needed
if (!_noKitRequired && {_hasFAKs isNotEqualTo []}) then {
    player removeItem selectRandom _hasFAKs;
};

// Read custom cooldown
private _timeout = missionNamespace getVariable ["A3A_selfReviveTweak_Cooldown", 300];
player setVariable ["A3A_selfReviveTimeout", _timeout + time];

[_hintTitle, localize "STR_A3A_selfRevive_success"] call A3A_fnc_customHint;

private _aimCoef = missionNamespace getVariable ["A3A_selfReviveAimCoef", 3];
player setCustomAimCoef _aimCoef;

// Visual effect (standard desaturation)
private _handle = ppEffectCreate ["ColorCorrections", 1537];
_handle ppEffectEnable true;
_handle ppEffectAdjust [1, 1, 0,
	[0, 0, 0, 0],
	[1, 1, 1, 0.5],
	[0.299, 0.587, 0.114, 0]
];
_handle ppEffectCommit 5;
A3A_selfRevivePPHandle = _handle;

_timeout spawn {
    sleep _this;
    [false] call A3A_fnc_selfReviveReset;
};
