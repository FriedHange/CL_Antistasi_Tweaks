/*
    fn_planning_showNotification.sqf
    Creates a premium, high-visibility overlay notification card directly on the Commander Menu.
    Replaces standard hints which display behind the parent dialog.
*/
params [
    ["_title", "", [""]],
    ["_message", "", [""]],
    ["_isError", true, [true]]
];

if (!hasInterface) exitWith {};

private _display = findDisplay 60000;
if (isNull _display) exitWith {
    [_title, _message] call A3A_fnc_customHint;
};

private _uW = pixelGridNoUIScale * pixelW;
private _uH = pixelGridNoUIScale * pixelH;

// Container control IDC: 8080
private _ctrlGroup = _display displayCtrl 8080;
if (isNull _ctrlGroup) then {
    _ctrlGroup = _display ctrlCreate ["ScrtRscControlsGroup", 8080];
};

// Size and position: Top-center of the screen
private _notifW = 30 * _uW;
private _notifH = 5 * _uH;
private _notifX = safezoneX + (safezoneW - _notifW) / 2;
private _notifY = safezoneY + 2 * _uH;

_ctrlGroup ctrlSetPosition [_notifX, _notifY, _notifW, _notifH];
_ctrlGroup ctrlCommit 0;

// Clear previous notification children
{ ctrlDelete _x; } forEach (allControls _ctrlGroup);

// Main Card Background (Dark, semi-transparent grey)
private _ctrlBg = _display ctrlCreate ["TextBase", -1, _ctrlGroup];
_ctrlBg ctrlSetPosition [0, 0, _notifW, _notifH];
_ctrlBg ctrlSetBackgroundColor [0.15, 0.15, 0.15, 0.95];
_ctrlBg ctrlSetFade 0;
_ctrlBg ctrlCommit 0;

// Left-hand Aesthetic Accent Bar (Error Red or Success Green)
private _ctrlAccent = _display ctrlCreate ["TextBase", -1, _ctrlGroup];
_ctrlAccent ctrlSetPosition [0, 0, 0.4 * _uW, _notifH];
private _accentColor = if (_isError) then { [0.85, 0.25, 0.25, 1] } else { [0.25, 0.75, 0.25, 1] };
_ctrlAccent ctrlSetBackgroundColor _accentColor;
_ctrlAccent ctrlSetFade 0;
_ctrlAccent ctrlCommit 0;

// Structured Text for Title & Body Message
private _ctrlText = _display ctrlCreate ["RscStructuredText", -1, _ctrlGroup];
_ctrlText ctrlSetPosition [0.8 * _uW, 0.4 * _uH, _notifW - 1.2 * _uW, _notifH - 0.8 * _uH];
private _titleColor = if (_isError) then { "#ff5555" } else { "#55ff55" };
private _textStr = format [
    "<t font='PuristaBold' size='1.05' color='%1'>%2</t><br/><t size='0.85' color='#ffffff'>%3</t>",
    _titleColor,
    toupper _title,
    _message
];
_ctrlText ctrlSetStructuredText parseText _textStr;
_ctrlText ctrlSetFade 0;
_ctrlText ctrlCommit 0;

// Slide and fade-in transit
_ctrlGroup ctrlSetFade 0;
_ctrlGroup ctrlCommit 0.25;

// Local audio cue matching type
private _sound = if (_isError) then { "3DEN_notificationWarning" } else { "3DEN_notificationDefault" };
playSound _sound;

// Auto-dismiss script (Fade-out and clear controls group)
if (!isNil "A3A_planning_notifScript") then { terminate A3A_planning_notifScript; };
A3A_planning_notifScript = _ctrlGroup spawn {
    params ["_ctrlGroup"];
    sleep 4.5;
    if (!isNull _ctrlGroup) then {
        _ctrlGroup ctrlSetFade 1;
        _ctrlGroup ctrlCommit 0.5;
        sleep 0.5;
        if (!isNull _ctrlGroup) then {
            { ctrlDelete _x; } forEach (allControls _ctrlGroup);
        };
    };
};
