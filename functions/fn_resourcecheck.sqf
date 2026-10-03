/*
    fn_resourcecheck.sqf
    V12 resourcecheck loop with Point Campfire facility upgrades and TEH fork rules.
    Keep the town and income section in sync with the active Antistasi fork.
*/
if (!isServer) exitWith {
    diag_log "[A3A Ultimate Tweaks Extender] Server-only function miscalled: resourcecheck";
};

//declaring variables outside of the loop increases performance
private _resAdd = nil;
private _hrAdd = nil;
private _resBoost = nil;

private _rivalsTaskChance = 5;
private _traderTaskChance = 5;

private _cfg = (configFile >> "A3U" >> "traderAddons" >> "traderVehicles");

private _condition_AA = getText (_cfg >> "condition_AA");
private _condition_APC = getText (_cfg >> "condition_APC");
private _condition_ARMEDCAR = getText (_cfg >> "condition_ARMEDCAR");
private _condition_ARTILLERY = getText (_cfg >> "condition_ARTILLERY");
private _condition_BOAT = getText (_cfg >> "condition_BOAT");
private _condition_HELI = getText (_cfg >> "condition_HELI");
private _condition_PLANE = getText (_cfg >> "condition_PLANE");
private _condition_STATICAA = getText (_cfg >> "condition_STATICAA");
private _condition_STATICAT = getText (_cfg >> "condition_STATICAT");
private _condition_STATICMG = getText (_cfg >> "condition_STATICMG");
private _condition_STATICMORTAR = getText (_cfg >> "condition_STATICMORTAR");
private _condition_TANK = getText (_cfg >> "condition_TANK");
private _condition_UAV = getText (_cfg >> "condition_UAV");
private _condition_UNARMEDCAR = getText (_cfg >> "condition_UNARMEDCAR");

private _conditions = [
	[_condition_AA, "AA"], 
	[_condition_APC, "APCs"], 
	[_condition_ARMEDCAR, "Armed Cars"], 
	[_condition_ARTILLERY, "Artillery"], 
	[_condition_BOAT, "Boats"], 
	[_condition_HELI, "Helicopters"], 
	[_condition_PLANE, "Planes"], 
	[_condition_STATICAA, "Statics: AA"], 
	[_condition_STATICAT, "Statics: AT"], 
	[_condition_STATICMG, "Statics: MG"], 
	[_condition_STATICMORTAR, "Statics: Mortar"],
	[_condition_TANK, "Tanks"],
	[_condition_UAV, "UAVs"],
	[_condition_UNARMEDCAR, "Unarmed Cars"]
];

