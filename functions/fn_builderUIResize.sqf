/*
    fn_builderUIResize.sqf
    Resizes the Teamleader Builder dialog at runtime using correct pixel grid values.
    Supports animated transitions and works on all UI scales.

    Arguments:
        0: _display (Display)
        1: _targetContentH (Scalar) - Target height of the content group in meters (usually N * GRID_H)
        2: _commitTime (Scalar, optional) - Time in seconds to animate the change (default: 0)
*/
params [
    ["_display", displayNull, [displayNull]],
    ["_targetContentH", 0, [0]],
    ["_commitTime", 0, [0]]
];

if (isNull _display) exitWith { false };

// Calculate GRID units at runtime (same formula as Antistasi defines.hpp)
private _gridH = pixelH * pixelGridNoUIScale * 0.5;
private _gridW = pixelW * pixelGridNoUIScale * 0.5;
private _bottom = safeZoneY + safeZoneH;

// --- DYNAMIC CONTROL FINDER ---
// Filter for root-level controls only (no parent controls group) to avoid picking up 
// dynamically created child elements inside the scrolling item grid.
private _ctrlBg = controlNull;
private _ctrlTitleBarBg = controlNull;
private _ctrlTitleText = controlNull;

{
    private _pos = ctrlPosition _x;
    private _h = _pos select 3;
    private _idc = ctrlIdc _x;
    if (_idc == -1 && { ctrlType _x == 0 && { isNull (ctrlParentControlsGroup _x) } }) then {
        if (_h > 10 * _gridH) then {
            _ctrlBg = _x;
        } else {
            // TitleBarBackground is wider: safeZoneW - 40 * GRID_W
            // TitlebarText is narrower: safeZoneW - 80 * GRID_W
            // We use safeZoneW - 60 * GRID_W as the dividing threshold
            if ((_pos select 2) > safeZoneW - (60 * _gridW)) then {
                _ctrlTitleBarBg = _x;
            } else {
                _ctrlTitleText = _x;
            };
        };
    };
} forEach (allControls _display);

private _ctrlMoneyText = _display displayCtrl 9707;
private _ctrlMainContent = _display displayCtrl 9701;
private _ctrlBuildGroup = _ctrlMainContent controlsGroupCtrl 9702;

if (isNull _ctrlMainContent) exitWith { false };

private _totalH = _targetContentH + (5 * _gridH);
private _itemGridH = _targetContentH - (4 * _gridH);

// --- APPLY POSITION CHANGES (using absolute math to avoid race conditions with animations) ---

// Main Content Container
private _mainPos = ctrlPosition _ctrlMainContent;
_ctrlMainContent ctrlSetPosition [_mainPos select 0, _bottom - _targetContentH, _mainPos select 2, _targetContentH];
_ctrlMainContent ctrlCommit _commitTime;

// Inner Scrollable Build Group
if (!isNull _ctrlBuildGroup) then {
    private _bgPos = ctrlPosition _ctrlBuildGroup;
    _ctrlBuildGroup ctrlSetPosition [_bgPos select 0, _bgPos select 1, _bgPos select 2, _itemGridH];
    _ctrlBuildGroup ctrlCommit _commitTime;
};

// Main Background Panel
if (!isNull _ctrlBg) then {
    _ctrlBg ctrlSetPosition [safeZoneX, _bottom - _targetContentH, safeZoneW - (40 * _gridW), _targetContentH];
    _ctrlBg ctrlCommit _commitTime;
};

// Title Bar Background Panel
if (!isNull _ctrlTitleBarBg) then {
    _ctrlTitleBarBg ctrlSetPosition [safeZoneX, _bottom - _totalH, safeZoneW - (40 * _gridW), 5 * _gridH];
    _ctrlTitleBarBg ctrlCommit _commitTime;
};

// Title Bar Text
if (!isNull _ctrlTitleText) then {
    _ctrlTitleText ctrlSetPosition [safeZoneX, _bottom - _totalH, safeZoneW - (80 * _gridW), 5 * _gridH];
    _ctrlTitleText ctrlCommit _commitTime;
};

// Money Text
if (!isNull _ctrlMoneyText) then {
    _ctrlMoneyText ctrlSetPosition [safeZoneX + safeZoneW - (80 * _gridW), _bottom - _totalH, 40 * _gridW, 5 * _gridH];
    _ctrlMoneyText ctrlCommit _commitTime;
};

// Update Expand/Collapse Toggle Button (IDC 9711) Position
private _ctrlToggleButton = _display displayCtrl 9711;
if (!isNull _ctrlToggleButton) then {
    private _btnW = 24 * _gridW;
    private _btnX = safeZoneX + safeZoneW - (80 * _gridW) - _btnW;
    private _btnY = _bottom - _totalH;
    _ctrlToggleButton ctrlSetPosition [_btnX, _btnY, _btnW, 5 * _gridH];
    _ctrlToggleButton ctrlCommit _commitTime;
};

true
