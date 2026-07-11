/*
    fn_teamLeaderRTSPlacerDialog.sqf
    Wrapper for Antistasi Ultimate's teamLeaderRTSPlacerDialog function.
    Resizes the builder dialog, injects the height toggle button, and adds auto-collapse on item selection.
*/
params[["_mode","onLoad"], ["_params",[]]];

// Call the original function to perform standard layout setup
_this call A3A_fnc_teamLeaderRTSPlacerDialog_original;

// Only resize and inject the button on onLoad mode on the client
if (_mode != "onLoad") exitWith {};
if (!hasInterface) exitWith {};

private _display = findDisplay 9700;
if (isNull _display) exitWith {};

private _gridH = pixelH * pixelGridNoUIScale * 0.5;
private _gridW = pixelW * pixelGridNoUIScale * 0.5;

// Retrieve the current expanded state (defaults to false, starting the menu collapsed at 1 row)
private _isExpanded = _display getVariable ["A3A_builder_expanded", false];

private _targetContentH = if (_isExpanded) then {
    (4 + 3 * 34) * _gridH;
} else {
    36 * _gridH;
};

// Call our resize function to apply the layout height immediately
[_display, _targetContentH, 0] call A3A_fnc_builderUIResize;

// --- DYNAMICALLY FIND TITLEBAR BACKGROUND FOR BUTTON ANCHORING ---
private _ctrlTitleBarBg = controlNull;
{
    private _pos = ctrlPosition _x;
    private _h = _pos select 3;
    if (ctrlIdc _x == -1 && { ctrlType _x == 0 && { isNull (ctrlParentControlsGroup _x) } }) then {
        if (_h <= 10 * _gridH && { (_pos select 2) > safeZoneW - (60 * _gridW) }) exitWith {
            _ctrlTitleBarBg = _x;
        };
    };
} forEach (allControls _display);

if (isNull _ctrlTitleBarBg) exitWith {
    diag_log "[A3A Tweaks] teamLeaderRTSPlacerDialog wrapper: Could not find titlebar background, aborting button creation.";
};

// Create or retrieve the toggle button (IDC 9711)
private _ctrlToggleButton = _display displayCtrl 9711;
if (isNull _ctrlToggleButton) then {
    _ctrlToggleButton = _display ctrlCreate ["A3A_Button", 9711];
    _ctrlToggleButton ctrlAddEventHandler ["ButtonClick", {
        [] call A3A_fnc_teamLeaderRTSPlacerDialog_toggleHeight;
    }];
};

// Position the toggle button anchored to the left of the money text
private _btnW = 24 * _gridW;
private _btnX = safeZoneX + safeZoneW - (80 * _gridW) - _btnW;
private _btnY = (safeZoneY + safeZoneH) - (_targetContentH + 5 * _gridH);

_ctrlToggleButton ctrlSetPosition [_btnX, _btnY, _btnW, 5 * _gridH];
_ctrlToggleButton ctrlSetText (if (_isExpanded) then { "[-] Collapse" } else { "[+] Expand" });
_ctrlToggleButton ctrlCommit 0;

// --- AUTO-COLLAPSE ON ITEM PLACEMENT SELECTION ---
// Add another Click handler to item buttons to collapse the menu when buying an item
{
    if (ctrlIdc _x == 9704) then {
        // If it's not a sub-menu and not a back button (<<<)
        if (isNil { _x getVariable "subMenu" } && { !(ctrlText _x select [0, 3] isEqualTo "<<<") }) then {
            _x ctrlAddEventHandler ["ButtonClick", {
                params ["_control"];
                private _display = ctrlParent _control;
                if (!isNull _display && { _display getVariable ["A3A_builder_expanded", false] }) then {
                    _display setVariable ["A3A_builder_expanded", false];
                    
                    private _gridH = pixelH * pixelGridNoUIScale * 0.5;
                    private _collapsedH = 36 * _gridH;
                    
                    // Collapse smoothly to 1 row
                    [_display, _collapsedH, 0.15] call A3A_fnc_builderUIResize;
                    
                    private _ctrlToggleButton = _display displayCtrl 9711;
                    if (!isNull _ctrlToggleButton) then {
                        _ctrlToggleButton ctrlSetText "[+] Expand";
                    };
                };
            }];
        };
    };
} forEach (allControls _display);

diag_log "[A3A Ultimate Tweaks Extender] Builder UI adjusted and Expand/Collapse button setup completed.";
