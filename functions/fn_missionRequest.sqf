/*
    fn_missionRequest.sqf
    Wrapper for Antistasi Ultimate's missionRequest function to support manual cooldowns.
*/
params ["_type", ["_requester", clientOwner], ["_silent", false]];

private _cooldown = (missionNamespace getVariable ["A3A_tweak_missionCooldown", 0]) * 60; // Convert minutes to seconds

// Only apply cooldown check on manual requests (not silent/random ones triggered by resource checks)
if (_cooldown > 0 && {!_silent}) then {
    private _lastTime = missionNamespace getVariable ["A3A_tweak_lastMissionTime", -9999];
    private _timeLeft = _lastTime + _cooldown - time;
    if (_timeLeft > 0) exitWith {
        private _minsLeft = ceil (_timeLeft / 60);
        private _timeMsg = if (_minsLeft > 1) then { format ["%1 minutes", _minsLeft] } else { format ["%1 seconds", round _timeLeft] };
        [petros, "globalChat", format ["I need a break. Ask me again in %1.", _timeMsg]] remoteExec ["A3A_fnc_commsMP", _requester];
        
        // Reset the request lock flag
        A3A_missionRequestInProgress = nil;
    };
};

private _prevActive = +A3A_activeTasks;

// Execute the original native mission request
_this call A3A_fnc_missionRequest_original;

// Monitor if a task is successfully created (runs asynchronously on server)
if (!_silent) then {
    [_prevActive, _requester] spawn {
        params ["_prevActive", "_requester"];
        sleep 2; // wait a moment for the scheduler/mission script to spawn and register the task
        
        // If the number of active tasks increased, the mission request was successful
        if (count (A3A_activeTasks - _prevActive) > 0) then {
            missionNamespace setVariable ["A3A_tweak_lastMissionTime", time, true];
            diag_log "[A3A Tweaks] Petros manual mission request succeeded. Cooldown timer started.";
        };
    };
};