while {true} do {
	private _nextTick = time + 600;
	waitUntil {sleep 15; time >= _nextTick};
    waitUntil {sleep 10; A3A_activePlayerCount > 0};

	if (isNil "factories") then { factories = []; };
	if (isNil "seaports") then { seaports = []; };
	if (isNil "destroyedSites") then { destroyedSites = []; };
	if (isNil "citiesX") then { citiesX = []; };
	if (isNil "controlsX") then { controlsX = []; };
	if (isNil "resourcesX") then { resourcesX = []; };
	if (isNil "airportsX") then { airportsX = []; };
	if (isNil "milAdministrationsX") then { milAdministrationsX = []; };
	if (isNil "A3A_milAdministrations") then { A3A_milAdministrations = []; };
	if (isNil "antennasDead") then { antennasDead = []; };

	_resAdd = 25;
	_hrAdd = 0;

	_resBoost = 1 + (0.25*({(sidesX getVariable [_x,sideUnknown] == teamPlayer) and !(_x in destroyedSites)} count factories));
	private _pcfUpgradesEnabled = missionNamespace getVariable ["PCF_EnableResourceUpgrade", false];
	if (_pcfUpgradesEnabled) then {
		// Point Campfire adds 25% for every upgraded rebel factory.
		_resBoost = _resBoost + (0.25 * (missionNamespace getVariable ["A3UE_TotalRebelFactoryUpgrades", 0]));
	};

	{
		private _city = _x;
		private _resAddCity = 0;
		private _hrAddCity = 0;
		// V12 stores each town as [population, vehicles, government support, rebel support].
		private _cityData = A3A_townData get _city;
		_cityData params [["_numCiv", 0], ["_numVeh", 0], ["_supportGov", 0], ["_supportReb", 0]];
		private _citySide = sidesX getVariable [_city, sideUnknown];
		private _radioTowerSide = [_city] call A3A_fnc_getSideRadioTowerInfluence;

		_resAddCity = (_numCiv * (_supportReb / 100)) / 3;
		if (!finite _resAddCity) then { _resAddCity = 0; };
		private _hrMultiplier = overallHRGain / 100;
		if (_numCiv > 0 && { _hrMultiplier > 0 }) then {
			private _supportRebCapped = if (_citySide != teamPlayer) then { _supportReb min 15 } else { _supportReb };
			private _divider = 10000 * sqrt (_numCiv / 2000);
			_divider = (_divider max (5000 / _hrMultiplier)) min (10000 / _hrMultiplier);
			_hrAddCity = _numCiv * (_supportRebCapped / _divider);
		};

		if (_citySide != teamPlayer) then
		{
			_resAddCity = _resAddCity / 2;
		};
		if (_radioTowerSide != teamPlayer) then { _resAddCity = _resAddCity / 2 };

		_resAdd = _resAdd + _resAddCity;
		_hrAdd = _hrAdd + _hrAddCity;

		// Preserve V12's neutral band, destroyed-town lock, and one-battle-at-a-time rule.
		private _popReb = round (_numCiv * (_supportReb / 100));
		private _popGov = round (_numCiv * (_supportGov / 100));
		private _isNowEnemy = _popReb <= (_popGov * 0.667);
		private _isNowFriendly = _popReb >= (_popGov * 1.5);
		private _canFlipBase = !(_city in destroyedSites) && { !(_city in townSkirmishes) } && { _isNowEnemy || _isNowFriendly };
		private _canStartSkirmish = round _numCiv >= 20 && { random 100 <= townSkirmishChance } && { !(_city in townSkirmishes) };
		if (_canFlipBase && { _isNowFriendly } && { _citySide != teamPlayer }) then {
			if (_canStartSkirmish) then {
				private _origins = outposts select { sidesX getVariable [_x, sideUnknown] == _citySide };
				private _nearOrigins = _origins select { (getMarkerPos _x) distance2D (getMarkerPos _city) < 3000 };
				private _origin = selectRandom _nearOrigins;
				if (isNil "_origin") then { _origin = selectRandom _origins };
				if (!isNil "_origin") then {
					diag_log format ["[A3A Tweaks Town] Starting V12 town battle at %1 from %2 (%3).", _city, _origin, _citySide];
					[_citySide, _city, _origin] spawn A3A_fnc_townBattle;
					uiSleep 1;
				} else {
					[_city, true] call A3A_fnc_cityChangeSide;
				};
			} else {
				[_city, true] call A3A_fnc_cityChangeSide;
			};
		};
		if (_canFlipBase && { _isNowEnemy } && { _citySide == teamPlayer }) then {
			[_city, false] call A3A_fnc_cityChangeSide;
		};
	} forEach citiesX;

	call A3A_fnc_checkWinCondition;

	if (lossCondition isNotEqualTo 1) then {
		call A3A_fnc_checkLossCondition;
	};

	if (_pcfUpgradesEnabled) then {
		// Point Campfire boosts the full base and resource income, including upgraded sites.
		private _ownedResources = {sidesX getVariable [_x,sideUnknown] == teamPlayer && {!(_x in destroyedSites)}} count resourcesX;
		private _resourceUpgrades = missionNamespace getVariable ["A3UE_TotalRebelResourceUpgrades", 0];
		_resAdd = (_resAdd + (300 * (_ownedResources + _resourceUpgrades))) * _resBoost;
	} else {
		{
			if (sidesX getVariable [_x,sideUnknown] == teamPlayer and {!(_x in destroyedSites)}) then {
				_resAdd = _resAdd + (300 * _resBoost);
			};
		} forEach resourcesX;
	};

	// TEH charges a reserve salary based on the current HR pool at war tier 2+.
	private _hrCount = server getVariable ["hr", 0];
	private _hrReserveSalaries = 0;
	if (!isNil "TEH_hrSalaries" && {tierWar > 1}) then {
		_hrReserveSalaries = floor ((TEH_hrSalaries * skillFIA * _hrCount) / 100);
	};

	_resAdd = [_resAdd] call SCRT_fnc_common_rebelSalary;
	if (isNil "_resAdd" || {!finite _resAdd}) then {
    	_resAdd = 25000;
	};

	_hrAdd = round _hrAdd;
	_resAdd = round _resAdd;
	if (!finite _resAdd) then { _resAdd = 25000; }; //either number is too large or something is broken
	if (!finite _hrAdd) then { _hrAdd = 30; };
	server setVariable ["hr", _hrAdd + _hrCount, true];
	server setVariable ["resourcesFIA", _resAdd - _hrReserveSalaries + (server getVariable ["resourcesFIA", 0]), true];

	private _rebAirportsQuantity = {sidesX getVariable [_x,sideUnknown] == teamPlayer} count airportsX;
	bombRuns = bombRuns + 0.25 * _rebAirportsQuantity;
	publicVariable "bombRuns";

	if (bombRuns > (_rebAirportsQuantity * 2)) then {
		bombRuns = _rebAirportsQuantity * 2;
	};

	if(tierWar > 2) then {
        supportPoints = supportPoints + 1;
    };

    if(supportPoints > maxSupportPoints) then {
        supportPoints = maxSupportPoints;
    };

	publicVariable "supportPoints";

	private _currency = A3A_faction_civ get "currencySymbol";
	private _textX = format [localize "STR_comms_mp_taxes_income", _hrAdd, _resAdd, _currency, _hrReserveSalaries, _currency];
	private _textArsenal = [] call A3A_fnc_arsenalManage;
	if (_textArsenal != "") then {_textX = format [localize "STR_comms_mp_arsenal_updated", _textX, _textArsenal]};
	[petros, "taxRep", _textX] remoteExec ["A3A_fnc_commsMP", [teamPlayer, civilian]];

	[] call A3A_fnc_generateRebelGear;

	[] call A3A_fnc_FIAradio;
	[] call A3A_fnc_cleanConvoyMarker;

	[] spawn A3A_fnc_promotePlayer;
	[] call A3A_fnc_assignBossIfNone;

	// Clear out plank objects that haven't been constructed and have exceeded the timeout
	call A3A_fnc_processBuildingTimeouts;

	// Decrease HQ knowledge values, old ones faster than current
	if (A3A_curHQInfoOcc < 1) then { A3A_curHQInfoOcc = 0 max (A3A_curHQInfoOcc - 0.01) };
	if (A3A_curHQInfoInv < 1) then { A3A_curHQInfoInv = 0 max (A3A_curHQInfoInv - 0.01) };
	A3A_oldHQInfoOcc = A3A_oldHQInfoOcc select { _x set [2, _x#2 - 0.1]; _x#2 > 0 };			// arrays of [xpos, ypos, knowledge]
	A3A_oldHQInfoInv = A3A_oldHQInfoInv select { _x set [2, _x#2 - 0.1]; _x#2 > 0 };

	// Petros Random mission trigger chance (Applying customizable multiplier, capped at 50% max to avoid mission overload)
	private _rawRandomMult = missionNamespace getVariable ["A3A_tweak_randomMissionChanceMultiplier", 100];
	private _randomMult = if (_rawRandomMult > 5) then { _rawRandomMult / 100 } else { _rawRandomMult };
	private _missionChance = ((5 * A3A_activePlayerCount) * _randomMult) min 50;
	if (!isNil "TEH_hrSalaries" && {captive petros}) then { _missionChance = 0 };
	if ((!bigAttackInProgress) and (random 100 < _missionChance)) then {[] spawn A3A_fnc_missionRequest};

	//Removed from scheduler for now, as it errors on Headless Clients.
	//[[],"A3A_fnc_reinforcementsAI"] call A3A_fnc_scheduler;
	[] spawn A3A_fnc_reinforcementsAI;
	{
		_veh = _x;
		if ((_veh isKindOf "StaticWeapon") and {{isPlayer _x} count crew _veh == 0 and {alive _veh}}) then {
			_veh setDamage 0;
			[_veh,1] remoteExec ["setVehicleAmmo",_veh];
		};
	} forEach vehicles;
	sleep 3;
    _numWreckedAntennas = count antennasDead;
	//Probability of spawning a mission in.
    _shouldSpawnRepairThisTick = round(random 100) < 15;
    if (_numWreckedAntennas > 0 && {_shouldSpawnRepairThisTick && {!("REP" in A3A_activeTasks)}}) then {
		_potentials = [];
		{
			if (!isNil "_x" && {!isNull _x}) then {
				_markerX = [markersX, _x] call BIS_fnc_nearestPosition;
				if (sidesX getVariable [_markerX,sideUnknown] == Occupants and {spawner getVariable _markerX == 2}) exitWith {
					_potentials pushBack [_markerX,_x];
				};
			};
		} forEach antennasDead;
		if (count _potentials > 0) then {
			_potential = selectRandom _potentials;
			[[_potential select 0,_potential select 1],"A3A_fnc_REP_Antenna"] call A3A_fnc_scheduler;
		};
	} else {
		_changingX = false;
		{
			_chance = 5;
			if (_x in resourcesX and {sidesX getVariable [_x,sideUnknown] == Invaders}) then {
				_chance = 20
			};
			if (random 100 < _chance) then {
				_changingX = true;
				destroyedSites = destroyedSites - [_x];
				_nameX = [_x] call A3A_fnc_localizar;
				["TaskSucceeded", ["", format [localize "STR_notifiers_city_rebuilt",_nameX]]] remoteExec ["BIS_fnc_showNotification",[teamPlayer,civilian]];
				sleep 2;
			};
		} forEach ((destroyedSites - citiesX) select {sidesX getVariable [_x,sideUnknown] != teamPlayer});
		if (_changingX) then {publicVariable "destroyedSites"};
	};
	sleep 4;

	if (areRivalsEnabled && tierWar > 3 && !areRivalsDiscovered && !isRivalsDiscoveryQuestAssigned) then {
		diag_log format ["[A3A] Rivals roll: %1", _rivalsTaskChance];
		if (random 100 < _rivalsTaskChance) then {
			diag_log "[A3A] Assigning Rivals Discovery Task...";
			[] call SCRT_fnc_rivals_prepareQuest;
		} else {
			_rivalsTaskChance = [
				_rivalsTaskChance + 5,
				_rivalsTaskChance + 10
			] select (sunOrMoon < 1);
		};
	};

	private _traderTier = missionNamespace getVariable ["TEH_TraderWarTierReq", 3];
	if (tierWar >= _traderTier && !isTraderQuestCompleted && !isTraderQuestAssigned) then {
		diag_log format ["[A3A] Arms Dealer roll: %1", _traderTaskChance];
		if (random 100 < _traderTaskChance) then {
			diag_log "[A3A] Assigning Arms Dealer Task...";
			[] remoteExec ["SCRT_fnc_trader_prepareTraderQuest", 2];
		} else {
			_traderTaskChance = _traderTaskChance + 2;
		};
	};

	if (areRivalsDiscovered && {!areRivalsDefeated}) then{
		[random [5,7,10]] call SCRT_fnc_rivals_addProgressToRivalsLocationReveal;
	};

	if (isTraderQuestCompleted) then {
		private _vehicleTypesUnlocked = unlockedVehicleTypes;
		private _vehicleTypesUnlockedNotify = [];

		if (isNil "_vehicleTypesUnlocked") then {
			_vehicleTypesUnlocked = [];
		};

		{
			private _condition = compile (_x#0);

			private _alreadyUnlocked = ((_x#1) in _vehicleTypesUnlocked);
			if (_alreadyUnlocked) then {continue};

			if (call _condition) then {
				private _text = format["%1 is now unlocked in the Arms Dealer.", (_x#1)];

				_vehicleTypesUnlocked pushBack (_x#1);
				_vehicleTypesUnlockedNotify pushBack (_x#1);
				
				diag_log _text;
			};
		} forEach _conditions;

		if (_vehicleTypesUnlockedNotify isEqualTo []) exitWith {false};

		private _unlockedMessages = "The following vehicles have been unlocked at the Arms Dealer.<br/>"; // To-Do: Localize

		{
			private _vehicleType = _x;
			_unlockedMessages = _unlockedMessages + "<br/>" + _vehicleType; // <br/> vehicleType <br/>
		} forEach _vehicleTypesUnlocked;

		[localize "STR_marker_arms_dealer", _unlockedMessages] remoteExec ["A3A_fnc_customHint", 0, false];

		unlockedVehicleTypes = _vehicleTypesUnlocked;
		
		publicVariable "unlockedVehicleTypes";
	};
};
