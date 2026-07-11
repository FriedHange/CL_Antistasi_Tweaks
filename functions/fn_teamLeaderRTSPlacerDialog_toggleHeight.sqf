/*
    fn_teamLeaderRTSPlacerDialog_toggleHeight.sqf
    Toggles the height of the teamLeaderBuilder UI between collapsed (1 row) and expanded (configured by lobby setting) states.
*/
private _display = findDisplay 9700;
if (isNull _display) exitWith {};

private _isExpanded = _display getVariable ["A3A_builder_expanded", false];
private _newState = !_isExpanded;
_display setVariable ["A3A_builder_expanded", _newState];

private _gridH = pixelH * pixelGridNoUIScale * 0.5;

// Hardcoded expanded height to 3 rows
private _expandedH = (4 + 3 * 34) * _gridH;

private _targetContentH = if (_newState) then { _expandedH } else { 36 * _gridH };

// Trigger the animated resize using the centralized resizing function
[_display, _targetContentH, 0.15] call A3A_fnc_builderUIResize;

// Update the button label to match the new state
private _ctrlToggleButton = _display displayCtrl 9711;
if (!isNull _ctrlToggleButton) then {
    _ctrlToggleButton ctrlSetText (if (_newState) then { "[-] Collapse" } else { "[+] Expand" });
};
