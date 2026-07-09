/* ----------------------------------------------------------------------------
Function: A3A_fnc_isWithinMarkerArea

Description:
    Overridden version to support custom base save radius tweaks.
    Check if a given position/object is within the area of a specified marker.

    For zero-size markers, assume a default radius of
    A3A_zeroSizeMarkerBlowup meters plus any custom buffer.

Parameters:
    0: _position - The position/object to check <ARRAY,OBJECT>
    1: _markerName - The name of the marker <STRING>

Optional:
    2: _zeroSizeRadius - The radius to use if the marker size is zero <SCALAR>
        (Default: A3A_zeroSizeMarkerBlowup)

Returns:
    <BOOL> True if the position is within the marker area, false otherwise.
---------------------------------------------------------------------------- */
params [
    ["_position", nil, [objNull, []]],
    ["_markerName", nil, [""]],
    ["_zeroSizeRadius", -1, [0]]
];

if (isNil "_position" || isNil "_markerName") exitWith { false };
if (_position isEqualType objNull && { isNull _position }) exitWith { false };
if (markerType _markerName isEqualTo "") exitWith { false };

// Get custom parameters
private _customHQRadius = missionNamespace getVariable ["A3A_tweak_saveRadiusHQ", 50];
private _customBuffer = missionNamespace getVariable ["A3A_tweak_saveRadiusBuffer", 0];

private _width = markerSize _markerName select 0;
private _height = markerSize _markerName select 1;

if (_markerName isEqualTo "synd_hq") then {
    _width = _customHQRadius;
    _height = _customHQRadius;
} else {
    // If it's a zero size marker, we use the custom HQ radius or the default zeroSizeMarkerBlowup + buffer
    if (_width == 0 && _height == 0) then {
        private _defaultRadius = if (_zeroSizeRadius >= 0) then { _zeroSizeRadius } else { (missionNamespace getVariable ["A3A_zeroSizeMarkerBlowup", 50]) };
        _width = _defaultRadius + _customBuffer;
        _height = _defaultRadius + _customBuffer;
    } else {
        // Standard marker with buffer
        _width = _width + _customBuffer;
        _height = _height + _customBuffer;
    };
};

private _pos = if (_position isEqualType objNull) then { getPos _position } else { _position };
_pos inArea [
    markerPos _markerName,
    _width,
    _height,
    markerDir _markerName,
    markerShape _markerName isEqualTo "RECTANGLE"
];
